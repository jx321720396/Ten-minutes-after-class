"""最小无头内核原型（Python）

用途：验证 docs/design/ 里的公式与不变式；Godot 版（scripts/core/）可据此移植。
依据：docs/design/统一影响公式.md、NPC行为决策.md、主文档 §3/§5–§10
运行：python tools/core_sim.py --days 1 --seed 12345

实现范围（「最小」= 够验证公式，不追求全部行为）：
  · 时间：天 / 相位（课间×3、上课×2）/ tick（课间 100、上课 90）
  · 状态：A/H 有向矩阵（16×16）、Stress/StudyAcc/Grade 个体量（长度 16）
  · 统一影响公式：E × 关系调制 → 软饱和 → round(0.1) → 写入
  · 行为：闲聊 / 搭话 / 多人聊天 / 打闹 / 学习 / 娱乐 / 睡觉（老师版 §9.2 + §9.4 行为集）
  · 跨天：衰减 + 座位重排（简化为随机重排相邻关系）
"""

import argparse
import csv
import math
import os
import random
from player_invitations import PlayerInvitations, invitation_behavior
from teacher_patrol import TeacherPatrol

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

AXES = ("affinity", "hostility")

# 主动行为的冷却（tick）：每角色每这么久最多发起一次行为
# ⚠️ 文档未规定，属实现补充；待标定（见 docs/design/NPC行为决策.md 待确认）
ACTION_COOLDOWN = 20
LEISURE_KINDS = {"listen_music": "music", "eat_snack": "snack", "read_book": "book"}


# ---------------------------------------------------------------- 工具
def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def _u32(x):
    return x & 0xFFFFFFFF


def exam_unit(seed_value, exam_index, node, salt):
    """与 ExamSettle._unit 逐式对齐的 32 位混合，结果落在 (0, 1)。"""
    x = _u32(seed_value)
    x = _u32(x ^ _u32(exam_index * 0x9E3779B1))
    x = _u32(x ^ _u32(node * 0x85EBCA6B))
    x = _u32(x ^ _u32(salt))
    x = _u32(x ^ (x >> 16))
    x = _u32(x * 0x7FEB352D)
    x = _u32(x ^ (x >> 15))
    x = _u32(x * 0x846CA68B)
    x = _u32(x ^ (x >> 16))
    return (x + 1) / 4294967297.0


def exam_q6(z):
    scaled = z * 1000000.0
    if z >= 0.0:
        return math.floor(scaled + 0.5) / 1000000.0
    return math.ceil(scaled - 0.5) / 1000000.0


def exam_quantized_normal(seed_value, exam_index, node):
    u1 = exam_unit(seed_value, exam_index, node, 1)
    u2 = exam_unit(seed_value, exam_index, node, 2)
    z = math.sqrt(-2.0 * math.log(u1)) * math.cos(math.tau * u2)
    return exam_q6(z)


def exam_rint(v):
    """对齐 Python round 的半偶，以及 SimCore._rint。"""
    return int(round(v))


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
def default_npc_count():
    """一局 NPC 数：读 data/rules/roster.csv（数值集中 data/，与 GDScript 侧同一个来源）。"""
    for row in load_table("rules/roster.csv"):
        if row.get("key") == "npc_count":
            return int(float(row["value"]))
    return len(load_table("characters/seeds.csv"))


class Sim:
    def __init__(self, seed=12345, npc_count=None, verbose=False):
        if npc_count is None:
            npc_count = default_npc_count()
        self.rng = random.Random(seed)
        self.seed = seed
        self.verbose = verbose

        # --- 配置 ---
        self.leisure = load_params("rules/leisure.csv")
        self.absence = load_params("rules/player_absence.csv")
        self.player_absent = False
        self.leave_count = 0
        self.p = load_params("rules/transmission.csv")
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
        # 内核硬编码系数（grade 等初始化常量）—— 从 kernel_params.csv 读，与 GDScript 内核同源。
        self.kp = load_params("rules/kernel_params.csv")
        # 成绩涓流分段表（§17.1.2）：band_upper 升序。
        self.grade_bands = sorted(
            [(float(r["band_upper"]), float(r["ticks_per_point"]))
             for r in load_table("rules/grade_table.csv")],
            key=lambda x: x[0])
        seeds = load_table("characters/seeds.csv")

        # --- 装配本局阵容（池 = 一局人数；洗牌只决定顺序，§11.5 的绑定组/原型去重仍未接入）---
        pool = seeds[:]
        self.rng.shuffle(pool)
        # 持书配额单值（rules/leisure.csv 的 book_count）；不得超过本局人数
        book_count = min(int(self.leisure["book_count"]), npc_count)
        books = [c for c in pool if c["book"] == "1"][:book_count]
        others = [c for c in pool if c["book"] == "0"][:npc_count - book_count]
        self.chars = [c for c in pool if c in books or c in others]
        self.book = [int(c["book"]) for c in self.chars] + [0]
        self.snacks_remaining = int(self.leisure["snack_count_per_run"])
        for kind, prefix in LEISURE_KINDS.items():
            self.behaviors[kind] = dict(duration=int(self.leisure[prefix + "_duration"]),
                                        noise=self.leisure[prefix + "_noise"],
                                        kind="env", join_mode="none")
        self.N = len(self.chars) + 1  # 索引 N-1 为玩家；实际人数以入池者为准（请求数超过池人数时自动夹紧）
        self.teacher = TeacherPatrol(load_params("rules/teacher.csv"), self.N)

        # --- 状态矩阵 ---
        n = self.N
        self.A = [[0.0] * n for _ in range(n)]
        self.H = [[0.0] * n for _ in range(n)]
        self.Stress = [0.0] * n
        self.Grade = [0.0] * n         # 成绩（§17.1）
        self.StudyAcc = [0.0] * n      # 学习时长累加器（§17.1.2）

        # --- 初始化 ---
        self._init_relations()
        self._init_grade()
        self._init_exam()

        # --- 时间与统计 ---
        self.day = 1
        self.phase = "break"
        self.tick_in_phase = 0
        # 一天的相位序列（段名, tick 数）。与 GDScript 内核 `_active_phases` 对齐（break/class 交替）。
        self.day_phases = [("break", 100), ("class", 90), ("break", 100), ("class", 90), ("break", 100)]
        self.stats = {"events": 0, "chats": 0, "joins": 0, "bursts": 0,
                      "interrupts": 0,
                      "skipped_events": 0, "dedup_skips": 0,
                      "roughhouse": 0, "sleeps": 0,
                      "chat_joins": 0, "join_vetoes": 0, "chat_leaves": 0,
                      "chat_max_size": 0}
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
        # 座位范围（§8.23）：**桌椅占位矩形**，由表现层注入 index -> (x, z, w, h)
        self.seat_world = {}
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
        # --- 空间层（§15.1、§10.17.2 种子一）：座位表 + 邻接 ---
        self.seats = load_table("rules/seats.csv")
        self.seat_pos = {r["seat_id"]: (int(r["row"]), int(r["col"])) for r in self.seats}
        self.seat_of = [None] * n         # 角色 -> seat_id
        self.neighbors = self._build_neighbors()
        self.assign_seats()               # 必须在 seats/neighbors 定义之后
        self.in_conversation = [False] * n
        # 多人聊天（2026-10-14 重构）：会话 = 成员集合，逐人计时，2→3→4 递进加入。
        self.conversations = []          # 会话列表：{"members": set}
        self.conv_of = [None] * n        # 节点 -> 所在会话（None = 不在会话）
        self.join_log = []               # 加入判定日志（谁欢迎/谁拒绝/原因，只读观察）
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
        # 环境事实（§11.3）：小情侣绑定、佳豪对外好感 50
        idx = {c["alias"]: k for k, c in enumerate(self.chars)}
        if "陈阳" in idx and "林晚" in idx:
            a, b = idx["陈阳"], idx["林晚"]
            self.A[a][b] = self.A[b][a] = 85.0
        if "佳豪" in idx:
            g = idx["佳豪"]
            for j in range(n):
                if j != g:
                    self.A[g][j] = 50.0

    def _init_grade(self):
        """成绩初始化（§17.1.1）：NPC 种子化均匀 [min,max)，玩家固定。消费 len(chars) 次 RNG。

        ⚠️ 必须紧跟 `_init_relations()` 之后调用，与 GDScript 同一点插入，保同种子 RNG 流不漂移。
        """
        gmin = self.kp["grade_init_npc_min"]
        gmax = self.kp["grade_init_npc_max"]
        for i in range(len(self.chars)):
            self.Grade[i] = gmin + self.rng.random() * (gmax - gmin)
        self.Grade[self.N - 1] = self.kp["grade_init_player"]

    # ------------------------------------------------ 派生量
    def m_relation(self, i, j):
        """关系调制 M = clamp((A − H)/50, −1, +1)。

        关系差时「聊了反而掉好感」是设计意图（§2.1）—— 保留反转。
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

        · 好感：越满越难涨 —— 这就是阻止「30 天全班一起封顶」的机制
        · 敌对 / 压力：不加负反馈，否则「敌意升级」会被压死
        """
        if self.feedback <= 0 or axis in ("hostility", "stress"):
            return 1.0
        return max(0.0, 1.0 - self.feedback * value / 100.0)

    def sat(self, u, axis):
        key = {"affinity": "u_a", "hostility": "u_h", "stress": "u_s"}[axis]
        U = self.p.get(key, 25.0)
        return u / (1.0 + abs(u) / U)

    # ------------------------------------------------ 事件写入
    def apply_event(self, i, j, event_id, scale=1.0):
        """按统一影响公式写入：E × 关系调制 → 软饱和 → round(0.1) → clamp

        含事件去重：同一对子同一规则每课间段只结算一次（§2.5.4）

        `scale`：**外部幅度系数**（默认 1.0）—— 让「同一事件」随情境强弱缩放。
        它与 `base` 相乘、仍走同一套公式，不是旁路写入（保持 §2.6 的单一写入点）。
        """

        if not self.is_present(i) or not self.is_present(j):
            return False
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
            e_val = base * scale
            if axis in AXES:
                e_val *= self.m_relation(i, j)
            m = self.m_state(i, negative=(base < 0) == (axis in AXES))
            delta = r1(m * self.sat(e_val, axis)) if axis != "stress" else r1(self.sat(e_val, axis))
            if axis == "stress":
                self.Stress[i] = clamp100(self.Stress[i] + delta)
            else:
                target = {"affinity": self.A, "hostility": self.H}[axis]
                # 统一写入点：正向轴乘负反馈（越满越难涨）
                delta = r1(self.room_for(axis, target[i][j]) * delta)
                target[i][j] = clamp100(target[i][j] + delta)
            applied = True
            self.stats["events"] += 1
        return applied

    # ------------------------------------------------ 决策
    def alpha(self, i):
        # 老师版删四维：意向权重退化为 A/H/stress 常数（§5）。
        raw = {
            "affinity": self.nw["alpha_a_base"],
            "hostility": self.nw["alpha_h_base"],
            "stress": self.nw["alpha_s_base"],
        }
        total = sum(raw.values())
        return {k: v / total for k, v in raw.items()}

    def tau(self, i):
        t = self.nw["tau0"]
        if self.Stress[i] >= 70:
            t *= self.nw["tau_stress_mult"]
        return max(t, 0.01)

    def join_gate_utility(self, i, j):
        """决策侧软门槛：低于门槛只降低概率，不把候选排除（§6.4）。

        硬门槛曾被写成 `A[i][j] >= 30 and Stress[i] <= 80`，于是「概率低也想试一把」
        的戏剧性被消灭。改为两个 sigmoid 之和再减 1，落在 (−1, +1)：
        越过门槛给正分、低于门槛给负分，乘以 `chat_join_gate_weight` 后加进 U_b。
        """
        th = self.thresholds_lookup
        ga = th.get("chat_join_gate_affinity", 30.0)
        gs = th.get("chat_join_gate_stress", 80.0)
        scale = th.get("chat_join_gate_scale", 8.0)
        w = th.get("chat_join_gate_weight", 4.0)
        za = (self.A[i][j] - ga) / scale
        zs = (gs - self.Stress[i]) / scale
        return w * (sigmoid(za) + sigmoid(zs) - 1.0)

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
        """判定侧 score：**被请求者的真值好感 `A[j][i]`** − 对方压力惩罚（§6.4）。

        判定读真值 —— 「他会不会接纳我」由**他的真实态度**决定，不由我的猜测决定；
        我的猜测只进两处：决策侧（要不要去试）与展示层（成功率）。两者之差就是误判，
        也正是本作「信息不对称」的来源（§9.4、§10.32.3）。

        ⚠️ 这里读 `A[j][i]`（别人对我的态度）**不违反** §18.7 不变式 3 ——
        该不变式禁止的是**决策路径**读它；本方法属**判定路径**，规格要求它读真值。

        压力是程度不是闸门：`hot ∈ [0,1]` 乘上 `chat_join_stress_penalty` 压低 score，
        而不是把 p 归零。

        ⚠️ 2026-10-14 删四维外向项（老师版删除隐藏性格四维，聊天机制规格 I）：
        `base` 不再含 `(dims[j][0]−50)·0.3`。
        """
        base = self.A[j][i]
        hot = max(0.0, self.Stress[j] - 50.0) / 50.0
        penalty = self.thresholds_lookup.get("chat_join_stress_penalty", 12.0)
        return base - penalty * hot

    def join_probability(self, i, j):
        """判定侧概率：p = σ((score − θ)/scale)，永不为 0/1（§6.4）。"""
        th = self.thresholds_lookup
        theta = th.get("chat_join_affinity", 45.0)
        scale = th.get("chat_join_scale", 10.0)
        return sigmoid((self.join_score(i, j) - theta) / scale)

    def join_feedback(self, i, j):
        """只读：返回玩家侧会看到的成功率 `p`（§10.32）。

        2026-10-14 删信念/透明度后玩家可读真值：显示概率 = 实际结算概率（读 A[j][i]）。
        """
        th = self.thresholds_lookup
        hot = max(0.0, self.Stress[j] - 50.0) / 50.0
        score = self.A[j][i] - th.get("chat_join_stress_penalty", 12.0) * hot
        theta = th.get("chat_join_affinity", 45.0)
        scale = th.get("chat_join_scale", 10.0)
        return {"p": round(sigmoid((score - theta) / scale), 2)}

    # ---------- 玩家侧判定展示（NPC 静默，玩家可见过程）----------
    def verdict(self, i, j, kind="join"):
        """**一次判定的展示包**：涉及玩家时展示三拍 = ① 当前成功率 → ② 掷骰 → ③ 结果。

        与判定本身**完全分离**：判定用 `do_chat_join` 照常静默执行，
        本方法只是**只读地取出「此刻玩家会看到的那个概率与结果」**，不参与结算。
        """
        if kind == "join":
            fb = self.join_feedback(i, j)
            roll = self.rng.random()
            return {
                "kind": kind,
                "p": fb["p"],                    # ① 成功率
                "roll": roll,                    # ② 掷骰
                "ok": roll < self.join_probability(i, j),   # ③ 结果（与 do_chat_join 同一 p）
                "note": "成功与否看对方对你的真实好感。",
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
            leisure_started = False
            for kind, prefix in LEISURE_KINDS.items():
                if self.allowed(kind) and (kind != "read_book" or self.book[i] > 0):
                    if self.rng.random() < self.probs[prefix + "_p"]:
                        self.start_leisure(i, kind)
                        leisure_started = True
                        break
            if leisure_started:
                busy.add(i)
                continue
            # 环境类：学习（§8.23）—— 主动坐下学一整个课间；爱学习的人更常坐下来
            study_gain = 1.0 + self.tag_bias(i, "study_bias")
            if self.allowed("study") and self.rng.random() < self.probs.get("study_p", 0.0) * study_gain:
                self.do_study(i)
                busy.add(i)
                continue
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
            # 环境类：加入群聊（2026-10-14 重构）—— 空闲者尝试加入一场正在进行的 NPC 会话
            # （双向判定 + 聚合接纳 + 规模衰减，见 try_join_conversation；含玩家的会话不参与自主加入）
            if self.allowed("chat") and self.conversations and self.rng.random() < self.probs.get("chat_join_p", 0.0):
                if self.try_join_conversation(i):
                    busy.add(i)
                    continue
            # 意向类：追逐打闹 —— 参与者互相好感↑（老师版 §9.2，去四维门槛与旁观者敌对）
            th_rc = int(self.thresholds_lookup.get("roughhouse_count", 2))
            if self.allowed("roughhouse") and self.rng.random() < self.probs.get("roughhouse_p", 0.05) * self.teacher.multiplier("roughhouse"):
                others = [j for j in range(n) if j != i and j not in busy and self.can_interact_with(j)]
                if others:
                    j = self.rng.choice(others)
                    bys = [k for k in range(n) if k not in (i, j) and k not in busy]
                    if len(bys) >= th_rc:
                        self.do_roughhouse(i, j)
                        busy.add(i)
                        busy.add(j)
                        continue
            # 意向类：搭话（老师版 §9.2）—— 决策读「我对他」的 A/H（§18.7 不变式 3）
            cands = [j for j in range(n) if j != i and j not in busy and self.can_interact_with(j)]
            if cands:
                alpha = self.alpha(i)
                scores = []
                for j in cands:
                    gain_a = self.A[i][j] / 100.0 * 3.0  # 预期收益（读我对他好感）
                    risk_h = self.H[i][j] / 100.0 * 2.0
                    u = alpha["affinity"] * gain_a - alpha["hostility"] * risk_h
                    u += self.tag_bias(i, "chat_bias") - self.tag_bias(i, "alone_bias")  # 标签项
                    u += self.join_gate_utility(i, j)   # 软门槛：低门槛仍可有小概率发起（§6.4）
                    scores.append(u)
                if scores:
                    k = softmax(scores, self.tau(i), self.rng)
                    j = cands[k]
                    self.do_chat_join(i, j)
                    busy.add(i)
                    busy.add(j)

    def is_present(self, i):
        return not (i == self.N - 1 and self.player_absent)

    def start_leisure(self, i, kind):
        if kind not in LEISURE_KINDS or not self.allowed(kind) or not self.can_interact_with(i):
            return False
        if kind == "read_book" and self.book[i] <= 0:
            return False
        if i == self.N - 1 and kind == "eat_snack":
            if self.snacks_remaining <= 0:
                return False
            self.snacks_remaining -= 1
        self.occupy(i, i, kind)
        self.stats[kind] = self.stats.get(kind, 0) + 1
        if kind == "read_book":
            self.teacher.catch_reader(self, i)
        return True

    def leave_class(self):
        me = self.N - 1
        if not self.allowed("leave_class") or not self.can_interact_with(me):
            return False
        if self.leave_count >= self.absence["max_per_break"]:
            return False
        for j in self.neighbor_idx[me]:
            self.apply_event(j, me, "leave_absence")
        self.leave_count += 1
        self.player_absent = True
        self.current_act[me] = "leave_class"
        self.busy_until[me] = self.global_tick + self.day_phases[self.phase_index][1] - self.tick_in_phase
        self.player_invitations.expire()
        return True

    def class_affinity_settle(self):
        for i in range(self.N):
            if self.sleeping[i] or not self.is_present(i):
                continue
            for j in self.neighbor_idx[i]:
                if not self.sleeping[j] and self.is_present(j):
                    self.A[i][j] = clamp100(self.A[i][j] + self.p["class_affinity_gain"])

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
        return self.is_present(j) and (not self.sleeping[j]) and self.global_tick >= self.busy_until[j]

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
        if self.current_act[i] == "study":
            self.StudyAcc[i] = 0.0
        self.current_act[i] = behavior
        # quiet=True：加入 / 被搭话的一方 —— 同一场对话只算**一个声源**
        # （现实里多一个人加入同一场聊天，音量几乎不变；让教室变吵的是「多摊人各自在聊」）
        occupy_target = j != self.N - 1 or i == self.N - 1 or self.player_invitations.authorizes(i)
        if occupy_target:
            if self.current_act[j] == "study":
                self.StudyAcc[j] = 0.0
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
        """闲聊（会话种子，规格 B）：i 与 j 开聊，形成二人会话，他人可随后加入。"""
        self.start_conversation(i, j)

    @invitation_behavior("chat")
    def do_chat_join(self, i, j, roll=None):
        """搭话（二人会话种子，含接纳判定，规格 E/I）：i 接近 j，j 按 p=σ((score−θ)/scale)
        接纳则开聊（score 已删四维项）；拒绝则记单向拒绝事件，不占时间槽。

        没有硬闸门：概率低也可能被接纳、概率高也可能被拒。
        `roll` 可由调用方（玩家 UI）预先掷好，保证「三拍展示」与实际结算一致。
        """
        p = self.join_probability(i, j)
        choice = self.player_invitations.choice_for(i)
        if choice is not None:
            p, roll = (1.0 if choice else 0.0), 0.0
        elif roll is None:
            roll = self.rng.random()
        if roll < p:
            self.start_conversation(i, j)
            self.stats["joins"] += 1
            self.stats["join_accepts"] = self.stats.get("join_accepts", 0) + 1
        else:
            self.apply_event(i, j, "reject_affinity")
            self.apply_event(i, j, "reject_hostility")
            self.apply_event(i, j, "reject_stress")
            self.stats["joins"] += 1
            self.stats["join_rejects"] = self.stats.get("join_rejects", 0) + 1
            self.stats["skipped_events"] += 1

    # ---------- 多人聊天会话子系统（2026-10-14 重构：2→3→4 递进加入）----------

    def start_conversation(self, i, j):
        """二人开聊（会话种子，规格 B）：形成会话 {i,j}，逐人独立计时，他人可随后加入。"""
        conv = {"members": {i, j}}
        self.conversations.append(conv)
        self.conv_of[i] = conv
        self.conv_of[j] = conv
        self.in_conversation[i] = True
        self.in_conversation[j] = True
        self._occupy_chat(i)
        self._occupy_chat(j)
        self._settle_chat_pair(i, j)
        self.stats["chats"] += 1

    def _chat_duration(self):
        """聊天时长：base × uniform[jitter_min, jitter_max]，逐人独立（规格 ③）。"""
        base = self.behaviors.get("chat", {}).get("duration", 30)
        lo = self.thresholds_lookup.get("chat_duration_jitter_min", 0.8)
        hi = self.thresholds_lookup.get("chat_duration_jitter_max", 1.2)
        return max(1, int(base * self.rng.uniform(lo, hi)))

    def _occupy_chat(self, i):
        """把 i 置为聊天占用（独立时长）。不写 busy_phase —— 聊天由 settle_conversations /
        _interrupt_conversations 专责，不经过「到期结算 / 被打断」两套通用协议。"""
        self.current_act[i] = "chat"
        self.busy_until[i] = max(self.busy_until[i], self.global_tick + self._chat_duration())
        self.busy_act[i] = "chat"

    def _settle_chat_pair(self, initiator, existing):
        """initiator 与 existing 之间的聊天结算（两轴：好感 + 压力）。"""
        self.apply_event(initiator, existing, "topic_affinity")
        self.apply_event(initiator, existing, "topic_stress")
        self.apply_event(existing, initiator, "topic_affinity")

    def _joinable_conversations(self, i):
        """i 可加入的会话：不含玩家（玩家交互走邀请机制）、且至少一名成员是 i 的邻居（邻域）。"""
        out = []
        for conv in self.conversations:
            if self.N - 1 in conv["members"]:
                continue
            if any(m in self.neighbor_idx[i] for m in conv["members"]):
                out.append(conv)
        return out

    def _desire_join(self, i, members):
        """意愿侧（加入者想不想进）：朋友在场（max A[i][m]）拉高意愿；明显敌对（H[i][m] ≥ veto）劝退。"""
        veto = self.thresholds_lookup.get("chat_hostility_veto", 50.0)
        if max(self.H[i][m] for m in members) >= veto:
            return False
        max_a = max(self.A[i][m] for m in members)
        theta = self.thresholds_lookup.get("chat_desire_theta", 40.0)
        scale = self.thresholds_lookup.get("chat_desire_scale", 10.0)
        return self.rng.random() < sigmoid((max_a - theta) / scale)

    def _welcome_probability(self, m, i, size):
        """接纳侧：成员 m 对加入者 i 的欢迎概率 = σ((A[m][i] − H[m][i] − θ)/scale) × w_size(size)。
        w_size(s) = 1/(1 + k·(s − s0))，s = 加入前成员数（规格 ② 有理衰减）。"""
        th = self.thresholds_lookup
        theta = th.get("chat_welcome_theta", 40.0)
        scale = th.get("chat_welcome_scale", 12.0)
        k = th.get("chat_size_k", 0.3)
        s0 = th.get("chat_size_s0", 4.0)
        w = 1.0 if size <= s0 else 1.0 / (1.0 + k * (size - s0))
        p = sigmoid((self.A[m][i] - self.H[m][i] - theta) / scale)
        return clamp(p * w, 0.0, 1.0)

    def try_join_conversation(self, i):
        """空闲者 i 尝试加入一场正在进行的 NPC 会话（双向判定 + 聚合接纳 + 规模衰减）。

        规格 B–I：意愿侧（想不想进）+ 接纳侧（成员欢不欢迎）；聚合 = 欢迎数 > 拒绝数
        （平票=拒绝）；任一成员 H[m][i] ≥ veto 硬否决。返回是否成功加入。
        """
        cands = self._joinable_conversations(i)
        if not cands:
            return False
        conv = self.rng.choice(cands)
        members = sorted(conv["members"])
        size = len(members)
        if not self._desire_join(i, members):
            return False
        veto = self.thresholds_lookup.get("chat_hostility_veto", 50.0)
        welcomed, rejected = [], []
        hard_veto = None
        for m in members:
            if self.H[m][i] >= veto:
                hard_veto = m
                break
            if self.rng.random() < self._welcome_probability(m, i, size):
                welcomed.append(m)
            else:
                rejected.append(m)
        if hard_veto is not None:
            self.stats["join_vetoes"] = self.stats.get("join_vetoes", 0) + 1
            self._log_join(i, members, "veto", welcomed, rejected, hard_veto)
            return False
        if len(welcomed) <= len(rejected):
            self._log_join(i, members, "rejected", welcomed, rejected, None)
            return False
        self._add_member_to_conversation(i, conv)
        self._log_join(i, members, "joined", welcomed, rejected, None)
        return True

    def _log_join(self, i, members, stage, welcomed, rejected, veto):
        """只读观察：记录一次加入尝试的判定（谁欢迎、谁拒绝、原因），供表现层 / 验收使用。"""
        self.join_log.append(dict(
            tick=self.global_tick, joiner=i, members=list(members),
            stage=stage, welcomed=list(welcomed), rejected=list(rejected), veto=veto))

    def _add_member_to_conversation(self, k, conv):
        """k 成功加入：加入者作为本次「发起」方，对每位现有成员做一次定向聊天结算。"""
        conv["members"].add(k)
        self.conv_of[k] = conv
        self.in_conversation[k] = True
        self._occupy_chat(k)
        for m in sorted(conv["members"]):
            if m != k:
                self._settle_chat_pair(k, m)
        self.stats["chat_joins"] = self.stats.get("chat_joins", 0) + 1
        self.stats["chat_max_size"] = max(self.stats.get("chat_max_size", 0), len(conv["members"]))

    def _leave_conversation(self, m, conv):
        """m 离开会话（自然到期或解散）。"""
        conv["members"].discard(m)
        self.conv_of[m] = None
        self.in_conversation[m] = False
        self.current_act[m] = None
        self.busy_act[m] = None
        self.stats["chat_leaves"] = self.stats.get("chat_leaves", 0) + 1

    def settle_conversations(self):
        """逐人离场（规格 G）：每人独立计时，到期即离场；成员 < 2 则会话解散。"""
        for conv in list(self.conversations):
            for m in list(conv["members"]):
                if self.busy_until[m] <= self.global_tick:
                    self._leave_conversation(m, conv)
            if len(conv["members"]) < 2:
                for m in list(conv["members"]):
                    self._leave_conversation(m, conv)
                self.conversations.remove(conv)

    def _interrupt_conversations(self):
        """铃响打断（规格 A/G）：结束所有未完成会话；仍在聊的人付中断代价。"""
        cost = self.probs.get("interrupted_stress", 0.0)
        for conv in list(self.conversations):
            for m in list(conv["members"]):
                if self.busy_until[m] > self.global_tick and cost > 0:
                    self.Stress[m] = clamp100(self.Stress[m] + cost)
                    self.stats["interrupts"] = self.stats.get("interrupts", 0) + 1
                self.conv_of[m] = None
                self.in_conversation[m] = False
                self.current_act[m] = None
                self.busy_act[m] = None
                self.busy_until[m] = 0
            self.conversations.remove(conv)

    @invitation_behavior("roughhouse")
    def do_roughhouse(self, i, j):
        """【追逐打闹】（§10.18）—— 参与者互相好感↑（A 类效果）。

        一起闹的人越来越亲近 —— 这是「小团体自发抱团」的机理之一。
        （老师版去四维门槛与旁观者敌对，只保留参与者好感。）
        """
        self.occupy(i, j, "roughhouse")
        self.apply_event(i, j, "roughhouse_affinity")
        self.apply_event(j, i, "roughhouse_affinity")
        self.stats["roughhouse"] += 1

    def set_seat_zones(self, positions):
        """表现层注入座位站位世界坐标：index -> (x, z)。参考只读。"""
        self.seat_world = dict(positions)

    def in_own_seat(self, i):
        """是否在自己的座位范围内（§8.23）；未注入时保守返回 True。"""
        if i not in self.seat_world:
            return True
        seat = self.seat_world[i]
        # 范围 = 自己那张桌椅的占位矩形（x, z, w, h）
        x, z, w, h = seat
        return x <= self.pos_x[i] <= x + w and z <= self.pos_z[i] <= z + h

    def do_study(self, i):
        """学习（§8.23）：进入学习态。学习是**占用态**（2026-10-14 修）——
        置 busy_until 覆盖本段剩余时间，把「学习中」衔接进 can_interact_with ↔ busy_until，
        否则会被聊天／搭话强行拉走（聊天机制规格 A 验收点）。不设 busy_phase，故不计「被打断」。
        """
        self.current_act[i] = "study"
        remaining = self.day_phases[self.phase_index][1] - self.tick_in_phase
        self.busy_until[i] = self.global_tick + remaining
        self.stats["studies"] = self.stats.get("studies", 0) + 1

    def do_sleep(self, i):
        """睡觉（§8.8）：玩家主动入睡（参考实现）。与 NPC 同规则：
        占用剩余课间段、段末一次性减压、期间不被任何人交互。
        """
        self.sleeping[i] = True
        self.current_act[i] = "sleep"
        self.stats["sleeps"] += 1


    def update_environment(self):
        """环境层：由「当前大家在做什么」推出目标音量，再平滑趋近。

        `target = clamp(Σ noise(各人当前行为), 0, max)` —— **量的累积产生质变**：
        2 人聊天 noise=12×2=24（正常）；8 人聊天 96（**吵到别人**）。
        超阈部分才转化为压力。
        """
        e = self.env
        target = 0.0
        for i in range(self.N):
            # 行为结束后回到"默认（学习，不发声）"——否则 current_act 会永久残留，
            # 全员被当成"一直在聊天"，音量恒满。
            if self.global_tick >= self.busy_until[i] and self.current_act[i] != "study":
                self.current_act[i] = None
            # None = 既没在做事、也没在发声（静默参与者或空闲）→ 不贡献音量
            act = self.current_act[i]
            if act is None:
                continue
            target += self.behaviors.get(act, {}).get("noise", 0.0)
        if self.teacher.present:
            target *= self.teacher.params["volume_target_mult"]
        target = clamp(target, 0.0, e.get("volume_max", 100.0))
        rate = e.get("adapt_rate", 0.02)
        self.volume = clamp(self.volume + rate * (target - self.volume), 0.0, e.get("volume_max", 100.0))

    def tag_bias(self, i, effect_key):
        """标签对行为倾向的加成（`data/rules/tags.csv`，按作用轴分类、分 weak/strong 两级）。

        **标签是"对底层轴的调制"，不是身份** —— 所以「学霸」不是规则，
        而是这组倾向条件涌现出来的称呼。这里只做**倾向加成**：
        weak ≈ +0.10、strong ≈ +0.50（对应表里的 `effect` 列）。
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

    `phases.csv` 用 `stress_drip` 描述上课段允许的规则；
        这里把它翻译成"行为白名单"——**上课时禁用的行为** = 一切主动社交。
        """
        if behavior in LEISURE_KINDS or behavior == "leave_class":
            return self.phase == "break"
        if not hasattr(self, "phase_rules"):
            return True
        pid = self.phase_order[self.phase_index] if 0 <= self.phase_index < len(self.phase_order) else None
        rules = self.phase_rules.get(pid, ["all"])
        if "all" in rules:
            return True
        banned = {"chat", "roughhouse", "move"}
        return behavior not in banned

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
        loud = ("chat", "roughhouse")
        for i in range(self.N):
            if not self.is_present(i):
                continue
            act = self.current_act[i] or "study"
            if act in loud and v < 0.4:
                self.Stress[i] = clamp100(self.Stress[i] + k * (0.4 - v) * 10.0)
            elif act == "study" and v > 0.72:
                # 阈值取 0.72 而非 0.6：否则"音量略高于阈"就惩罚全部学习者，
                # 而 study 是默认行为 → 等于给全班加压力（实测会把爆发从 20 推到 70+）
                self.Stress[i] = clamp100(self.Stress[i] + k * (v - 0.72) * 10.0)

    # ------------------------------------------------ 主循环
    def stress_drip(self):
        self.deviance_pressure()   # 环境层：偏离氛围 → 压力（不是禁止，是代价）
        """涓流：独处恢复 / 学习累积（主文档 §8.4）"""
        for i in range(self.N):
            if not self.is_present(i):
                continue
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
        """跨相位中断（统一边界协议 ③）：**尚未完成**的占用即被打断。

        只做「判定 + 打断代价」，**不再**内含到期结算（到期动作由 ① `settle_finished_actions`
        处理），也不再依赖 `phase_index` 是否已切换到新段 —— 边界协议里本方法先于
        `switch_phase`（⑥）执行，此刻 `phase_index` 仍指向旧段。

        ⚠️ 只有**尚未完成**的行为才算被打断（内核策划符合性审查 P1-04）：
        `busy_until <= global_tick` 说明它早就做完了（已由 ① 清理占用），此处只剩
        `busy_until > global_tick` 的未完成占用。
        返回被打断节点下标，供 `cleanup_phase`（④）清理残余状态。
        """
        cost = self.probs.get("interrupted_stress", 0.0)
        interrupted = []
        for i in range(self.N):
            if self.busy_phase[i] < 0:
                continue
            if self.busy_until[i] > self.global_tick:
                self.busy_until[i] = 0
                self.busy_phase[i] = -1
                action_cost = self.leisure["interrupted_stress"] if self.busy_act[i] in LEISURE_KINDS else cost
                if action_cost > 0:
                    self.Stress[i] = clamp100(self.Stress[i] + action_cost)
                self.stats["interrupts"] = self.stats.get("interrupts", 0) + 1
                interrupted.append(i)
        return interrupted

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
            if self.busy_act[i] in LEISURE_KINDS:
                prefix = LEISURE_KINDS[self.busy_act[i]]
                self.Stress[i] = clamp100(self.Stress[i] - self.leisure[prefix + "_relief"])
            self.current_act[i] = None
            self.busy_act[i] = None
            self.busy_phase[i] = -1

    def tick(self):
        self.global_tick += 1
        self.settle_finished_actions()
        self.settle_conversations()      # 多人聊天：逐人离场 / 解散（2026-10-14）
        self.teacher.step(self)
        self.decide_and_act()
        self.study_accumulate()
        self.update_environment()
        if self.global_tick % int(self.p["settle_interval"]) == 0:   # 每天 2 次（上午/下午）
            self.stress_drip()
        # 压力爆发已在每日结算时按概率判定（见 try_burst），此处不再做阈值相变

    def study_accumulate(self):
        """成绩涓流（§17.1.2）：每 tick 处于「学习状态」（默认空闲 = 无行为且不忙碌）时累积
        study_acc，满档 +1 分。上课段不累积；跨天保留（settle_day 不清 study_acc）。不消耗 RNG。
        """
        if self.phase != "break":
            return
        gmax = self.kp["grade_max"]
        for i in range(self.N):
            if not self.is_present(i):
                continue
            if self.Grade[i] >= gmax:
                self.StudyAcc[i] = 0.0
                continue
            # §8.23：学习是**主动行为** —— 玩家与 NPC 都必须处于学习态才累积成绩
            if self.current_act[i] != "study":
                continue
            self.StudyAcc[i] += 1.0
            self._fold_study_acc(i)

    def _fold_study_acc(self, i):
        """把已经灌进 StudyAcc 的时长折成分数。与 SimCore._fold_study_acc 对齐。"""
        gmax = self.kp["grade_max"]
        while self.Grade[i] < gmax:
            tpp = self._grade_ticks_per_point(self.Grade[i])
            if tpp <= 0.0 or self.StudyAcc[i] < tpp:
                return
            self.StudyAcc[i] -= tpp
            self.Grade[i] += 1.0
            self.apply_event(i, i, "study_stress")

    def _init_exam(self):
        rows = load_table("rules/exam.csv")
        self.exam_days = sorted(int(float(r["value"])) for r in rows if r["param"].startswith("exam_day_"))
        by_key = {r["param"]: float(r["value"]) for r in rows if not r["param"].startswith("exam_day_")}
        self.exam_sigma = by_key.get("exam_noise_sigma", 12.0)
        self.exam_penalty = by_key.get("stress_exam_penalty", 15.0)
        self.exam_progress_delta = by_key.get("progress_prize_delta", 50.0)
        self.exam_top_rank = int(by_key.get("top_prize_rank", 3))
        self.exam_top_tokens = int(by_key.get("top_prize_tokens", 1))
        runtime = {r["key"]: float(r["value"]) for r in load_table("rules/time_runtime.csv")}
        self.exam_term_days = int(runtime.get("term_days", 30))
        self.exam_last = list(self.Grade)
        self.exam_tokens = [0] * self.N
        self.exam_rank = [0] * self.N
        self.exam_score = [0.0] * self.N

    def settle_exam(self, day):
        """周考 / 期末考。不改 Grade，不消耗 self.rng。非考试日直接返回。"""
        final = day == self.exam_term_days
        if not final and day not in self.exam_days:
            return False
        index = self._exam_index(day)
        scores = [
            self._exam_score(self.Grade[i], self.Stress[i], index, i) for i in range(self.N)
        ]
        order = sorted(range(self.N), key=lambda i: (-scores[i], i))
        for place, i in enumerate(order):
            self.exam_rank[i] = place + 1
        player = self.N - 1
        delta = scores[player] - self.exam_last[player]
        if self.exam_rank[player] <= self.exam_top_rank:
            self.exam_tokens[player] += self.exam_top_tokens
        self.exam_score = scores
        self.exam_last = list(scores)
        self.exam_gave_progress = (not final) and delta >= self.exam_progress_delta
        return True

    def _exam_index(self, day):
        all_days = sorted(self.exam_days + [self.exam_term_days])
        return all_days.index(day) + 1

    def _exam_score(self, grade, stress, exam_index, node):
        z = exam_quantized_normal(self.seed, exam_index, node)
        raw = grade + exam_rint(self.exam_sigma * z - self.exam_penalty * stress / 100.0)
        return clamp(raw, 0.0, self.kp["grade_max"])

    def _grade_ticks_per_point(self, g):
        """当前成绩档的「每 +1 分所需 tick」（§17.1.2 分段表）；越界返回 0。"""
        for upper, ticks in self.grade_bands:
            if g < upper:
                return ticks
        return 0.0

    def cleanup_phase(self, interrupted):
        """统一边界协议 ④：清理被打断动作的残余状态（旧段占用）。

        不消耗 RNG。被打断节点的 `busy_until`/`busy_phase` 已由 ③ 清掉，这里清掉仍残留的
        `current_act`/`busy_act`/`in_conversation`，让新段判定看到一致的空闲状态。
        """
        self._interrupt_conversations()   # 铃响打断所有未结束会话（2026-10-14 多人聊天）
        for i in range(self.N):
            if self.current_act[i] == "study":
                self.current_act[i] = None
                self.StudyAcc[i] = 0.0
        for i in interrupted:
            self.current_act[i] = None
            self.busy_act[i] = None
            self.in_conversation[i] = False
        if self.player_absent:
            self.player_absent = False
            self.busy_until[self.N - 1] = 0
            self.current_act[self.N - 1] = None
        self.leave_count = 0

    def end_phase(self):
        """统一边界协议 ②③④⑤：结束旧段（不推进 tick）。

        顺序固定：到期结算 → 睡眠收尾 → 中断 → 清理 →（日末）跨天结算。
        核心 RNG 只由 `settle_day → try_burst` 消耗一次，其余步骤无核心 RNG。
        """
        self.settle_finished_actions()
        if self.phase == "class":
            self.class_affinity_settle()
        self.settle_sleep()
        interrupted = self.check_interrupt()
        self.cleanup_phase(interrupted)
        if self.phase_index + 1 >= len(self.day_phases):
            self.settle_day()

    def begin_phase(self):
        """统一边界协议 ⑦：进入当前段（`phase_index` 已指向本段）并执行新段判定。

        核心 RNG 消费序：roll_sleep。
        """
        self.phase = self.day_phases[self.phase_index][0]
        self.tick_in_phase = 0
        self.teacher.begin_phase(self)
        self.roll_sleep()                 # 本段开始掷一次睡觉（段粒度，非 tick）

    def run_day(self):
        total_ticks = 0
        for _ in range(len(self.day_phases)):
            self.begin_phase()                      # ⑥⑦ 进入本段 + 新段判定
            _phase, ticks = self.day_phases[self.phase_index]
            for _ in range(ticks):
                self.tick()
                self.tick_in_phase += 1
                total_ticks += 1
            self.vol_log.append(round(self.volume, 1))   # 相位末采样
            self.end_phase()                        # ②③④⑤ 结束本段（末段触发跨天结算）
            self.phase_index = (self.phase_index + 1) % len(self.day_phases)
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
            self.stats["bursts"] += 1

    def settle_day(self):
        """跨天结算（§3.5）"""
        self.try_burst()                      # 每日一次：压力爆发按概率判定
        d = self.decay

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
                self.H[i][j] *= d["decay_h"]
            self.Stress[i] *= d["retain_s"]
        self.day_events.clear()          # 新的一天，重置「有互动」判定
        self.settle_exam(self.day)
        self.day += 1

    # ------------------------------------------------ 报告
    def report(self):
        n = self.N
        pairs = [(i, j) for i in range(n) for j in range(n) if i != j]
        aff = [self.A[i][j] for i, j in pairs]
        aff.sort()
        mean = sum(aff) / len(aff)
        saturated = sum(1 for v in aff if v >= 95) / len(aff)
        print("=== 内核运行统计（seed=%d, 天数=%d, 节点=%d）===" % (self.seed, self.day - 1, self.N))
        print("  好感：min %.1f / 中位 %.1f / 均值 %.1f / max %.1f" % (aff[0], aff[len(aff) // 2], mean, aff[-1]))
        print("  接近饱和(>=95)比例：%.1f%%" % (saturated * 100))
        print("  事件 %d 次（闲聊 %d / 搭话 %d / 打闹 %d）" % (
            self.stats["events"], self.stats["chats"], self.stats["joins"], self.stats.get("roughhouse", 0)))
        print(
            "  睡着 %d 人次 | 被打断 %d"
            % (
                self.stats.get("sleeps", 0),
                self.stats.get("interrupts", 0),
            )
        )
        print("  去重跳过 %d 次" % self.stats["dedup_skips"])
        print("  压力爆发 %d 次（平均每 %.1f 天一次）" % (
            self.stats["bursts"],
            (self.day - 1) / max(1, self.stats["bursts"])))


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
    """观察层：**只读**、**每个角色一份视角**的标签器。

    老师版删除透明度/信任后，关系矩阵对所有人可见（`visibility` 恒为 clear）：
    标签器直接读真实 A/H。规格来源：主文档 §9.3 / §11；阈值复用系统已有阈值
    （亲近 A≥60、敌对 H≥40），**不另定**。
    """

    def __init__(self, sim):
        self.s = sim

    # ---------- ① 可见性档位（老师版：无透明度，恒 clear）----------
    def visibility(self, viewer, target):
        """返回 'clear'（老师版删除透明度，关系对所有人可见）。"""
        return "clear"

    # ---------- ② 该 viewer 能看见的关系矩阵 ----------
    def seen_matrix(self, viewer, axis="affinity"):
        """返回 viewer 眼中的 axis 关系矩阵（老师版：直接读真值）。"""
        n = self.s.N
        src = {"affinity": self.s.A, "hostility": self.s.H}[axis]
        out = [[None] * n for _ in range(n)]
        for k in range(n):
            for m in range(n):
                if k == m:
                    continue
                out[k][m] = src[k][m]
        return out

    # ---------- ③ 簇标签（每个角色一份视角）----------
    def cluster_tags(self, viewer):
        """viewer 眼中的小团体：按 §11.1 的强连接阈值 A≥60 取连通分量（≥3 人成簇）。"""
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
