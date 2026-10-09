"""最小无头内核原型（Python）

用途：验证 docs/design/ 里的公式与不变式；Godot 版（scripts/core/）可据此移植。
依据：docs/design/统一影响公式.md、信念矩阵.md、NPC行为决策.md、主文档 §3/§5–§10
运行：python tools/core_sim.py --days 1 --seed 12345

实现范围（「最小」= 够验证公式，不追求全部行为）：
  · 时间：天 / 相位（课间×3、上课×2）/ tick（课间 100、上课 90）
  · 状态：A/H/T 有向矩阵、O/Stress 个体量、MBTI 四维
  · 统一影响公式：E × 性格倍率 × 关系调制 → +β·C → 软饱和 → round(0.1) → 写入
  · 传导：阈值 + 竞争归一化 + **感知值**，每 settle_interval 结算
  · 信念矩阵：B_A/B_B/B_T，观测噪声由对方透明度决定、学习率由信任决定
  · 行为：闲聊（环境类）、搭话（意向类）、举报（阈值类）—— 覆盖三类触发
  · 跨天：衰减 + 座位重排（简化为随机重排相邻关系）
"""

import argparse
import csv
import math
import os
import random
from player_invitations import PlayerInvitations, invitation_behavior

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

AXES = ("affinity", "hostility", "trust")

# 主动行为的冷却（tick）：每角色每这么久最多发起一次行为
# ⚠️ 文档未规定，属实现补充；待标定（见 docs/design/NPC行为决策.md 待确认）
ACTION_COOLDOWN = 20
DIMS = ("e", "n", "f", "p")


# ---------------------------------------------------------------- 工具
def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def clamp100(v):
    return clamp(v, 0.0, 100.0)


def r1(v):
    """全局精度：四舍五入到 0.1（统一影响公式 §2.3）"""
    return round(v, 1)


def sigmoid(z):
    """logistic 函数：p ∈ (0,1)，没有 0/1 硬闸门（§6.4）"""
    if z >= 0:
        return 1.0 / (1.0 + math.exp(-z))
    e = math.exp(z)
    return e / (1.0 + e)


def softmax(scores, tau, rng):
    if tau <= 0:
        raise ValueError("tau 必须 > 0（NPC行为决策 §8 不变式 5）")
    m = max(scores)
    exps = [math.exp((s - m) / tau) for s in scores]
    total = sum(exps)
    r = rng.random() * total
    acc = 0.0
    for i, e in enumerate(exps):
        acc += e
        if r <= acc:
            return i
    return len(scores) - 1


def load_params(rel):
    with open(os.path.join(DATA, rel), encoding="utf-8") as f:
        rows = [r for r in f if not r.startswith("#")]
    return {row["param"]: float(row["value"]) for row in csv.DictReader(rows)}


def load_table(rel):
    with open(os.path.join(DATA, rel), encoding="utf-8") as f:
        rows = [r for r in f if not r.startswith("#")]
    return list(csv.DictReader(rows))


# ---------------------------------------------------------------- 内核
class Sim:
    def __init__(self, seed=12345, npc_count=16, verbose=False):
        self.rng = random.Random(seed)
        self.seed = seed
        self.verbose = verbose

        # --- 配置 ---
        self.p = load_params("rules/transmission.csv")
        self.bp = load_params("rules/belief.csv")
        self.probs = {r["behavior"]: float(r["base_p"]) for r in load_table("rules/behavior_probs.csv")}
        self.thresholds = load_table("rules/behavior_thresholds.csv")
        # 阈值查表：键为 `<behavior>_<metric>`（同一行为可有多个指标，如调侃的两档）
        self.thresholds_lookup = {"%s_%s" % (r["behavior"], r["metric"]): float(r["value"])
                                  for r in self.thresholds}
        # decay.csv 采用 param,value 标量风格（注意键名已由 axis 改为 param）
        self.decay = {r["param"]: float(r["value"]) for r in load_table("rules/decay.csv")}
        # 行为主表：行为 -> {duration, payoff, kind}（含“收益越大耗时越长”法则）
        self.behaviors = {r["behavior"]: {"duration": int(float(r["duration"])),
                                         "payoff": float(r["payoff"]),
                                         "kind": r["kind"],
                                         "noise": float(r.get("noise", 0)),
                                         "join_mode": (r.get("join_mode") or "none").strip()}
                          for r in load_table("rules/behaviors.csv")}
        # 「当前活动」的分组查询用：谁此刻正在做哪个活动
        self.activity_log = []            # 每段一个快照（只读查询用，不参与结算）
        # 负反馈：传导增益随目标容纳度衰减（来自 transmission.csv 的 feedback）
        self.feedback = self.p.get("feedback", 0.0)
        self.event_rows = load_table("balance/w_events.csv")
        self.nw = load_params("balance/npc_weight" + "s.csv")
        seeds = load_table("characters/seeds.csv")

        # --- 抽角色（简化：随机取 npc_count 个；§11.5 的绑定组/原型去重留待正式版）---
        pool = seeds[:]
        self.rng.shuffle(pool)
        self.chars = pool[:npc_count]
        self.N = npc_count + 1  # 索引 N-1 为玩家

        # --- 状态矩阵 ---
        n = self.N
        self.A = [[0.0] * n for _ in range(n)]
        self.H = [[0.0] * n for _ in range(n)]
        # 深层敌对（§10.22）：只由 tier=major 的负性事件写入，**永不衰减**。
        # H 存的仍是「总敌对」，H_deep 是其中「忘不掉的那一部分」。
        self.H_deep = [[0.0] * n for _ in range(n)]
        # 施害者一侧的证据（§8.4 修订）：最近一次「i 对 j 做过敌对行为」的日。
        # 排挤的判据要用它 —— 集体排斥的证据在**施害者**一侧，不在受害者一侧。
        self.hurt_day = [[-10 ** 9] * n for _ in range(n)]
        # 排挤冷却：同一目标多少天内不再被重复驱逐。
        # 「孤立某人」是一个**状态**而不是反复的动作 —— 没有冷却时同一人一天被排挤 9 次（实测）。
        self.exclude_last_day = [-10 ** 9] * n
        self.T = [[0.0] * n for _ in range(n)]
        self.O = [0.0] * n
        self.Stress = [0.0] * n
        self.dims = [[50.0] * 4 for _ in range(n)]  # E N F P

        # --- 信念矩阵：B_X[i][j] = i 估计的「j 对 i 的 X」---
        self.B = {ax: [[0.0] * n for _ in range(n)] for ax in AXES}
        prior = {"affinity": self.bp["prior_a"], "hostility": self.bp["prior_h"], "trust": self.bp["prior_t"]}
        for i in range(n):
            for j in range(n):
                for ax in AXES:
                    self.B[ax][i][j] = prior[ax]

        # --- 初始化 ---
        for i, ch in enumerate(self.chars):
            self.O[i] = float(ch.get("opacity_init") or 50)
            self.dims[i] = [float(ch[k]) for k in DIMS]
        self.O[n - 1] = 50.0
        self.dims[n - 1] = [50.0] * 4
        self._init_relations()
        self._init_belief_bias()   # 按 信念矩阵.md §3：初始值 = 先验 + 性格偏差

        # --- 时间与统计 ---
        self.day = 1
        self.phase = "break"
        self.tick_in_phase = 0
        self.stats = {"events": 0, "chats": 0, "joins": 0, "reports": 0, "bursts": 0,
                      "interrupts": 0,
                      "transmission_ticks": 0, "skipped_events": 0, "dedup_skips": 0,
                      "teases": 0, "tease_fail": 0, "rumors": 0, "excludes": 0,
                      "roughhouse": 0, "sleeps": 0,
                      "comforts": 0, "helps": 0, "help_rejects": 0,
                      "apologizes": 0, "apologize_rejects": 0}
        # 事件去重：同一对子同一规则每课间段只结算一次（统一影响公式 §2.5.4）
        self.settled = set()
        self.phase_index = 0
        self.global_tick = 0
        self.next_action = [0] * n
        # --- 空间层：节点在教室里的真实平面位置（米，世界坐标；由表现层 / 内核空间层写入）---
        # 依据：主文档 §10.5 / §15.1；策划 2026-10-07 裁决第 4 项「加临时位置与交互范围」。
        # ⚠️ 本层**只记录**：内核不自己算移动，也不因位置改变任何矩阵 —— 位置只用于
        #    范围判定与展示。真实空间版启用后，交互范围判定会读这里（见 can_interact_with）。
        self.pos_x = [0.0] * n
        self.pos_z = [0.0] * n
        self.busy_until = [0] * n        # 忙碌到何时（按行为 duration，替代统一冷却）
        self.busy_phase = [-1] * n       # 行为开始时的相位序号（用于判定「被下课铃打断」）
        # 占用中的行为名（含 quiet 一方：current_act 会被清成 None，「被动参与」也要记得住）
        self.busy_act = [None] * n
        # 本 tick **刚完成**的行为（到期收尾时写入），给「行为完成才发信息」做挂点（如玩家闲聊线索）
        self.last_finished = [None] * n
        # --- 环境层（班级级标量，不是第六轴，而是与个体/关系并列的第三层）---
        self.env = {r["param"]: float(r["value"]) for r in load_table("rules/environment.csv")}
        self.volume = self.env.get("init_volume", 20.0)
        self.tag_rows = {r["tag_id"]: r for r in load_table("rules/tags.csv")}
        # 每个角色持有的标签（来自 seeds.csv 的 tags 列，"|" 分隔）
        self.character_tags = [
            [t2 for t2 in (c.get("tags") or "").split("|") if t2] for c in self.chars
        ] + [[]]                                 # 末位是玩家（无标签）
        # 相位 -> 允许的行为集（§3.3：上课段只跑规则子集；"all" = 全部允许）
        self.phase_rules = {r["phase_id"]: (r["active_rules"] or "none").split("|")
                            for r in load_table("rules/phases.csv")}
        self.phase_order = [r["phase_id"] for r in load_table("rules/phases.csv")]
        self.current_act = [None] * n     # 当前正在做/刚做完的行为（供音量统计）
        self.vol_log = []                 # 每个相位末的音量（标定观测用）
        self.sleeping = [False] * n       # 睡觉中（§10.8）：本课间不做别的事，且别人不能与之交互
        # --- 举报把柄（§10.2）：目击到的「标签行为痕迹」虚拟层 ---
        self.witness_day = [[-999] * n for _ in range(n)]   # witness_day[i][j] = i 最近目击 j 违规的日
        # --- 空间层（§15.1、§10.17.2 种子一）：座位表 + 邻接 ---
        self.seats = load_table("rules/seats.csv")
        self.seat_pos = {r["seat_id"]: (int(r["row"]), int(r["col"])) for r in self.seats}
        self.seat_of = [None] * n         # 角色 -> seat_id
        self.neighbors = self._build_neighbors()
        self.assign_seats()               # 必须在 seats/neighbors 定义之后
        self.in_conversation = [False] * n
        self.knot_days = [0] * n        # 「心结」剩余天数（参数来自 status_tags.csv）
        self.status_tags = {r["tag_id"]: r for r in load_table("rules/status_tags.csv")}
        self.day_events = {}            # (i,j) -> 当天事件类结算次数，用于「有互动」判定
        self.player_invitations = PlayerInvitations(
            self, load_table("rules/player_invitation_kinds.csv"),
            load_params("rules/player_interaction.csv"))

    def get_player_invitation(self):
        return self.player_invitations.pending()

    def respond_player_invitation(self, invitation_id, accepted):
        return self.player_invitations.respond(invitation_id, accepted)

    def _build_neighbors(self):
        """按 8 邻域（相邻 ≤1 格）建立邻接表；讲桌旁（row 0）与第一排（row 1）相邻。

        邻接是**对称**的。这张表是「边数摊薄」的解药 —— 交互只在**固定邻居**之间反复发生，
        而不是在 272 条边上随机撒点。
        """
        ids = [r["seat_id"] for r in self.seats]
        nb = {sid: set() for sid in ids}
        for a in ids:
            ra, ca = self.seat_pos[a]
            for b in ids:
                if a == b:
                    continue
                rb, cb = self.seat_pos[b]
                if max(abs(ra - rb), abs(ca - cb)) <= 1:
                    nb[a].add(b)
        return {k: sorted(v) for k, v in nb.items()}

    def assign_seats(self):
        """把本局角色分配到座位上（同种子同座位），并算出「谁是我的邻居」。"""
        ids = [r["seat_id"] for r in self.seats]
        self.rng.shuffle(ids)
        for i in range(self.N):
            self.seat_of[i] = ids[i]
        self.neighbor_idx = [[k for k in range(self.N)
                              if self.seat_of[k] in self.neighbors[self.seat_of[i]]]
                             for i in range(self.N)]

    def are_neighbors(self, i, j):
        """i 与 j 是否相邻（≤1 格）。"""
        return j in self.neighbor_idx[i]

    # ------------------------------------------------ 初始化关系
    def _init_relations(self):
        n = self.N
        for i in range(n):
            for j in range(n):
                if i == j:
                    continue
                self.A[i][j] = clamp100(20 + self.rng.random() * 20)
                self.H[i][j] = clamp100(self.rng.random() * 15)
                self.T[i][j] = clamp100(20 + self.rng.random() * 20)
        # 环境事实（§11.3）：小情侣绑定、佳豪对外好感 50
        idx = {c["alias"]: k for k, c in enumerate(self.chars)}
        if "陈阳" in idx and "林晚" in idx:
            a, b = idx["陈阳"], idx["林晚"]
            self.A[a][b] = self.A[b][a] = 85.0
            self.T[a][b] = self.T[b][a] = 80.0
        if "佳豪" in idx:
            g = idx["佳豪"]
            for j in range(n):
                if j != g:
                    self.A[g][j] = 50.0

    def _init_belief_bias(self):
        """按 `docs/design/信念矩阵.md` §3 补**初始信念偏差**。

        文档规定：`B_X[i][j] = prior_X + bias_X(j) × w_bias`，其中
            bias_A(j) = +k · [ (E_j−50)/50·0.5 + (F_j−50)/50·0.5 ]   外向 / 共情型「显得友善」→ 被高估好感
            bias_H(j) = −bias_A(j)                                    同一人显得友善 → 被低估敌对
            bias_T(j) = 0                                             信任没有「看起来」这回事

        要点：**偏差是性格的函数，不是随机数** —— 让「话痨型总被高估亲近、冰山型总被低估好感」
        成为**可预测的系统性错觉**。

        ⚠️ 此前实现只写了纯先验（`B = prior`，全员同一值），漏了本项；
        后果是开局**所有人对所有人的猜测完全相同**，既失去系统性错觉，也让搭话判据在开局无分化。
        """
        w = self.bp["w_bias"]
        k = self.bp.get("bias_observer_k", 0.0)
        tr = self.bp.get("bias_trust_ratio", 0.0)

        def perceived(j):
            """对方「看起来」多友善：外向 + 共情 → 显得友善（被观察者项）"""
            return (self.dims[j][0] - 50.0) / 50.0 * 0.5 + (self.dims[j][2] - 50.0) / 50.0 * 0.5

        def observer(i):
            """我自己多倾向于把人往好处想：共情 + 外向 → 乐观（观察者项）"""
            return (self.dims[i][2] - 50.0) / 50.0 * 0.5 + (self.dims[i][0] - 50.0) / 50.0 * 0.5

        for i in range(self.N):
            for j in range(self.N):
                if i == j:
                    continue
                # 双方性格共同决定：对方的可见特质 × 我自己的乐观程度
                bias_a = w * perceived(j) * (1.0 + k * observer(i))
                self.B["affinity"][i][j] = clamp100(self.B["affinity"][i][j] + bias_a)
                self.B["hostility"][i][j] = clamp100(self.B["hostility"][i][j] - bias_a)
                # 信任只受**观察者**影响（对方"看起来"与否无关）：乐观者更易先信任
                self.B["trust"][i][j] = clamp100(self.B["trust"][i][j] + tr * w * observer(i) * 0.1)

    # ------------------------------------------------ 派生量
    def mult_personality(self, row, i):
        """性格倍率 clamp(1 + Σw·d, 0.1, 1.2)"""
        w = [float(row["w_e"]), float(row["w_s"]), float(row["w_f"]), float(row["w_j"])]
        d = [(self.dims[i][k] - 50.0) / 50.0 for k in range(4)]
        return clamp(1.0 + sum(w[k] * d[k] for k in range(4)), 0.1, 1.2)

    def m_relation(self, i, j, tier="normal"):
        """关系调制 M = clamp((A − H)/50, −1, +1)

        **边界②：重大档（tier=major）禁止被关系反转** —— 取 max(0, M)，即"允许削弱、禁止翻转符号"。
        否则「我们关系好，所以他举报我反而是好事」会塌掉欺凌线与信任崩塌线
        （`report_hostility` / `leak_hostility` / `leak_trust` 都是 major）。
        常规档保留反转：关系差时「聊了反而掉好感」是设计意图（§2.1）。
        ⚠️ 注意不是 max(0, M)：那样关系差时伤害会归零，等于"被讨厌就不会被伤害"，同样不合理。
        重大事件的语义是**伤害与关系无关**（关系好坏都会被举报，伤害一样）→ 直接不调制。
        """
        return clamp((self.A[i][j] - self.H[i][j]) / 50.0, -1.0, 1.0)

    def m_state(self, i, negative):
        """压力区间系数（§6.2）：负面事件更敏感"""
        s = self.Stress[i]
        if s < 40:
            return 1.0
        if s < 70:
            return 1.5 if negative else 0.75
        if s < 90:
            return 1.5
        return 1.0

    def room_for(self, axis, value):
        """负反馈：正向轴越接近饱和，增益越小（负面轴不适用）。

        · 好感 / 信任：越满越难涨 —— 这就是阻止「30 天全班一起封顶」的机制
        · 敌对 / 压力：不加负反馈，否则「敌意升级」会被压死
        """
        if self.feedback <= 0 or axis in ("hostility", "stress"):
            return 1.0
        return max(0.0, 1.0 - self.feedback * value / 100.0)

    def sat(self, u, axis):
        key = {"affinity": "u_a", "hostility": "u_h", "trust": "u_t", "stress": "u_s"}[axis]
        U = self.p.get(key, 25.0)
        return u / (1.0 + abs(u) / U)

    # ------------------------------------------------ 事件写入
    def apply_event(self, i, j, event_id, scale=1.0, no_modulation=False):
        """按统一影响公式写入：E × 性格 × 关系调制 → 软饱和 → round(0.1) → clamp

        含事件去重：同一对子同一规则每课间段只结算一次（§2.5.4）

        `scale`：**外部幅度系数**（默认 1.0）—— 让「同一事件」随情境强弱缩放，
        例如音量越吵、怕吵者的敌对越重。它与 `base` 相乘、仍走同一套公式，
        不是旁路写入（保持 §2.6 的单一写入点）。

        `no_modulation`：跳过**关系调制** `M(i,j)`（与 `tier=major` 同口径，§7.1 边界②）。
        用于**修复类行为**：道歉的发起门槛保证 `H ≥ 30` → `M` 常为负 → 常规档会把
        「敌对回落」乘以负的 `M` **翻成敌对上升**、「好感回升」翻成好感下降 ——
        即「越道歉越糟」。修复行为与 `M` 的冲突是结构性的，故整条行为不走调制。
        """

        dkey = (i, j, event_id, self.day, self.phase_index)
        if dkey in self.settled:
            self.stats["dedup_skips"] += 1
            return False
        self.settled.add(dkey)
        self.day_events[(i, j)] = self.day_events.get((i, j), 0) + 1
        applied = False
        for row in self.event_rows:
            if row["event_id"] != event_id:
                continue
            axis = row["axis"]
            base = float(row["base"])
            e_val = base * scale * self.mult_personality(row, i)
            if axis in AXES:
                # 边界②：重大档不做关系调制（M_eff = 1）
                #   否则「关系好 → 举报反而是好事」会塌掉欺凌线与信任崩塌线；
                #   也不是 max(0, M)（那样关系差时伤害归零，等于「被讨厌就不会被伤害」）
                if row.get("tier", "normal") != "major" and not no_modulation:
                    e_val *= self.m_relation(i, j)
            p_val = e_val + (0.0 if axis == "stress" else 0.0)  # 事件侧不含传导
            m = self.m_state(i, negative=(base < 0) == (axis in AXES))
            delta = r1(m * self.sat(p_val, axis)) if axis != "stress" else r1(self.sat(p_val, axis))
            # ⚠️ `hurt_day` **不在此处维护**（2026-10-07 修）：本方法的 (i, j) 是
            #    「被作用方 → 作用方」，而读者（§10.25 排挤、§10.24 从众）要的是
            #    「施害者 → 受害者」—— 两者在一次调用里恰好相反，曾使**受害者被误记为施害者**。
            #    改由**调用点**用 `mark_hurt(施害者, 受害者)` 显式记录。
            if axis == "hostility" and row.get("tier") == "major":
                # 重大负性事件 → 同时写入**永不衰减**的深层（§10.22）。
                # ⚠️ 不经 room_for：负反馈是给「表层摩擦」用的，若也套在深层上，
                #    仇恨会自己封顶（越满越涨不动），「不可消减」就名存实亡了。
                # 深层**软上限**（§10.27）：不会一路涨到 100。
                # 「恨到顶了」——到了上限就不再加深，但**永不回落**（忘不掉依然成立）。
                # 总 H 仍可更高（深层 + 表层），所以「死仇」的强度不被压平，只是不再无限堆积。
                cap = self.env.get("deep_cap", 70.0)
                self.H_deep[i][j] = min(cap, self.H_deep[i][j] + abs(delta))
                self.stats["deep_writes"] = self.stats.get("deep_writes", 0) + 1
            if axis == "stress":
                self.Stress[i] = clamp100(self.Stress[i] + delta)
            else:
                target = {"affinity": self.A, "hostility": self.H, "trust": self.T}[axis]
                # 统一写入点：正向轴乘负反馈（越满越难涨）
                delta = r1(self.room_for(axis, target[i][j]) * delta)
                target[i][j] = clamp100(target[i][j] + delta)
            applied = True
            self.stats["events"] += 1
        return applied

    def mark_hurt(self, perpetrator, victim):
        """记录「施害者 → 受害者」的最近一次**重大**敌对行为（§10.25 排挤判据、§10.24 从众判据）。

        ⚠️ 只在 `tier = major` 的事件调用点使用 —— 日常摩擦（`noise_hostility` 等）每天让
        几乎所有人互相「损害」，若一并记录，「被 3 人损害」会成为常态、排挤天天发生
        （实测 268 次 / 30 天）。「被欺负」指的是**严重**的事：当众羞辱、举报、秘密泄露。
        """
        self.hurt_day[perpetrator][victim] = self.day

    # ------------------------------------------------ 传导（涓流）
    def transmission(self):
        """阈值 + 竞争归一化 + 感知值；每 settle_interval 结算一次"""
        n = self.N
        th = {"affinity": self.p["theta_a"], "hostility": self.p["theta_h"], "trust": self.p["theta_t"]}
        beta = {"affinity": self.p["beta_a"], "hostility": self.p["beta_h"], "trust": self.p["beta_t"]}
        true = {"affinity": self.A, "hostility": self.H, "trust": self.T}
        deltas = {ax: [[0.0] * n for _ in range(n)] for ax in AXES}

        # 预计算感知表：perceive(j, k, ax) 只依赖被感知者 j、目标 k、轴，
        # **与观察者 i 无关**，而它原本写在 `for i` 的内层 —— 每个 (j,k,ax) 被重算 n 次。
        # 提到循环外先算一次（n²·3 次，而非 n³·3 次），结果逐位不变：
        # perceive 是纯函数，其入参 A/H/T/O 在本函数内直到下方 apply 之前都不被改动。
        seen = {ax: [[self.perceive(j, k, ax) for k in range(n)] for j in range(n)]
                for ax in AXES}

        for i in range(n):
            A_i = self.A[i]
            for k in range(n):
                if i == k:
                    continue
                w_sum = 0.0
                num = {"affinity": 0.0, "hostility": 0.0, "trust": 0.0}
                for j in range(n):
                    if j == i or j == k:
                        continue
                    w = A_i[j] / 100.0  # 听从度
                    if w <= 0:
                        continue
                    w_sum += w
                    for ax in AXES:
                        # σ = max(0, 感知_X(j→k) − θ)
                        perceived = seen[ax][j][k]
                        num[ax] += w * max(0.0, perceived - th[ax])
                if w_sum <= 0:
                    continue
                denom = w_sum + self.p["epsilon"]
                net_a = (num["affinity"] - num["hostility"]) / denom
                net_h = (num["hostility"] - num["affinity"]) / denom
                # 负反馈：越接近饱和，传导增益越小（与事件侧同一口径）
                room_a = self.room_for("affinity", true["affinity"][i][k])
                deltas["affinity"][i][k] = r1(room_a * self.sat(beta["affinity"] * net_a, "affinity"))
                deltas["hostility"][i][k] = r1(self.sat(beta["hostility"] * net_h, "hostility"))
                deltas["trust"][i][k] = r1(self.sat(beta["trust"] * num["trust"] / denom, "trust"))

        for ax in AXES:
            target = true[ax]
            for i in range(n):
                for k in range(n):
                    if i != k:
                        target[i][k] = clamp100(target[i][k] + deltas[ax][i][k])
        self.stats["transmission_ticks"] += 1

    def perceive(self, j, k, axis):
        """i 感知到的 X(j→k)：经 j 的透明度档位过滤（信念矩阵 §11）+ 确定性噪声"""
        tier = self.tier(self.O[j])
        if tier == "sealed":
            return 0.0
        val = {"affinity": self.A, "hostility": self.H, "trust": self.T}[axis][j][k]
        z = self.hash01(j, k, axis) * 2 - 1
        sigma = self.sigma_max(axis) * (1 - self.O[j] / 100.0)
        if tier == "blurry":
            return clamp100(val + sigma * z * 1.5)
        return clamp100(val + sigma * z)

    @staticmethod
    def tier(opacity):
        if opacity >= 80:
            return "clear"
        if opacity >= 50:
            return "visible"
        if opacity >= 20:
            return "blurry"
        return "sealed"

    def sigma_max(self, axis):
        return {"affinity": self.bp["sigma_max_a"], "hostility": self.bp["sigma_max_h"],
                "trust": self.bp["sigma_max_t"]}[axis]

    # ------------------------------------------------ 信念更新
    def observe(self, i, j, axis, weight=1.0):
        """i 通过一次观测更新「j 对 i 的 axis」信念"""
        if i == j:
            return
        true_val = {"affinity": self.A, "hostility": self.H, "trust": self.T}[axis][j][i]
        sigma = self.sigma_max(axis) * (1 - self.O[j] / 100.0)
        z = self.hash01(i, j, axis) * 2 - 1
        bias = 0.0
        if axis == "affinity":
            bias = self.bp["w_bias"] * ((self.dims[j][0] - 50) / 50.0 * 0.5 + (self.dims[j][2] - 50) / 50.0 * 0.5)
        obs = clamp100(true_val + sigma * z + bias)
        eta_key = {"affinity": "eta0_a", "hostility": "eta0_h", "trust": "eta0_t"}[axis]
        eta = self.bp[eta_key] * (0.3 + 0.7 * self.T[i][j] / 100.0) * weight
        cur = self.B[axis][i][j]
        self.B[axis][i][j] = clamp100(cur + eta * (obs - cur))

    def hash01(self, *parts):
        """确定性伪随机（不用真随机，保证可复现）"""
        h = 2166136261
        for p in parts:
            for b in str(p).encode("utf-8"):
                h = ((h ^ b) * 16777619) & 0xFFFFFFFF
        return (h % 10000) / 10000.0

    # ------------------------------------------------ 决策
    def alpha(self, i):
        raw = {
            "affinity": self.nw["alpha_a_base"] + self.nw["alpha_a_f"] * self.dims[i][2] / 100.0
                        + self.nw["alpha_a_e"] * self.dims[i][0] / 100.0,
            # **选项 C：两行都跟 J**（判断型爱恨分明 —— 「谁值得信、谁是敌人」都是**先判断再下结论**的事）。
            #   · 接通了原本断掉的一条线：强 J 种子「举报倾向由 J 派生」，若敌对意向权重低，
            #     则**最有动机举报的人反而不记恨**，欺凌→举报链对他们不成立；
            #   · 与从众（§10.24）互补而非重叠：**J 型发起（意向层高权重）→ P 型跟从（从众通道）**，
            #     「主谋 + 被拉拢的乌合」的分层才出得来；
            #   · 对齐 §5.5「J/P 影响小团体归属倾向、被拉拢概率」——P 型被拉拢 = 低自主权重 + 高从众。
            # `(1 + arg_j)/2` 把 J 强度从 [-1,1] 映到 [0,1]，与系数原标定区间一致。
            "trust": self.nw["alpha_t_base"] + self.nw["alpha_t_j"] * (1.0 + self.arg_j(i)) / 2.0,
            "hostility": self.nw["alpha_h_base"] + self.nw["alpha_h_f"] * (1 - self.dims[i][2] / 100.0)
                         + self.nw["alpha_h_j"] * (1.0 + self.arg_j(i)) / 2.0,
            "stress": self.nw["alpha_s_base"] + self.nw["alpha_s_e"] * (1 - self.dims[i][0] / 100.0),
        }
        total = sum(raw.values())
        return {k: v / total for k, v in raw.items()}

    def tau(self, i):
        # 「高 J 温度更低」：J 强度用 arg_j
        t = self.nw["tau0"] * (1 + self.nw["tau_j"] * (0.5 - self.arg_j(i) / 2.0))
        if self.Stress[i] >= 70:
            t *= self.nw["tau_stress_mult"]
        return max(t, 0.01)

    def join_gate_utility(self, i, j):
        """决策侧软门槛：低于门槛只降低概率，不把候选排除（§6.4）。

        硬门槛曾被写成 `A[i][j] >= 30 and Stress[i] <= 80`，于是「概率低也想试一把」
        的戏剧性被消灭。改为两个 sigmoid 之和再减 1，落在 (−1, +1)：
        越过门槛给正分、低于门槛给负分，乘以 `join_chat_gate_weight` 后加进 U_b。
        """
        th = self.thresholds_lookup
        ga = th.get("join_chat_gate_affinity", 30.0)
        gs = th.get("join_chat_gate_stress", 80.0)
        scale = th.get("join_chat_gate_scale", 8.0)
        w = th.get("join_chat_gate_weight", 4.0)
        za = (self.A[i][j] - ga) / scale
        zs = (gs - self.Stress[i]) / scale
        return w * (sigmoid(za) + sigmoid(zs) - 1.0)

    def free_join(self):
        """**「别人做什么，我也跟着做什么」**（用户设计）—— `join_mode = free` 的活动可自由跟随。

        与 `join_chat`（accept 类，需对方判定）相对：学习 / 睡觉这类活动**不需要谁同意**，
        但它同样会「传染」—— 而**传染强度由 `conformity(i)` 决定**（§10.19 从众度：
        高 F 随大流、高 J·高 N 有主见）。于是「从众」第一次从**意愿层**落到**行为层**：

          · `conformity(i)` 管「我倾向做什么」（氛围影响意愿，原有）
          · `free_join` 管「我具体跟谁做」（看到别人在做，我也做，新增）

        只看**邻居**（看得见才谈得上跟随），且只跟随**当前真在做的**活动。
        """
        rates = self.probs
        # 玩家（末位）由人选择活动，不参与自动跟随。
        for i in range(self.N - 1):
            if self.sleeping[i] or self.busy_until[i] > self.global_tick:
                continue
            # ⚠️ **「学习」是个例外**：它是 `default` 状态、不占用时间槽，因此**不体现在 `current_act` 里**。
            #    但现实中它恰恰最常被跟随（"看他摊开书，我也学"）。
            #    判定：邻居此刻**既不忙、也不在做别的事** → 他在学习 → 可跟着学。
            acts = []
            for k in self.neighbor_idx[i]:
                if k == i or self.sleeping[k]:
                    continue
                a = self.current_act[k]
                if a and self.behaviors.get(a, {}).get("join_mode") == "free":
                    acts.append(a)
                elif (not a) and self.busy_until[k] <= self.global_tick:
                    acts.append("study")
            cands = acts
            if not cands:
                continue
            # 从众度高的人更容易跟着做；反从众的人（conformity≈0）基本不跟
            conf = self.conformity(i)
            if conf <= 0.05:
                continue
            if self.rng.random() < rates.get("free_join_rate", 0.0) * conf:
                a = self.rng.choice(cands)
                if a == "sleep" and self.allowed("sleep"):
                    self.sleeping[i] = True
                    self.current_act[i] = "sleep"
                    self.busy_until[i] = 10 ** 9
                elif a == "study":
                    self.current_act[i] = None    # None = 默认状态 = 在学习
                self.stats["free_joins"] = self.stats.get("free_joins", 0) + 1

    # ---------- 只读查询（供 UI 画圈 / 上绿红，零副作用）----------
    def activity_of(self, i):
        """某人此刻在做什么（UI 用）。"""
        return self.current_act[i]

    def active_circles(self):
        """**当前的「活动圈」**：按「此刻在做同一件事」分组（**只读**）。

        「圈」= 正在做同一个活动的人。与簇标签器（长期好感格局）不同，它是**实时、局部、可见**的 ——
        对应 §15.1 的「小人在教室的物理位置就是涌现的第一画面」。不同活动即不同颜色的圈。
        """
        groups = {}
        for i in range(self.N):
            a = self.current_act[i]
            if not a:
                continue
            groups.setdefault(a, []).append(i)
        return {a: sorted(v) for a, v in groups.items() if len(v) >= 2}

    def join_score(self, i, j):
        """判定侧 score：**被请求者的真值好感 `A[j][i]`** + 对方外向度 − 对方压力惩罚（§6.4）。

        判定读真值 —— 「他会不会接纳我」由**他的真实态度**决定，不由我的猜测决定；
        我的猜测只进两处：决策侧（要不要去试）与展示层（成功率）。两者之差就是误判，
        也正是本作「信息不对称」的来源（§9.4、§10.32.3）。

        ⚠️ 这里读 `A[j][i]`（别人对我的态度）**不违反** §18.7 不变式 3 ——
        该不变式禁止的是**决策路径**读它；本方法属**判定路径**，规格要求它读真值。

        压力是程度不是闸门：`hot ∈ [0,1]` 乘上 `join_chat_stress_penalty` 压低 score，
        而不是把 p 归零。
        """
        base = self.A[j][i] + (self.dims[j][0] - 50.0) * 0.3
        hot = max(0.0, self.Stress[j] - 50.0) / 50.0
        penalty = self.thresholds_lookup.get("join_chat_stress_penalty", 12.0)
        return base - penalty * hot

    def join_probability(self, i, j):
        """判定侧概率：p = σ((score − θ)/scale)，永不为 0/1（§6.4）。"""
        th = self.thresholds_lookup
        theta = th.get("join_chat_affinity", 45.0)
        scale = th.get("join_chat_scale", 10.0)
        return sigmoid((self.join_score(i, j) - theta) / scale)

    def join_feedback(self, i, j):
        """只读：返回玩家侧会看到的成功率 `p`（§10.32）。

        ⚠️ 这里**必须用信念 `B_A`**（我猜对方对我多有好感），**不得用真值** ——
        否则等于把对方心里的真实态度直接告诉玩家（§10.32.3「不泄露隐藏信息」）。

        于是**显示值与实际结算值（`join_probability`，读真值）刻意不同**：
        「我明明有 80% 把握却被拒」正是认知偏差的具象化，不是 bug（§10.32.4）。
        """
        th = self.thresholds_lookup
        hot = max(0.0, self.Stress[j] - 50.0) / 50.0
        score = (self.B["affinity"][i][j] + (self.dims[j][0] - 50.0) * 0.3
                 - th.get("join_chat_stress_penalty", 12.0) * hot)
        theta = th.get("join_chat_affinity", 45.0)
        scale = th.get("join_chat_scale", 10.0)
        return {"p": round(sigmoid((score - theta) / scale), 2)}

    # ---------- 玩家侧判定展示（NPC 静默，玩家可见过程）----------
    def verdict(self, i, j, kind="join_chat"):
        """**一次判定的展示包**（用户设计）：NPC 之间静默出结果，涉及玩家时展示三拍。

        三拍 = ① 当前成功率（由**信念**算）→ ② 掷骰 → ③ 结果。

        与判定本身**完全分离**：判定用 `do_join_chat` / `do_tease` 等照常静默执行，
        本方法只是**只读地取出「此刻玩家会看到的那个概率与结果」**，不参与结算。
        """
        if kind == "join_chat":
            fb = self.join_feedback(i, j)
            roll = self.rng.random()
            return {
                "kind": kind,
                "p": fb["p"],                    # ① 成功率（信念算得，不泄露真值）
                "roll": roll,                    # ② 掷骰
                "ok": roll < self.join_probability(i, j),   # ③ 结果（与 do_join_chat 同一 p：读真值）
                "note": "成功率来自「你以为对方怎么看你」，不是事实 —— 把握大也可能被拒。",
            }
        return None

    def roll_sleep(self):
        """每**课间段开始**掷一次睡觉（§10.8：睡 = 本段不做其他事）。

        ⚠️ 必须在**段**粒度而非 tick 粒度判定 —— 早期误写在 `decide_and_act` 里，
        结果每段掷 100 次、96% 的课间都在睡。规格的单位是"本课间"，不是"本 tick"。
        """
        if not self.allowed("sleep"):
            return
        p = self.probs.get("sleep", 0.0)
        # 随机睡觉属于 NPC 决策，不能替玩家选择。
        for i in range(self.N - 1):
            if self.sleeping[i]:
                continue
            if self.rng.random() < p * (1.0 + self.tag_bias(i, "alone_bias")):
                self.sleeping[i] = True
                self.current_act[i] = "sleep"
                self.busy_until[i] = 10 ** 9
                self.stats["sleeps"] += 1

    def phone_exposure(self):
        """举报把柄虚拟层（§10.2）：带手机者课间可能被目击「玩手机」。

        目击者 = 非睡觉的邻居（看得见才谈得上目击）。被目击一次，
        目击者获得 `report_witness_window` 天内的举报把柄。
        这是「标签 → 行为痕迹 → 目击」的链路，**不追溯流言源头**。
        """
        p = self.probs.get("phone_expose_p", 0.0)
        if p <= 0:
            return
        for j in range(self.N):
            if self.sleeping[j] or "带手机" not in self.character_tags[j]:
                continue
            if self.rng.random() >= p:
                continue
            for i in self.neighbor_idx[j]:
                if i == j or self.sleeping[i]:
                    continue
                self.witness_day[i][j] = self.day

    def roll_reports(self):
        """举报判定（§10.2）：每段课间对有把柄的候选掷一次骰，而不是每 tick。

        概率 = report_p × σ(z)，其中 z 由敌对、好感、信任共同决定——
        好友几乎不举报（A/T 高把 z 压低），但概率永不为 0。
        """
        th_rep = self.thresholds_lookup.get("report_hostility", 60.0)
        sc_rep = self.thresholds_lookup.get("report_scale", 8.0)
        win = self.thresholds_lookup.get("report_witness_window", 7.0)
        w_a = self.thresholds_lookup.get("report_affinity_penalty", 3.0)
        w_t = self.thresholds_lookup.get("report_trust_penalty", 2.0)
        p_rep = self.probs.get("report_p", 0.05)
        for i in range(self.N):
            if self.sleeping[i]:
                continue
            for j in range(self.N):
                if i == j or self.sleeping[j] or self.day - self.witness_day[i][j] > win:
                    continue
                z = (self.H[i][j] - th_rep) / sc_rep - w_a * self.A[i][j] / 100.0 - w_t * self.T[i][j] / 100.0
                if self.rng.random() < p_rep * sigmoid(z):
                    self.do_report(i, j)
                    break

    def decide_and_act(self):
        """一 tick 内的行为决策（简化：只挑一个行为执行）"""
        n = self.N
        # 玩家（末位节点，§4.1）由人的主动选择驱动，**不参与 NPC 自主决策**（§12.1）。
        # 但它仍是被交互对象：下方候选集合与 pick_target 都不排除末位。
        order = list(range(n - 1))
        self.rng.shuffle(order)
        busy = set()

        for i in order:
            if self.player_invitations.is_waiting(i):
                continue
            if self.sleeping[i] or i in busy or self.global_tick < self.busy_until[i]:
                continue
            self.in_conversation[i] = False
            # 环境类：闲聊（概率触发）—— 上课段禁用（§3.3）
            # 标签调制（§11、§18.9）：爱学习 → 更少闲聊；爱聊天 → 更多闲聊
            chat_gain = 1.0 + self.tag_bias(i, "chat_bias") - self.tag_bias(i, "study_bias")
            chat_gain = max(0.1, chat_gain)
            if self.allowed("chat") and self.rng.random() < self.probs["chat"] * chat_gain:
                j = self.pick_target(i)
                if j is not None:
                    self.do_chat(i, j)
                    busy.add(i)
                    busy.add(j)
                    continue
            # 意向类：当众调侃（需 ≥3 人围观；失败则目标受辱）
            # 目标选择**带偏好**：敌对越高 / 好感越低越容易被针对 —— 被讨厌的人会被反复打击，
            # 这正是"压力分化 → 个别爆发"的机制来源（不允许随机摊平）
            # 调侃候选：**好意 / 挑衅双轨**（§10.12 修订）——
            #   好意 A ≥ 40；或挑衅式（**i 猜测 j 对自己敌对** B_H ≥ 25，或发起者对目标 A < 25）。
#   ⚠️ 挑衅式读的是**信念** B_H[i][j] 而非真值 H[j][i] —— 决策只读信念（§18.7 不变式 3）。
            #   修复前只有「A ≥ 20」这一条，与 §10.16 的嘲讽档判据互斥，使嘲讽档永远发不出来。
            cands_t = [j for j in range(n)
                       if j != i and j not in busy and self.can_interact_with(j)
                       and self.are_neighbors(i, j)      # 调侃需物理接近（§10.12 围观前提）
                       and (self.A[i][j] >= 40.0 or self.B["hostility"][i][j] >= 25.0 or self.A[i][j] < 25.0)]
            if self.allowed("tease") and len(cands_t) >= 3 and self.rng.random() < self.probs.get("tease_p", 0.18) * (1.0 + self.tag_bias(i, "tease_bias")):
                wts = [max(1.0, ((100.0 - self.A[i][j]) + self.H[i][j]) ** 2) for j in cands_t]
                j = self.rng.choices(cands_t, weights=wts, k=1)[0]
                # **围观者 = 物理上在场的人（邻居）**，而不是「全班减去两个忙人」。
                #    后者让 audience 恒有 13~15 人，任何「被围着」的门槛都会恒真。
                #    §10.12 说的「周围 ≥3 人围观」，'周围'本就是空间概念（§10.20 座位表）。
                # 围观者 = **i 与 j 的共同邻居**（调侃发生在两人之间，看热闹的是两人旁边的人）。
                #    用「并集」会得到约 10 人（5+5），任何门槛都会恒真；
                #    用「交集」才是真正的「围在他俩周围」—— 数量少、有筛选力。
                audience = [k for k in self.neighbor_idx[i]
                            if k in self.neighbor_idx[j]
                            and k not in (i, j) and k not in busy and not self.sleeping[k]]
                if len(audience) >= 3:
                    # ⚠️ **不截断** audience：`audience[:3]` 曾把围观者固定为恰好 3 人，
                    #    而羞辱门槛也是 3 → `len(audience) >= 3` **恒真**，
                    #    §10.23 所说「私下嘲讽只是摩擦、被围着才写深层」的区分**从未生效**。
                    #    而且 [:3] 取的是 range(n) 前 3 个 → 围观者系统性偏向低索引角色。
                    self.do_tease(i, j, audience)
                    busy.add(i)
                    busy.add(j)
                    continue
            # 意向类：追逐打闹 —— 敌对种子（参与者好感↑ / 旁观者敌对↑）
            th_rh = self.thresholds_lookup.get("roughhouse_affinity", 45.0)
            th_rc = int(self.thresholds_lookup.get("roughhouse_count", 2))
            if self.allowed("roughhouse") and self.dims[i][0] >= th_rh and self.rng.random() < self.probs.get("roughhouse_p", 0.05):
                others = [j for j in range(n) if j != i and j not in busy and self.can_interact_with(j)]
                if others:
                    # 追跑对象按外向度加权：越外向越可能一起闹（→ 同样的少数人反复搭配）
                    w_rh = [max(1.0, self.dims[j][0] - 30.0) for j in others]
                    j = self.rng.choices(others, weights=w_rh, k=1)[0]
                    bys = [k for k in range(n) if k not in (i, j) and k not in busy]
                    if len(bys) >= th_rc:
                        # 旁观者聚焦「安静专注型」（高 J + 内向）—— 他们最容易被吵到，
                        # 于是「活跃分子 × 严肃分子」这一批边会被反复击中而累积，而不是被摊平
                        # 随机采样，而非取 range(n) 前 N 个 —— 否则围观者永远是低索引角色
                        bys = self.rng.sample(bys, min(len(bys), 4))
                        # 打闹**只吵到邻座**（§10.18 + 空间层）——
                        # 修复前用的是「全班路过的」，一次打闹就摊到全班的边上，这正是边数摊薄的主因。
                        nb = [k for k in (self.neighbor_idx[i] + self.neighbor_idx[j])
                              if k != i and k != j and not self.sleeping[k]]
                        self.do_roughhouse(i, j, sorted(set(nb))[:3])
                        busy.add(i)
                        busy.add(j)
                        continue
            # 阈值类：排挤（"大家都讨厌他" → 集体驱逐）—— B 类，让关系能无条件变差
            # 阈值类：排挤（§8.4 **修订**：「有多少人**近期损害过他**」→ 集体驱逐）。
            # ⚠️ 原判据是「≥3 人**恨**他 ≥40」，方向反了 —— 欺凌是**多对一**：
            #    施害者多人、受害者一人，**受害者只能单向记恨**，永远凑不出「3 人恨他」。
            #    集体排斥的证据在**施害者一侧**：有多少人**对他做过敌对行为**。
            if self.allowed("exclude") and self.rng.random() < self.probs.get("exclude_p", 0.04):
                th_n = int(self.thresholds_lookup.get("exclude_count", 3))
                cd_days = self.thresholds_lookup.get("exclude_cooldown", 7.0)
                window = self.thresholds_lookup.get("exclude_window", 7.0)
                done = False
                for j in range(n):
                    if j == i or j in busy:
                        continue
                    if self.day - self.exclude_last_day[j] < cd_days:
                        continue                      # 冷却中：已经被驱逐过，不再重复
                    hurters = [k for k in range(n)
                               if k != j and self.day - self.hurt_day[k][j] <= window]
                    if len(hurters) >= th_n:
                        self.do_exclude(i, j, hurters[:4])
                        self.exclude_last_day[j] = self.day
                        busy.add(i)
                        done = True
                        break
                if done:
                    continue
            # 附加行为：流言（负面染色，压力来源）；目标同样偏好敌对高者
            if self.allowed("rumor") and self.rng.random() < self.probs.get("rumor_p", 0.03):
                c2 = [j for j in range(n) if j != i and j not in busy and self.can_interact_with(j)]
                if c2:
                    w2 = [max(1.0, 20.0 + self.H[i][j] - self.A[i][j] * 0.5) for j in c2]
                    j = self.rng.choices(c2, weights=w2, k=1)[0]
                    self.do_rumor(i, j)
                    busy.add(i)
                    busy.add(j)
                    continue
            # ---------- 意向类：三条「主动接近他人」的行为（§10.10 / §10.11 / §10.13）----------
            # 三者都必须排在下面**无门槛的搭话回退块之前**，否则会被它永远抢先。
            # 门槛一律读「我自己的立场」（A[i][j] / H[i][j] / Stress[j]）与信念 B，
            # **不读 A[j][i] / H[j][i]**（§18.7 不变式 3：决策路径不得读「别人对我的态度」）。
            thk = self.thresholds_lookup
            e_i = self.dims[i][0]
            # 意向类：安慰（§10.13，A 类）—— 有人正处在高压区，而我和他关系够近
            if self.allowed("comfort") and self.rng.random() < self.probs.get("comfort_p", 0.0):
                # 好感门槛：E ≥ 50 用默认值，E < 50 向内向端线性抬高
                # （§10.13「一般 50 / 内向 70」→ E=50 恰为 50、E=0 恰为 70；连续、不跳变）
                base_cf = thk.get("comfort_trigger_affinity", 50.0)
                intro_cf = thk.get("comfort_trigger_introvert_affinity", 70.0)
                need_cf = base_cf + (intro_cf - base_cf) * max(0.0, (50.0 - e_i) / 50.0)
                cands_cf = [j for j in range(n) if j != i and j not in busy and self.can_interact_with(j)
                            and self.Stress[j] >= thk.get("comfort_trigger_target_stress", 70.0)
                            and self.A[i][j] >= need_cf]
                if cands_cf:
                    # 谁越崩溃越该被关心（目标是**可见的**情绪状态，不是「他对我的态度」）
                    w_cf = [max(1.0, self.Stress[j]) for j in cands_cf]
                    j = self.rng.choices(cands_cf, weights=w_cf, k=1)[0]
                    self.do_comfort(i, j)
                    busy.add(i)
                    busy.add(j)
                    continue
            # 意向类：求助（§10.10，C 类）—— 我对目标好感够高才敢开口（内向更高、外向更低）
            if self.allowed("ask_help") and self.rng.random() < self.probs.get("ask_help_p", 0.0):
                # 三段锚点：E=50 → 30、E=0 → 50、E=100 → 20（§10.10「≥30；内向 ≥50；外向 ≥20」）
                base_h = thk.get("ask_help_affinity", 30.0)
                intro_h = thk.get("ask_help_introvert_affinity", 50.0)
                extro_h = thk.get("ask_help_extrovert_affinity", 20.0)
                need_h = (base_h + (intro_h - base_h) * (50.0 - e_i) / 50.0 if e_i < 50.0
                          else base_h + (extro_h - base_h) * (e_i - 50.0) / 50.0)
                cands_h = [j for j in range(n) if j != i and j not in busy and self.can_interact_with(j)
                           and self.A[i][j] >= need_h]
                if cands_h:
                    # 目标选择读**信念**：我以为他越可能帮我，越先去求他（§18.6 意向评分「对方的反应预期」）
                    w_h = [max(1.0, self.B["affinity"][i][j] - self.B["hostility"][i][j]) for j in cands_h]
                    j = self.rng.choices(cands_h, weights=w_h, k=1)[0]
                    self.do_ask_help(i, j)
                    busy.add(i)
                    busy.add(j)
                    continue
            # 意向类：道歉 / 和解（§10.11，E 类）—— 僵局够深才有「和解」这件事
            if self.allowed("apologize") and self.rng.random() < self.probs.get("apologize_p", 0.0):
                th_ap = thk.get("apologize_trigger_hostility", 30.0)
                # 决策侧只看**我自己的立场**（我对他敌对到什么程度才谈得上「和解」）——
                # §10.11 的「双方」由**判定侧**承接：接受概率里含 `H[j][i]`（他的气有多大）。
                # ⚠️ 不在这里读 `H[j][i]`：决策路径禁读「别人对我的态度」（§18.7 不变式 3）。
                cands_ap = [j for j in range(n) if j != i and j not in busy and self.can_interact_with(j)
                            and self.H[i][j] >= th_ap]
                if cands_ap:
                    # 我越恨、也越以为他恨我 → 越有动力去破这个僵局
                    w_ap = [max(1.0, self.H[i][j] + self.B["hostility"][i][j]) for j in cands_ap]
                    j = self.rng.choices(cands_ap, weights=w_ap, k=1)[0]
                    self.do_apologize(i, j)
                    busy.add(i)
                    busy.add(j)
                    continue
            # 意向类：搭话
            cands = [j for j in range(n) if j != i and j not in busy and self.can_interact_with(j)]
            if cands:
                alpha = self.alpha(i)
                scores = []
                for j in cands:
                    gain_a = self.B["affinity"][i][j] / 100.0 * 3.0  # 预期收益（读信念）
                    gain_t = self.B["trust"][i][j] / 100.0 * 2.0
                    risk_h = self.B["hostility"][i][j] / 100.0 * 2.0
                    u = alpha["affinity"] * gain_a + alpha["trust"] * gain_t - alpha["hostility"] * risk_h
                    u += self.crowd_bias(i, "loud")   # 氛围项：吵则更想搭话（从众者）
                    u += self.tag_bias(i, "chat_bias") - self.tag_bias(i, "alone_bias")  # 标签项
                    u += self.join_gate_utility(i, j)   # 软门槛：低门槛仍可有小概率发起（§6.4）
                    scores.append(u)
                if scores:
                    k = softmax(scores, self.tau(i), self.rng)
                    j = cands[k]
                    self.do_join_chat(i, j)
                    busy.add(i)
                    busy.add(j)

    def is_busy(self, i):
        """节点此刻是否正处在占用型行为中（§10.4 行为耗时）—— 表现层权限判定用（如玩家操控）。"""
        if i < 0 or i >= self.N:
            return False
        return self.global_tick < self.busy_until[i]

    def set_position(self, i, x, z):
        """写入节点在教室里的真实平面位置（米）。越界静默忽略（表现层防御性调用）。"""
        if 0 <= i < self.N:
            self.pos_x[i] = float(x)
            self.pos_z[i] = float(z)

    def position_of(self, i):
        """节点当前位置 (x, z)，单位米。"""
        return (self.pos_x[i], self.pos_z[i])

    def distance_between(self, i, j):
        """两点的平面距离（米）—— 空间层判定（交互范围 / 活动圈）的统一口径。"""
        return math.hypot(self.pos_x[i] - self.pos_x[j], self.pos_z[i] - self.pos_z[j])

    def can_interact_with(self, j):
        """目标此刻能否接受一次新交互（只读判定）：
        未睡觉（§10.8）且**没有尚未结束**的占用（行为耗时契约）。

        跨 tick 的占用看 `busy_until` —— 只看本 tick 的局部 `busy` 集合，
        会让「还在做上一个行为」的人被反复拉进新交互（内核策划符合性审查 P1-03）。
        """
        return (not self.sleeping[j]) and self.global_tick >= self.busy_until[j]

    def pick_target(self, i, neighbors_only=False):
        """选交互目标。**邻居优先**（§10.15 相邻修正）——

        这是「边数摊薄」的解药：交互集中在固定邻居之间，同一对子会反复相遇。
        `neighbors_only=True` 时只在邻居里选（打闹/调侃这类**需要物理接近**的行为）。
        """
        n = self.N
        if neighbors_only:
            others = [j for j in self.neighbor_idx[i] if self.can_interact_with(j)]
            return self.rng.choice(others) if others else None
        # **邻居优先**：邻居被选中的权重更高（§10.15 相邻修正）。
        # 非邻居仍可能（课间有人走动），但概率显著低 —— 这就是「边数摊薄」的解药。
        w_nb = self.probs.get("neighbor_pick_mult", 3.0)
        pool = []
        for j in range(n):
            if j == i or not self.can_interact_with(j):
                continue
            pool.append((j, w_nb if j in self.neighbor_idx[i] else 1.0))
        if not pool:
            return None
        tot = sum(w for _, w in pool)
        r = self.rng.random() * tot
        acc = 0.0
        for j, w in pool:
            acc += w
            if r <= acc:
                return j
        return pool[-1][0]

    def occupy(self, i, j, behavior, quiet=False):
        """按行为耗时把双方置为忙碌（“收益越大耗时越长”，不再一律 20 tick）"""
        self.current_act[i] = behavior
        # quiet=True：加入 / 被搭话的一方 —— 同一场对话只算**一个声源**
        # （现实里多一个人加入同一场聊天，音量几乎不变；让教室变吵的是「多摊人各自在聊」）
        occupy_target = j != self.N - 1 or i == self.N - 1 or self.player_invitations.authorizes(i)
        if occupy_target:
            self.current_act[j] = None if quiet else behavior
        dur = self.behaviors.get(behavior, {}).get("duration", 0)
        if dur > 0:
            # 时长**累积**而不是覆盖（策划 2026-10-07：「群聊作为同一个交互管理，
            # 不能靠覆盖占用实现」）—— 否则加入一场进行中的活动会把已占用的时长改短。
            until = self.global_tick + dur
            self.busy_until[i] = max(self.busy_until[i], until)
            self.busy_phase[i] = self.phase_index
            self.busy_act[i] = behavior
            if occupy_target:
                self.busy_until[j] = max(self.busy_until[j], until)
                self.busy_phase[j] = self.phase_index
                self.busy_act[j] = behavior

    @invitation_behavior("chat")
    def do_chat(self, i, j):
        """闲聊：话题共鸣事件 + 双方观测"""
        self.in_conversation[i] = True
        self.in_conversation[j] = True
        self.occupy(i, j, "chat", quiet=True)   # 同一场对话：只计一个声源
        self.apply_event(i, j, "topic_affinity")
        self.apply_event(i, j, "topic_trust")
        self.apply_event(i, j, "topic_stress")
        self.apply_event(j, i, "topic_affinity")
        self.apply_event(j, i, "topic_trust")
        self.observe(i, j, "affinity")
        self.observe(j, i, "affinity")
        self.stats["chats"] += 1

    @invitation_behavior("join_chat")
    def do_join_chat(self, i, j, roll=None):
        """搭话判定侧：**p = σ((score − θ)/scale) 掷骰**（§6.4）。

        没有硬闸门：概率低也可能被接纳、概率高也可能被拒。
        `roll` 可由调用方（玩家 UI）预先掷好，保证「三拍展示」与实际结算一致。
        """
        self.in_conversation[i] = True
        self.in_conversation[j] = True
        self.occupy(i, j, "join_chat", quiet=True)   # 同一场对话：只计一个声源
        p = self.join_probability(i, j)
        choice = self.player_invitations.choice_for(i)
        if choice is not None:
            p, roll = (1.0 if choice else 0.0), 0.0
        elif roll is None:
            roll = self.rng.random()
        if roll < p:
            self.do_chat(i, j)
            self.stats["joins"] += 1
            self.stats["join_accepts"] = self.stats.get("join_accepts", 0) + 1
        else:
            self.apply_event(i, j, "reject_affinity")
            self.apply_event(i, j, "reject_hostility")
            self.apply_event(i, j, "reject_stress")
            self.observe(i, j, "affinity")
            self.stats["joins"] += 1
            self.stats["join_rejects"] = self.stats.get("join_rejects", 0) + 1
            self.stats["skipped_events"] += 1

    def do_report(self, i, j):
        """举报（§10.2）：**i = 举报者，j = 被举报者**。

        ⚠️ **效果落在被举报者身上**（2026-10-07 修）：两处 `apply_event` 曾写作 `(i, j)`，
        于是被举报者压力恒为 0、深层敌对记到了举报者一侧 —— 与 §10.2「举报会大幅提升
        **被举报者**的压力值」、§6.3 major 档（压力 +5 / 敌对 +5）相反。
        方向与 `do_tease` 的羞辱链路同构（受害者 → 施害者）。
        """
        self.apply_event(j, i, "report_stress")       # 被举报者压力↑（§6.3 major）
        self.apply_event(j, i, "report_hostility")    # 被举报者 → 举报者 敌对↑（major → 深层，§10.22）
        self.mark_hurt(i, j)                          # 施害者视角：i 举报了 j（§10.25）
        self.H[i][j] = clamp100(self.H[i][j] - 5.0)   # 举报后 A 对 B 的敌对回落（§10.2）
        self.stats["reports"] += 1

    def do_tease(self, i, j, audience):
        """当众调侃（§10.12）：**结果方向由净态度 M 决定**，而不是二分的「成功 / 过火」。

        同一个行为覆盖三种社会含义：
          · **玩笑档**（A ≥ 55 且 H < 25）→ 双方好感↑、被逗笑减压
          · **嘲讽档**（H ≥ 40 或 A < 25）→ 目标压力↑、对发起者敌对↑、围观者按性格分裂
          · **尴尬档**（其余）             → 不结算（效果自然为 0）
        方向由 `behavior_thresholds.csv` 的**绝对阈值**判定；强度仍由 |M| 调制。
        ⚠️ 不用 M 的符号判方向：M 的零点在 A=H，而 A 的基线(25~40)远高于 H 的基线(0~15)，
        M 恒偏正 → 会退化成「永远玩笑」，实测全班冲到 89.4 / SD 1.5 / 爆发 0。
        """
        th = self.thresholds_lookup
        self.occupy(i, j, "tease")
        if self.A[i][j] >= th["tease_laugh_affinity"] and self.H[i][j] < th["tease_laugh_hostility"]:
            self.apply_event(i, j, "tease_success_affinity")
            self.apply_event(j, i, "tease_success_affinity")
            for k in audience:
                self.apply_event(k, j, "tease_success_affinity")
            self.apply_event(j, i, "tease_laugh_stress")
        elif self.H[i][j] >= th["tease_taunt_hostility"] or self.A[i][j] < th["tease_taunt_affinity"]:
            self.apply_event(j, i, "tease_hostility")
            self.apply_event(j, i, "tease_stress")
            # 围观者站哪边：由**他对被调侃者的态度**决定（与主行为同一套轴与阈值，表驱动）
            for k in audience:
                if self.A[k][j] >= th["tease_stand_affinity"]:
                    self.apply_event(k, i, "tease_hostility")     # 站被调侃者 → 不满发起者
                elif self.H[k][j] >= th["tease_sneer_hostility"]:
                    self.apply_event(k, j, "tease_affinity")      # 讨厌被调侃者 → 附和发起者
                # 其余：中立，不表态
            # **当众羞辱**（§10.23）：被一群人看着嘲笑，就不是"过火"而是**羞辱**了。
            # 私下的嘲讽只是表层摩擦（会淡忘）；**当众**才写进永不衰减的深层。
            # 判定只看「有多少人在看」—— 这是纯粹的处境条件，与是谁无关（无特例）。
            if len(audience) >= th.get("humiliate_bystanders", 3.0):
                self.apply_event(j, i, "humiliate_hostility")
                self.mark_hurt(i, j)             # 施害者视角：i 当众羞辱了 j（§10.25）
                self.stats["humiliations"] = self.stats.get("humiliations", 0) + 1
            self.stats["tease_fail"] += 1
        self.stats["teases"] += 1

    def do_exclude(self, i, j, crowd):
        """【排挤】（B 类：纯损害，判定来源＝**群体状态**）。

        触发条件是「**大家都讨厌他**」——需要多个人同时对 j 敌对过阈，才构成集体驱逐。
        因此它与任何一对个人关系无关：**不是「我讨厌你所以排挤你」，而是「大家都讨厌你」**。
        这正是 §10.16 所说的 B 类（判定来源为「无」的纯损害行为），也是本作此前缺失的
        「让关系无条件变差」的通道。

        效果：被排挤者压力↑（§8.4）且**对参与者好感↓** —— 关系真的变差。
        """
        self.occupy(i, j, "exclude")
        self.apply_event(j, i, "exclude_stress")
        # 双向：**「他恨上了排斥他的人」**
        self.apply_event(j, i, "exclude_affinity")
        for k in crowd:
            if k != i:
                self.apply_event(j, k, "exclude_affinity")
        # 双向：**「大家不跟他玩了」**（§10.24.4 补齐）
        # ⚠️ 反向效果此前缺失，导致「被孤立」只表现为「受害者单向记恨」，
        #    而**观察不到全班对他的疏远** —— 孤立因此不是一个可观测的**状态**。
        self.apply_event(i, j, "exclude_affinity")
        for k in crowd:
            if k != i:
                self.apply_event(k, j, "exclude_affinity")
        self.stats["excludes"] += 1

    def do_rumor(self, i, j):
        """流言（§10.1）：i 传关于 j 的话 → j 压力变化；旁观者"二手观测"。

        倾向由 i 对 j 的净态度决定：敌对压过好感则传负面（被传者压力↑）。
        """
        # 流言的**本性就是负面**：无条件让「被传谣者恨传播者」——不要求"当前已敌对"。
        # （早期实现用 `H > A` 作前置 → 死循环：H 起不来 → 永不判为负面 → 永不加敌对 → H 更起不来。）
        # `negative` 只用于调节**强度**（倾向），不决定**有无**。
        negative = self.H[i][j] > self.A[i][j]
        self.apply_event(j, i, "rumor_hostility")
        if negative:
            self.apply_event(i, j, "rumor_stress")
            self.apply_event(i, j, "tease_hostility")
        for k in range(self.N):
            if k not in (i, j):
                self.observe(k, j, "hostility")     # 二手观测（会带噪声）
        self.stats["rumors"] += 1

    @invitation_behavior("roughhouse")
    def do_roughhouse(self, i, j, bystanders):
        """【追逐打闹】（§10.18）—— 全系统唯一不依赖既有敌对的「敌对种子」。

        · 参与者互相**好感↑**（A 类效果）；
        · **路过的旁观者对参与者敌对↑**（B 类效果）—— 只需「有人在打闹」+「有人在场」，
          不引用任何已有敌对值，因此 **t = 0 即可触发**，解开了「要产生敌对需先有敌对」的死锁。

        社会含义自带讽刺：打闹的两人越来越亲近，被吵到的人越来越讨厌他们两个 ——
        「聚集」与「排斥」在同一个动作里同时发生，这正是 §16「小团体自发抱团」的机理。

        聚焦而非纯随机：发起者须外向（热闹型才追跑）、旁观者的敌对受 `w_j` 调制（高 J 的专注型
        最容易被吵到），于是「活跃分子 × 严肃分子」这一批边会持续累积，而不是被摊平。
        """
        self.occupy(i, j, "roughhouse")
        self.apply_event(i, j, "roughhouse_affinity")
        self.apply_event(j, i, "roughhouse_affinity")
        for k in bystanders:
            self.apply_event(k, i, "roughhouse_hostility")
            self.apply_event(k, j, "roughhouse_hostility")
        self.stats["roughhouse"] += 1

    # ---------- 意向类：三条「主动接近他人」的行为（§10.10 / §10.11 / §10.13）----------
    # 三者同守 §6.4 两段式：**决策侧读信念、判定侧读真值**。
    # 它们的共同点：**发起者要付出压力成本**（主动接近别人是有代价的）——
    # 于是「谁被照顾、谁被求、谁被原谅」都不白给，代价由发起者承担。

    @invitation_behavior("comfort")
    def do_comfort(self, i, j):
        """安慰（§10.13，A 类）：**i 主动去关心正处在高压区的 j**。

        触发（决策侧）：目标 `Stress[j] ≥ 70` 且我对他的好感跨过门槛（内向门槛更高）。
        效果（major 档，效果行见 `w_events.csv` 的 `comfort_target_*`）：

        · 目标压力 ↓、**对安慰者**好感 ↑ / 信任 ↑（`apply_event(j, i, ...)` 的方向语义：
          被安慰者才是数值变化的一方）
        · 发起者付出 `comfort_cost_stress`（+2 压力，不论结果）

        它是**深度关系的主要建立方式**：门槛苛刻（须已有好感 + 对方正崩溃），但回报是全表
        最重的正向档 —— 关系的跃升发生在「救援时刻」，而不是日常寒暄里。

        ⚠️ 本轮未实现：目标 `Stress ≥ 90` 时的共情判定与效果 ×1.5（§10.13 第 4 条）。
        """
        self.occupy(i, j, "comfort")
        self.apply_event(i, j, "comfort_cost_stress")      # 发起者成本（不论结果）
        self.apply_event(j, i, "comfort_target_stress")    # 目标：压力 ↓
        self.apply_event(j, i, "comfort_target_affinity")  # 目标 → 安慰者：好感 ↑
        self.apply_event(j, i, "comfort_target_trust")     # 目标 → 安慰者：信任 ↑
        self.stats["comforts"] += 1

    @invitation_behavior("ask_help")
    def do_ask_help(self, i, j):
        """求助（§10.10，C 类）：**i 开口求 j 帮忙**。

        判定读**真值**：`p = σ((A[j][i] + 对方外向度加成 − θ) / scale)` ——
        「他会不会帮我」由**他的真实态度**决定，不由我的猜测决定（§6.4）；
        我的猜测只进决策侧的目标选择（我以为他越可能帮，越先去求他）。

        效果（§10.10）：
        · 成功 → 求助者 好感↑ / 压力↓；帮忙者 对求助者 好感↑ / 信任↑
        · 被拒 → 求助者 压力↑ / 敌对↑ / 信任↓
        发起成本（+2 压力）**不论成败都付** —— 「开口求人」本身就有代价。

        ⚠️ 本轮未实现：「被亏欠」状态（3 天内成功率 +25%）与「被拒压力 ×1.5 / 好斗敌对 ×2」
        —— 前者需要 `status_tags` 支持「条件修正」语义（现表是「每天施加固定效果」），
        后者超出 `M_personality` 的 `[0.1,1.2]` 钳位，需另开通道。
        """
        thk = self.thresholds_lookup
        self.occupy(i, j, "ask_help")
        self.apply_event(i, j, "ask_help_cost_stress")
        score = self.A[j][i] + self.dims[j][0] / 100.0 * thk.get("ask_help_extrovert_bonus", 10.0)
        p = sigmoid((score - thk.get("ask_help_accept_theta", 40.0))
                    / thk.get("ask_help_accept_scale", 12.0))
        if (self.player_invitations.choice_for(i) if self.player_invitations.choice_for(i) is not None
                else self.rng.random() < p):
            self.apply_event(i, j, "ask_help_ok_asker_affinity")
            self.apply_event(i, j, "ask_help_ok_asker_stress")
            self.apply_event(j, i, "ask_help_ok_helper_affinity")
            self.apply_event(j, i, "ask_help_ok_helper_trust")
            self.stats["helps"] += 1
        else:
            self.apply_event(i, j, "ask_help_no_stress")
            self.apply_event(i, j, "ask_help_no_hostility")
            self.apply_event(i, j, "ask_help_no_trust")
            self.stats["help_rejects"] += 1

    @invitation_behavior("apologize")
    def do_apologize(self, i, j):
        """道歉 / 和解（§10.11，E 类）：**i 主动向 j 低头**。双方敌对 ≥30 才谈得上和解。

        判定读**真值**：`p = σ((A[j][i] + 对方随和系数(F_j) − H[j][i]×惩罚) / scale)` ——
        三个输入**全部是「j 对 i 的立场」**：他对我好感越高、性格越随和、对我的气越少，
        越可能接受。发起方的态度不参与判定（低头的人没资格决定对方原不原谅）。

        效果（§10.11）：

        · 接受 → **表层**敌对回落、双向好感/信任回升、双方减压
        · 被拒 → 敌对继续累积、发起者压力↑（major）、信任↓
        发起成本（+3 压力）不论结果都付。

        ⚠️ **只消表层敌对**：`H_deep`（心结）不因道歉而消 —— 与 §10.22「心结永不衰减」自洽
        （「道歉能消当下的气，但忘不掉的还是忘不掉」）。同一行为的敌对变化也不写 `hurt_day`
        （那是**施害者**视角的重伤记录，道歉是和解不是伤害）。

        ⚠️ 效果行一律 `no_modulation=True`：见 `apply_event` 的说明 —— 和解与关系调制
        `M` 的冲突是结构性的（门槛 H ≥ 30 保证 M 常为负，否则会「越道歉越糟」）。

        ⚠️ 本轮未实现：发起时的「透明度临时 +10」（现有实现没有临时透明度机制）。
        """
        thk = self.thresholds_lookup
        self.occupy(i, j, "apologize")
        self.apply_event(i, j, "apologize_cost_stress")
        score = (self.A[j][i]
                 + self.dims[j][2] / 100.0 * thk.get("apologize_calm_bonus", 20.0)
                 - self.H[j][i] * thk.get("apologize_hostility_penalty", 0.5))
        p = sigmoid((score - thk.get("apologize_accept_theta", 40.0))
                    / thk.get("apologize_accept_scale", 12.0))
        if (self.player_invitations.choice_for(i) if self.player_invitations.choice_for(i) is not None
                else self.rng.random() < p):
            for a, b in ((i, j), (j, i)):          # 双向：和解是双方的事
                self.apply_event(a, b, "apologize_ok_hostility", no_modulation=True)
                self.apply_event(a, b, "apologize_ok_affinity", no_modulation=True)
                self.apply_event(a, b, "apologize_ok_trust", no_modulation=True)
                self.apply_event(a, b, "apologize_ok_stress", no_modulation=True)
            self.stats["apologizes"] += 1
        else:
            self.apply_event(i, j, "apologize_no_hostility", no_modulation=True)
            self.apply_event(i, j, "apologize_no_stress", no_modulation=True)
            self.apply_event(i, j, "apologize_no_trust", no_modulation=True)
            self.stats["apologize_rejects"] += 1

    def update_environment(self):
        """环境层：由「当前大家在做什么」推出目标音量，再平滑趋近。

        `target = clamp(Σ noise(各人当前行为), 0, max)` —— **量的累积产生质变**：
        2 人聊天 noise=12×2=24（正常）；8 人聊天 96（**吵到别人**）。
        超阈部分才转化为压力，且**怕吵程度取决于性格**（高 J 的专注型、内向者更受不了）。
        """
        e = self.env
        target = 0.0
        for i in range(self.N):
            # 行为结束后回到"默认（学习，不发声）"——否则 current_act 会永久残留，
            # 全员被当成"一直在聊天"，音量恒满。
            if self.global_tick >= self.busy_until[i]:
                self.current_act[i] = None
            # None = 既没在做事、也没在发声（静默参与者或空闲）→ 不贡献音量
            act = self.current_act[i]
            if act is None:
                continue
            target += self.behaviors.get(act, {}).get("noise", 0.0)
        target = clamp(target, 0.0, e.get("volume_max", 100.0))
        rate = e.get("adapt_rate", 0.02)
        self.volume = clamp(self.volume + rate * (target - self.volume), 0.0, e.get("volume_max", 100.0))

    def tag_bias(self, i, effect_key):
        """标签对行为倾向的加成（`data/rules/tags.csv`，按作用轴分类、分 weak/strong 两级）。

        **标签是"对底层轴的调制"，不是身份** —— 所以「学霸」不是规则，
        而是「高 J × 低从众度 × 爱学习」这组条件涌现出来的称呼（§10.19 结尾）。
        这里只做**倾向加成**：weak ≈ +0.10、strong ≈ +0.50（对应表里的 `effect` 列）。
        """
        if not self.character_tags:
            return 0.0
        total = 0.0
        for tid in self.character_tags[i]:
            row = self.tag_rows.get(tid)
            if not row or row.get("effect") != effect_key:
                continue
            total += 0.10 if row.get("strength") == "weak" else 0.50
        return total

    def allowed(self, behavior):
        """当前相位是否允许该行为（§3.3：上课段只跑规则子集）。

        `phases.csv` 用 `study_together|rumor|stress_drip|transmission` 描述上课段允许的规则；
        这里把它翻译成"行为白名单"——**上课时禁用的行为** = 一切主动社交。
        """
        if not hasattr(self, "phase_rules"):
            return True
        pid = self.phase_order[self.phase_index] if 0 <= self.phase_index < len(self.phase_order) else None
        rules = self.phase_rules.get(pid, ["all"])
        if "all" in rules:
            return True
        banned = {"chat", "join_chat", "pass_note", "tease", "ask_help", "inform",
                  "comfort", "apologize", "share_secret", "roughhouse", "exclude",
                  "report", "move"}
        return behavior not in banned

    def arg_j(self, i):
        """J（判断型）强度 ∈ [-1,1]：**`dims[3]` 直读，它就是 J 强度**（50 = 中性）。

        ⚠️ **重要更正（2026-10-05）**：文档 §5.5 曾把第 4 维描述为「感知度 P（0 端=判断 J）」，
        但**种子数据 `seeds.csv` 的第 4 列实际存的是 J 强度** —— 证据：
          · 李峥 **ESTJ** 班长 = 95，其注释原文「举报倾向由 **J=95** 派生」；
          · 王磊 **ESFP** / 郑浩 **ENTP**（两个强 P 型）= 25；
          · 陈阳 ESFJ = 65、张渊 INTJ = 85 —— **全部与 MBTI 字符串一致**。
        且主文档自己的引言写的就是 `α_T ∝ 0.5 + 0.5·J/100`（直用 J）。
        **∴ 文档的文字定义与数据矛盾，以数据为准**（数据才是设计者真实意图）。

        曾有一版按文档文字把它写成 `(50 − dims[3])/50` —— 那会把**全班人格镜像**：
        最强的 J（班长）被当成最随性的人（从众最高、最不怕吵、τ 最随机、意向权重最低）。
        """
        return (self.dims[i][3] - 50.0) / 50.0

    def arg_i(self, i):
        """内向强度 ∈ [-1,1]：`dims[0]` 是外向 E，故内向 = (50 − E)/50。"""
        return (50.0 - self.dims[i][0]) / 50.0

    def conformity(self, i):
        """从众度 ∈ [0,1]：**大部分人从众，少数人有主见**。

        · 高 F（情感型、在意氛围）→ 从众；
        · 高 J（判断型，有自己的计划）+ 高 N（直觉型，脑内自成一套）→ 反从众。
        从众者跟着环境走（吵就更想聊、静就更想学），反从众者不受环境影响 ——
        所以「安静也要聊天」「吵闹也会学习」这两种人天然存在，**不需要特例**。
        """
        # 高 F（情感型、在意氛围）→ 从众；高 J（判断型）+ 高 N（直觉型）→ 反从众。
        # ⚠️ 原式误把 dims[3] 当 J 用，实际让 **J 型更从众**（与文档相反）；
        #    现改用 arg_j（J 强度）与 arg_n（N 强度），方向与文档一致。
        f = (self.dims[i][2] - 50.0) / 100.0
        j = self.arg_j(i) / 2.0
        n = (self.dims[i][1] - 50.0) / 100.0
        return clamp(0.5 + f - j * 0.5 - n * 0.5, 0.0, 1.0)

    def crowd_bias(self, i, kind):
        """环境氛围对行为意愿的加成（kind ∈ {"loud","quiet"}）：从众者受影响，反从众者不受。"""
        conf = self.conformity(i)
        v = self.volume / 100.0
        if kind == "loud":
            return conf * v
        return conf * (1.0 - v)

    def deviance_pressure(self):
        """**偏离氛围 → 压力（而非禁止）** —— 「社会压力」的机制化。

        你可以顶着氛围来，但要付代价：
          · 安静教室里偏要聊天 → 压力上升（会被侧目）
          · 吵闹教室里偏要学习 → 压力上升（"学不进去"）
        低从众度者（如高 J 的所谓"学霸"）不是不被罚，而是**本来就少偏离、且扛得住**。
        """
        k = self.env.get("deviance_k", 0.0)
        if k <= 0:
            return
        v = self.volume / 100.0
        loud = ("chat", "join_chat", "tease", "roughhouse")
        for i in range(self.N):
            act = self.current_act[i] or "study"
            if act in loud and v < 0.4:
                self.Stress[i] = clamp100(self.Stress[i] + k * (0.4 - v) * 10.0)
            elif act == "study" and v > 0.72:
                # 阈值取 0.72 而非 0.6：否则"音量略高于阈"就惩罚全部学习者，
                # 而 study 是默认行为 → 等于给全班加压力（实测会把爆发从 20 推到 70+）
                self.Stress[i] = clamp100(self.Stress[i] + k * (v - 0.72) * 10.0)

    def noise_pressure(self):
        """超阈音量 → 压力。极慢的涓流（每次结算一次），怕吵程度由性格决定。"""
        e = self.env
        excess = max(0.0, self.volume - e.get("volume_threshold", 60.0))
        if excess <= 0:
            return
        k = e.get("stress_k", 0.0)
        fj, fe = e.get("fear_j", 0.0), e.get("fear_e", 0.0)
        for i in range(self.N):
            # J 越高越受不了吵（§10.18 原意）—— 用助手，避免与 P 混淆
            fear = fj * self.arg_j(i) + fe * self.arg_i(i)
            fear = max(0.0, fear)
            # ⚠️ 加上**基础项**：嘈杂环境对**所有人**都有压力，不只是「怕吵的人」。
            # 此前只在 fear 上做文章，导致 stress_k 放大 12 倍仍无效 —— 因为压力只压到了少数内向/专注者。
            fear = e.get("noise_base_fear", 0.0) + fear
            self.Stress[i] = clamp100(self.Stress[i] + excess * k * fear)

    def conformity_hostility(self):
        """从众 → 敌对（§10.24）：**「大家都讨厌他，那我也讨厌他」**。

        这是把「散落的敌意」变成「集体围攻」的枢纽。排挤要求
        「**≥3 人同时对同一目标敌对 ≥40**」（`behavior_thresholds.csv`），
        而单靠一对一摩擦永远凑不齐那么多人 —— 之前实测就是：一个人到处欺负别人、
        其他人各有一条互怼边，**「被围攻」的格局出现不了**。

        有了从众，旁观者会**跟着已有的敌意走** —— 「欺凌」这才可能成立。

        从众度由性格给出（§10.19 `conformity`），**不需要特例**：
        高 F 者随大流，高 J / 高 N 者有自己的判断、不被裹挟 ——
        所以「敢替被孤立的人说话」这种人天然存在，**不必专门写一个"正义者"角色**。
        """
        # `conformity_see` 的语义已随信息来源改变（§10.24）：
        #   旧 = 「敌对值门槛」（读真值，已废弃）；新 = 「**公开敌对行为的可见窗口天数**」。
        see = self.thresholds_lookup.get("conformity_see", 25.0)
        see_window = self.thresholds_lookup.get("conformity_see_window", 14.0)
        need = int(self.thresholds_lookup.get("conformity_min", 2.0))
        for i in range(self.N):
            conf = self.conformity(i)
            if conf <= 0.05:
                continue                    # 有主见的人不被裹挟
            for j in range(self.N):
                if i == j:
                    continue
                # ⚠️ **不读真值敌对**（§7.4 不变式）：从众依循的是「**i 亲眼见过的敌对行为**」。
                #    旧写法 `self.H[k][j] >= see` 是**信息层穿透** —— 低透明度的人把恨藏起来，
                #    却仍会在这里扩散给从众者，直接破坏 §7.4「藏得住的人真的藏得住」。
                #    现用 `hurt_day[k][j]`（**公开**的 major 负性事件：当众羞辱 / 举报 / 排挤）：
                #    做过公开行为的人才被看见，藏着的人**不会被跟风**。
                haters = [k for k in self.neighbor_idx[i]
                          if k != j and not self.sleeping[k]
                          and 0 <= self.day - self.hurt_day[k][j] <= see_window]
                if len(haters) >= need:
                    # 跟着恨：人数越多、从众度越高，跟得越紧（走统一影响公式，scale 传从众度）
                    self.apply_event(i, j, "conformity_hostility",
                                     scale=conf * len(haters) / float(max(1, need)))

    def noise_of(self, j):
        """j 此刻的噪音贡献（来自 behaviors.csv 的 noise 列；0 = 安静）。"""
        return float(self.behaviors.get(self.current_act[j], {}).get("noise", 0.0))

    def noise_fear(self, i):
        """i 的「怕吵程度」（§10.18）：越内向、越专注，越受不了吵。

        与 `noise_pressure` 用的是**同一个 fear**（同源），只是后果不同。
        ⚠️ 待核验：`dims` 第 4 维在本原型里名为 `p`，而注释说的是「J（专注型）」，
        两者在 MBTI 里互斥（J 判/断 vs P 感知）。此处沿用现有实现的方向，暂不改动。
        """
        e = self.env
        fj, fe = e.get("fear_j", 0.0), e.get("fear_e", 0.0)
        f = fj * self.arg_j(i) + fe * self.arg_i(i)
        return max(0.0, f)

    def noise_hostility(self):
        """超阈音量 → **定向敌对**：怕吵的人会记恨「最吵的那个邻居」。

        **不对称是本机制的灵魂**（用户设计）：
          · **安静/学习者 → 敌视吵闹者** ✓ —— 他是真的在受损；
          · **吵闹者 → 敌视安静者** ✗ —— 他不觉得自己被打扰。
        ∴ 这是本项目第一条**天然单向**的关系通道（其余通道都是对称的）。

        与 `noise_pressure` 同源、不同轴：同一刺激，一份转化成**压力**（内耗），
        一份转化成**敌对**（指向他人）—— 这正是社会解释的分岔。

        为什么它能解决「种子频率太低」：音量**持续存在**，不像打闹那样稀疏，
        因此每个涓流周期都在累积，而且**方向明确**（对象是具体的「最吵的邻居」）。
        """
        e = self.env
        excess = max(0.0, self.volume - e.get("volume_threshold", 20.0))
        if excess <= 0:
            return
        scale = max(1e-6, e.get("noise_scale", 8.0))
        base = e.get("noise_hostility_base", 0.0) * min(2.0, excess / scale)
        if base <= 0:
            return
        for i in range(self.N):
            fear = self.noise_fear(i)
            if fear <= 0.05:
                continue                       # 不怕吵的人不会去恨（不对称的另一面）
            culprits = [j for j in self.neighbor_idx[i]
                        if j != i and not self.sleeping[j] and self.noise_of(j) > 0]
            if not culprits:
                continue
            # 恨「最吵的那个」—— 但**并列的第二个也恨**。
            # 只取 1 个时对象每次结算都在变，同一对子很难被反复命中（实测 H 上不去）；
            # 取 2 个既保留「盯着最吵的人」的方向性，又让敌意在**稳定的边**上真正累积。
            culprits.sort(key=self.noise_of, reverse=True)
            for j in culprits[:2]:
                self.apply_event(i, j, "noise_hostility", scale=base * fear)
                self.stats["noise_grudges"] = self.stats.get("noise_grudges", 0) + 1

    def spread_knot(self, i, severity=0.0):
        """爆发传染：把「心结」扩散给与 i 关系最鲜明的少数人。

        情绪传染沿**关系**传播 —— 与爆发者关系越鲜明（无论亲密还是敌对，|A − H| 越大），
        情绪共鸣越强、越容易被波及。这不是"随机撒点"，而是关系结构算出来的：
          · 死党的朋友会替他焦虑
          · 死对头也会因对手崩溃而兴奋/紧张
          · 泛泛之交则不受影响
        因此「连环爆发」的形态由班级关系结构决定，而非掷骰子。
        """
        tag = self.status_tags.get("heart_knot")
        if not tag:
            return
        ratio, kmax = float(tag.get("spread_ratio", 0)), int(float(tag.get("spread_max", 0)))
        if ratio <= 0 or kmax <= 0:
            return
        others = [j for j in range(self.N) if j != i and self.knot_days[j] == 0]
        if not others:
            return
        others.sort(key=lambda j: -abs(self.A[i][j] - self.H[i][j]))   # 关系最鲜明者优先
        pool = others[:max(1, int(len(others) * ratio))]
        # 越晚爆发（severity 越高）→ 波及越广、心结越久：这就是「拖得越久，爆得越大」
        kmax_eff = int(round(kmax * (1.0 + severity)))
        days_eff = int(round(float(tag["days"]) * (1.0 + severity)))
        for j in self.rng.sample(pool, min(kmax_eff, len(pool))):
            self.knot_days[j] = max(self.knot_days[j], days_eff)

    # ------------------------------------------------ 主循环
    def stress_drip(self):
        self.noise_pressure()      # 环境层：超阈音量 → 压力
        self.noise_hostility()     # 环境层：超阈音量 → 定向敌对（单向，§10.21）
        self.conformity_hostility()  # 社会层：从众 → 跟着恨（§10.24，让排挤凑得齐人）
        self.deviance_pressure()   # 环境层：偏离氛围 → 压力（不是禁止，是代价）
        """涓流：独处恢复 / 学习累积（主文档 §8.4）"""
        for i in range(self.N):
            if self.in_conversation[i]:
                continue                      # 参与互动者已由 topic_stress 减压
            if self.doing_study(i):
                self.Stress[i] = clamp100(self.Stress[i] + self.probs["study_stress"])
            else:
                self.Stress[i] = clamp100(self.Stress[i] + self.probs["alone_stress"])

    @staticmethod
    def doing_study(i):
        """原型简化：未参与互动即视为在原位学习（正式版按行为状态判定）"""
        return True

    def settle_sleep(self):
        """课间结束：睡了一整段的人**大幅减压**并醒来（§10.8）。

        "睡觉"是唯一"用社交机会换压力缓解"的策略 —— 它让压力有了一条
        **主动可控**的出口（此前只有闲聊被动减压与时间衰减）。
        """
        relief = self.probs.get("sleep_relief", 8.0)
        for i in range(self.N):
            if self.sleeping[i]:
                self.Stress[i] = clamp100(self.Stress[i] - relief)
                self.sleeping[i] = False
                self.busy_until[i] = 0
                self.current_act[i] = None

    def check_interrupt(self):
        """跨相位中断：行为还没做完就被「下课铃 / 上课铃」打断。

        耗时机制的直接推论 —— 课间只有 100 tick，一个 60 tick 的秘密交换很容易跨越过相位边界。
        被打断者获得压力代价（`interrupted_stress`），因为「话说到一半被打断」本身就是压力源。
        这也让「长行为」有了真实的代价：不是不能做，而是**要挑时机做**。

        ⚠️ 只有**尚未完成**的行为才算被打断（内核策划符合性审查 P1-04）：
        `busy_until <= global_tick` 说明它早就做完了，此时只清理占用记录、不施加压力代价。
        修复前只要有 busy_phase 记录且跨了相位就加压力，把「已完成」误判成「被铃声打断」。
        """
        cost = self.probs.get("interrupted_stress", 0.0)
        for i in range(self.N):
            if self.busy_phase[i] < 0:
                continue
            if self.busy_until[i] <= self.global_tick:
                self.busy_phase[i] = -1
                continue
            if self.busy_phase[i] != self.phase_index:
                self.busy_until[i] = 0
                self.busy_phase[i] = -1
                if cost > 0:
                    self.Stress[i] = clamp100(self.Stress[i] + cost)
                self.stats["interrupts"] = self.stats.get("interrupts", 0) + 1

    def settle_finished_actions(self):
        """行为完成结算：把**已到期**的占用收尾（§10.4 / §12.2 行为耗时契约）。

        占用到期即「这件事做完了」：清 current_act、清 busy_phase，并把行为名写进
        last_finished（仅本 tick 有效）。**「行为完成才发信息」的规则必须挂在这里**
        （例如玩家的闲聊线索），不能挂在「发起」上 —— 发起不等于做完。

        ⚠️ 与「被铃声打断」严格互斥：到期的不算被打断；未到期的才可能被 check_interrupt()
        在相位切换时打断。两边都不重复记。
        """
        self.player_invitations.expire()
        self.last_finished = [None] * self.N
        for i in range(self.N):
            if self.busy_phase[i] < 0 or self.busy_until[i] > self.global_tick:
                continue
            self.last_finished[i] = self.busy_act[i]
            self.current_act[i] = None
            self.busy_act[i] = None
            self.busy_phase[i] = -1

    def tick(self):
        self.global_tick += 1
        self.settle_finished_actions()
        self.decide_and_act()
        self.update_environment()
        if self.global_tick % int(self.p["settle_interval"]) == 0:   # 每天 2 次（上午/下午）
            self.transmission()
            self.stress_drip()
        # 压力爆发已在每日结算时按概率判定（见 try_burst），此处不再做阈值相变

    def run_day(self):
        phases = [("break", 100), ("class", 90), ("break", 100), ("class", 90), ("break", 100)]
        total_ticks = 0
        for pidx, (phase, ticks) in enumerate(phases):
            self.phase_index = pidx
            self.phase, self.tick_in_phase = phase, 0
            self.settle_sleep()               # 上一相位睡着的醒来（课间段结束才结算）
            self.roll_sleep()                 # 本段开始掷一次睡觉（段粒度，非 tick）
            self.free_join()                  # 「别人做什么我也跟着做」（free 类活动，§10.31）
            if phase == "break":
                self.phone_exposure()         # 举报把柄：课间目击「带手机」等标签行为痕迹（§10.2）
                self.roll_reports()           # 举报判定：每段一次，有把柄才掷骰（§10.2）
            self.check_interrupt()            # 相位切换 → 未完成的行为被打断
            for _ in range(ticks):
                self.tick()
                self.tick_in_phase += 1
                total_ticks += 1
            self.vol_log.append(round(self.volume, 1))   # 相位末采样
        self.settle_day()
        return total_ticks

    def try_burst(self):
        """概率爆发（不是「到点必爆」）。

        压力跨过入口阈值 `burst`（70，即 §8.3 高压区入口）后，**每天判定一次**：
            概率 p = burst_p_max × severity，其中 severity = (stress − θ) / (100 − θ)
        `severity` 同时放大**波及范围**与**心结时长** —— 于是「拖得越久、压力越高、爆得越大」，
        而大爆又会传染更广 → 这就是「连环爆发」的结构来源。

        为什么概率化：阈值处「必爆」会让行为在阈值附近疯狂跳变（UIF §2.6 边界③）；
        概率化之后，高压区是一个**危险斜区**，而不是一堵墙。
        """
        th = self.thresholds_lookup.get("burst_stress", 70.0)
        pmax = self.probs.get("burst_p_max", 0.0)
        if pmax <= 0:
            return
        tag = self.status_tags.get("heart_knot")
        for i in range(self.N):
            s = self.Stress[i]
            if s < th:
                continue
            severity = clamp((s - th) / (100.0 - th), 0.0, 1.0)
            if self.rng.random() >= pmax * severity:
                continue
            self.Stress[i] = clamp100(s - 40)
            if tag:
                self.knot_days[i] = max(self.knot_days[i],
                                        int(round(float(tag["days"]) * (1.0 + severity))))
            self.spread_knot(i, severity)
            self.stats["bursts"] += 1

    def settle_day(self):
        """跨天结算（§3.5）"""
        self.try_burst()                      # 每日一次：压力爆发按概率判定
        d = self.decay
        # 信念遗忘回归（`belief.lambda_b`）：每天把信念向先验缓慢拉回 —— 信念不能"只学不忘"，
        # 否则久了会固执地停在某个旧印象上（§18.9 列为未落实项，本轮补齐）。
        lam = self.bp.get("lambda_b", 0.0)
        if lam > 0:
            prior = {"affinity": self.bp["prior_a"], "hostility": self.bp["prior_h"],
                     "trust": self.bp["prior_t"]}
            for i in range(self.N):
                for j in range(self.N):
                    if i == j:
                        continue
                    for ax in AXES:
                        cur = self.B[ax][i][j]
                        self.B[ax][i][j] = clamp100(cur + lam * (prior[ax] - cur))

        # 「心结」：爆发后的 3 天里，每天先加 5 点压力（长线心理创伤，§3.5）
        for i in range(self.N):
            if self.knot_days[i] > 0:
                self.Stress[i] = clamp100(self.Stress[i] + float(self.status_tags["heart_knot"]["daily_stress"]))
                self.knot_days[i] -= 1
        for i in range(self.N):
            for j in range(self.N):
                if i == j:
                    continue
                interacted = self.day_events.get((i, j), 0) >= d["interact_min_events"]
                self.A[i][j] *= d["decay_a_interact"] if interacted else d["decay_a_no_interact"]
                # 两层敌对（§10.22）：深层原样保留，只衰减**表层**。
                # 「表层怒火会消，但心结永远在」—— 所以「可以原谅，但忘不了」。
                # ⚠️ 表层要夹到 ≥0：H 会被别的负向事件（和解类）降到低于 deep，
                #    那时 `H - deep` 为负，若不夹住会把负数继续带下去 ——
                #    结果出现「深层 17.5 而总数只有 9.0」的自相矛盾（深层本应是**底线**）。
                # 深层**极慢衰减**（§10.29）：这是「忘不掉」与「吸收态」之间的平衡。
                #   · 30 天尺度：0.995^30 ≈ 0.86 → 几乎不衰减，「忘不了」依然成立；
                #   · 百年尺度：会缓慢收敛 → 死仇也有解冻的可能，
                #     **保住结局空间的开放性**（否则所有局最终都掉进同一个终态）。
                dd = d.get("deep_decay", 0.995)
                self.H_deep[i][j] *= dd
                deep = self.H_deep[i][j]
                surf = max(0.0, self.H[i][j] - deep)
                self.H[i][j] = min(100.0, deep + surf * d["decay_h"])
                self.T[i][j] *= d["decay_t"]
            self.Stress[i] *= d["retain_s"]
        self.day_events.clear()          # 新的一天，重置「有互动」判定
        self.day += 1

    # ------------------------------------------------ 报告
    def report(self):
        n = self.N
        pairs = [(i, j) for i in range(n) for j in range(n) if i != j]
        aff = [self.A[i][j] for i, j in pairs]
        aff.sort()
        mean = sum(aff) / len(aff)
        saturated = sum(1 for v in aff if v >= 95) / len(aff)
        err = 0.0
        for i, j in pairs:
            err += abs(self.B["affinity"][i][j] - self.A[j][i])
        err /= len(pairs)
        print("=== 内核运行统计（seed=%d, 天数=%d, 节点=%d）===" % (self.seed, self.day - 1, self.N))
        print("  好感：min %.1f / 中位 %.1f / 均值 %.1f / max %.1f" % (aff[0], aff[len(aff) // 2], mean, aff[-1]))
        print("  接近饱和(>=95)比例：%.1f%%" % (saturated * 100))
        print("  事件 %d 次（闲聊 %d / 搭话 %d / 举报 %d）" % (
            self.stats["events"], self.stats["chats"], self.stats["joins"], self.stats["reports"]))
        print("  睡着 %d 人次 | 调侃 %d（过火 %d）/ 流言 %d / 排挤 %d / 打闹 %d / 被打断 %d" % (
            self.stats.get("sleeps", 0),
            self.stats["teases"], self.stats["tease_fail"], self.stats["rumors"],
            self.stats.get("excludes", 0), self.stats.get("roughhouse", 0),
            self.stats.get("interrupts", 0)))
        print("  去重跳过 %d 次" % self.stats["dedup_skips"])
        print("  传导结算 %d 次 | 压力爆发 %d 次（平均每 %.1f 天一次）" % (
            self.stats["transmission_ticks"], self.stats["bursts"],
            (self.day - 1) / max(1, self.stats["bursts"])))
        print("  信念平均误差 |B − 真值|：%.1f" % err)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=1)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--npc", type=int, default=16)
    args = ap.parse_args()
    sim = Sim(seed=args.seed, npc_count=args.npc)
    for _ in range(args.days):
        sim.run_day()
    sim.report()


if __name__ == "__main__":
    main()

class ObserverLayer:
    """观察层：**只读**、**按透明度过滤**、**每个角色一份视角**的标签器。

    为什么是「透明度的下属」（用户判断 + §7.4）：
      「只读」只保证标签**不干扰**模拟；但若直接读真值矩阵，它对玩家就是**上帝视角** ——
      低透明度角色的「藏」会在标签层被绕过。§7.4 的原则是「**凡是涉及感知的读取，
      都要经透明度（+信任）过滤**」，而标签器的输出正是「**玩家感知到的班级结构**」，
      因此它天然归这条原则管辖。

    于是：**低透明度的人，他的关系看不透 → 标签器不会把他归进任何簇**
    ——「藏着的人，连标签都藏住了」，这是 §7.4 精神的自然延伸。

    规格来源：`docs/design/信念矩阵.md` §11（可见性档位 / null≠0 / 只读查询）。
    阈值来源：§11.1 复用系统已有阈值（亲近 A≥60、敌对 H≥40），**不另定**。
    """

    def __init__(self, sim):
        self.s = sim

    # ---------- ① 可见性档位（§11.1 / §11.3：由「被观测者」的透明度决定）----------
    def visibility(self, viewer, target):
        """返回 'clear' / 'blurry' / 'sealed'。**由被观测者 O[target] 决定**，与 viewer 无关。"""
        o = self.s.O[target]
        if o >= 50.0:
            return "clear"
        if o >= 20.0:
            return "blurry"
        return "sealed"

    # ---------- ② 该 viewer 能看见的关系矩阵 ----------
    def seen_matrix(self, viewer, axis="affinity"):
        """返回 viewer 眼中的 axis 关系矩阵（`None` = 看不见）。

        · clear  → 真值（他演出来的就是真实的）
        · blurry → **只知「有没有变化」，不知方向**（§11.2 `null ≠ 0`）→ 用中性基准代替
        · sealed → `None`（你看不见 → 你不知道）
        """
        n = self.s.N
        src = {"affinity": self.s.A, "hostility": self.s.H, "trust": self.s.T}[axis]
        base = 50.0 if axis != "hostility" else 0.0
        out = [[None] * n for _ in range(n)]
        for k in range(n):                       # k = 被观测的「一边」
            vis = self.visibility(viewer, k)
            for m in range(n):
                if k == m:
                    continue
                if vis == "clear":
                    out[k][m] = src[k][m]
                elif vis == "blurry":
                    out[k][m] = base           # 只知「有变化」——不给方向，故取中性
                # sealed: 保持 None
        return out

    # ---------- ③ 簇标签（每个角色一份视角）----------
    def cluster_tags(self, viewer):
        """viewer 眼中的小团体：按 §11.1 的强连接阈值 A≥60 取连通分量（≥3 人成簇）。

        因为关系先经透明度过滤，"看不透的人"自然落不进任何簇。
        """
        n = self.s.N
        seen = self.seen_matrix(viewer, "affinity")
        # §11.1 的绝对阈值 A≥60 是**基线**；但实测好感均值已到 57，「60」在实际分布下不构成「强」连接
        # （会连成一个 15 人的巨簇）。∴ 再加一条**相对**判据：这条边要比「双方各自的多数关系」都更亲近。
        TH_A = 60.0
        # 每个人可观测关系的分位基准（只统计他看得见的部分）
        pct = {}
        for i in range(n):
            vals = sorted(v for v in seen[i] if v is not None)
            pct[i] = vals[int(len(vals) * 0.75)] if len(vals) >= 3 else 10 ** 9
        # 无向强连接图：双方都看得见 + 都过绝对阈值 + 都比各自 75 分位更高
        adj = {i: set() for i in range(n)}
        for i in range(n):
            for j in range(i + 1, n):
                a1 = seen[i][j]
                a2 = seen[j][i]
                if (a1 is not None and a2 is not None and a1 >= TH_A and a2 >= TH_A
                        and a1 >= pct[i] and a2 >= pct[j]):
                    adj[i].add(j)
                    adj[j].add(i)
        seen_set = set()
        clusters = []
        for i in range(n):
            if i in seen_set:
                continue
            stack, comp = [i], []
            while stack:
                x = stack.pop()
                if x in seen_set:
                    continue
                seen_set.add(x)
                comp.append(x)
                stack.extend(adj[x] - seen_set)
            if len(comp) >= 3:
                clusters.append(sorted(comp))
        return sorted(clusters, key=lambda c: (-len(c), c[0]))

    # ---------- ④ 孤立标签 ----------
    def isolated_tags(self, viewer):
        """viewer 眼中的「被孤立者」：**他人→他显著低，而他→他人接近正常**。

        判据来自 §10.26.3：「全班都不喜欢他，而他还喜欢大家」——想融入但没人要他。
        ⚠️ 同样只读 viewer 能看见的部分。
        """
        n = self.s.N
        seen = self.seen_matrix(viewer, "affinity")
        recv, give = {}, {}
        for j in range(n):
            r = [seen[k][j] for k in range(n) if k != j and seen[k][j] is not None]
            g = [seen[j][k] for k in range(n) if k != j and seen[j][k] is not None]
            if len(r) >= 3 and len(g) >= 3:
                recv[j] = sum(r) / len(r)
                give[j] = sum(g) / len(g)
        if not recv:
            return []
        avg = sum(recv.values()) / len(recv)
        out = []
        for j in recv:
            if recv[j] < avg - 15.0 and give[j] > recv[j] + 15.0:
                out.append(j)
        return sorted(out, key=lambda j: recv[j])

    # ---------- 汇总：一份「某人眼中的班级格局」----------
    def view(self, viewer):
        return {
            "viewer": viewer,
            "clusters": self.cluster_tags(viewer),
            "isolated": self.isolated_tags(viewer),
        }
