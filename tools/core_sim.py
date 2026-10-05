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
                                         "noise": float(r.get("noise", 0))}
                          for r in load_table("rules/behaviors.csv")}
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
                      "roughhouse": 0}
        # 事件去重：同一对子同一规则每课间段只结算一次（统一影响公式 §2.5.4）
        self.settled = set()
        self.phase_index = 0
        self.global_tick = 0
        self.next_action = [0] * n
        self.busy_until = [0] * n        # 忙碌到何时（按行为 duration，替代统一冷却）
        self.busy_phase = [-1] * n       # 行为开始时的相位序号（用于判定「被下课铃打断」）
        # --- 环境层（班级级标量，不是第六轴，而是与个体/关系并列的第三层）---
        self.env = {r["param"]: float(r["value"]) for r in load_table("rules/environment.csv")}
        self.volume = self.env.get("init_volume", 20.0)
        self.tag_rows = {r["tag_id"]: r for r in load_table("rules/tags.csv")}
        self.current_act = [None] * n     # 当前正在做/刚做完的行为（供音量统计）
        self.in_conversation = [False] * n
        self.knot_days = [0] * n        # 「心结」剩余天数（参数来自 status_tags.csv）
        self.status_tags = {r["tag_id"]: r for r in load_table("rules/status_tags.csv")}
        self.day_events = {}            # (i,j) -> 当天事件类结算次数，用于「有互动」判定

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
    def apply_event(self, i, j, event_id):
        """按统一影响公式写入：E × 性格 × 关系调制 → 软饱和 → round(0.1) → clamp

        含事件去重：同一对子同一规则每课间段只结算一次（§2.5.4）
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
            e_val = base * self.mult_personality(row, i)
            if axis in AXES:
                # 边界②：重大档不做关系调制（M_eff = 1）
                #   否则「关系好 → 举报反而是好事」会塌掉欺凌线与信任崩塌线；
                #   也不是 max(0, M)（那样关系差时伤害归零，等于「被讨厌就不会被伤害」）
                if row.get("tier", "normal") != "major":
                    e_val *= self.m_relation(i, j)
            p_val = e_val + (0.0 if axis == "stress" else 0.0)  # 事件侧不含传导
            m = self.m_state(i, negative=(base < 0) == (axis in AXES))
            delta = r1(m * self.sat(p_val, axis)) if axis != "stress" else r1(self.sat(p_val, axis))
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

    # ------------------------------------------------ 传导（涓流）
    def transmission(self):
        """阈值 + 竞争归一化 + 感知值；每 settle_interval 结算一次"""
        n = self.N
        th = {"affinity": self.p["theta_a"], "hostility": self.p["theta_h"], "trust": self.p["theta_t"]}
        beta = {"affinity": self.p["beta_a"], "hostility": self.p["beta_h"], "trust": self.p["beta_t"]}
        true = {"affinity": self.A, "hostility": self.H, "trust": self.T}
        deltas = {ax: [[0.0] * n for _ in range(n)] for ax in AXES}

        for i in range(n):
            for k in range(n):
                if i == k:
                    continue
                w_sum = 0.0
                num = {"affinity": 0.0, "hostility": 0.0, "trust": 0.0}
                for j in range(n):
                    if j == i or j == k:
                        continue
                    w = self.A[i][j] / 100.0  # 听从度
                    if w <= 0:
                        continue
                    w_sum += w
                    for ax in AXES:
                        # σ = max(0, 感知_X(j→k) − θ)
                        perceived = self.perceive(j, k, ax)
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
            "trust": self.nw["alpha_t_base"] + self.nw["alpha_t_j"] * self.dims[i][3] / 100.0,
            "hostility": self.nw["alpha_h_base"] + self.nw["alpha_h_f"] * (1 - self.dims[i][2] / 100.0)
                         + self.nw["alpha_h_j"] * (1 - self.dims[i][3] / 100.0),
            "stress": self.nw["alpha_s_base"] + self.nw["alpha_s_e"] * (1 - self.dims[i][0] / 100.0),
        }
        total = sum(raw.values())
        return {k: v / total for k, v in raw.items()}

    def tau(self, i):
        t = self.nw["tau0"] * (1 + self.nw["tau_j"] * (1 - self.dims[i][3] / 100.0))
        if self.Stress[i] >= 70:
            t *= self.nw["tau_stress_mult"]
        return max(t, 0.01)

    def gate(self, i, behavior, j):
        """门槛（硬条件）：不通过则不进入候选集"""
        if behavior == "join_chat":
            return self.A[i][j] >= 30 and self.Stress[i] <= 80
        if behavior == "report":
            return self.H[i][j] >= 60
        if behavior == "chat":
            return True
        return False

    def decide_and_act(self):
        """一 tick 内的行为决策（简化：只挑一个行为执行）"""
        n = self.N
        order = list(range(n))
        self.rng.shuffle(order)
        busy = set()
        for i in order:
            if i in busy or self.global_tick < self.busy_until[i]:
                continue
            self.in_conversation[i] = False
            # 环境类：闲聊（概率触发）
            if self.rng.random() < self.probs["chat"]:
                j = self.pick_target(i)
                if j is not None:
                    self.do_chat(i, j)
                    busy.add(i)
                    busy.add(j)
                    continue
            # 意向类：当众调侃（需 ≥3 人围观；失败则目标受辱）
            # 目标选择**带偏好**：敌对越高 / 好感越低越容易被针对 —— 被讨厌的人会被反复打击，
            # 这正是"压力分化 → 个别爆发"的机制来源（不允许随机摊平）
            cands_t = [j for j in range(n) if j != i and j not in busy and self.A[i][j] >= 20.0]
            if len(cands_t) >= 3 and self.rng.random() < 0.18:
                wts = [max(1.0, ((100.0 - self.A[i][j]) + self.H[i][j]) ** 2) for j in cands_t]
                j = self.rng.choices(cands_t, weights=wts, k=1)[0]
                audience = [k for k in range(n) if k not in (i, j) and k not in busy]
                if len(audience) >= 3:
                    self.do_tease(i, j, audience[:3])
                    busy.add(i)
                    busy.add(j)
                    continue
            # 意向类：追逐打闹 —— 敌对种子（参与者好感↑ / 旁观者敌对↑）
            th_rh = self.thresholds_lookup.get("roughhouse_affinity", 45.0)
            th_rc = int(self.thresholds_lookup.get("roughhouse_count", 2))
            if self.dims[i][0] >= th_rh and self.rng.random() < 0.05:
                others = [j for j in range(n) if j != i and j not in busy]
                if others:
                    # 追跑对象按外向度加权：越外向越可能一起闹（→ 同样的少数人反复搭配）
                    w_rh = [max(1.0, self.dims[j][0] - 30.0) for j in others]
                    j = self.rng.choices(others, weights=w_rh, k=1)[0]
                    bys = [k for k in range(n) if k not in (i, j) and k not in busy]
                    if len(bys) >= th_rc:
                        # 旁观者聚焦「安静专注型」（高 J + 内向）—— 他们最容易被吵到，
                        # 于是「活跃分子 × 严肃分子」这一批边会被反复击中而累积，而不是被摊平
                        bys.sort(key=lambda k: -((self.dims[k][3] - 50.0) + (50.0 - self.dims[k][0])))
                        self.do_roughhouse(i, j, bys[:3])
                        busy.add(i)
                        busy.add(j)
                        continue
            # 阈值类：排挤（"大家都讨厌他" → 集体驱逐）—— B 类，让关系能无条件变差
            if self.rng.random() < 0.04:
                th_h = self.thresholds_lookup.get("exclude_hostility", 40.0)
                th_n = int(self.thresholds_lookup.get("exclude_count", 3))
                done = False
                for j in range(n):
                    if j == i or j in busy:
                        continue
                    haters = [k for k in range(n) if k != j and self.H[k][j] >= th_h]
                    if len(haters) >= th_n:
                        self.do_exclude(i, j, haters[:4])
                        busy.add(i)
                        done = True
                        break
                if done:
                    continue
            # 附加行为：流言（负面染色，压力来源）；目标同样偏好敌对高者
            if self.rng.random() < 0.03:
                c2 = [j for j in range(n) if j != i and j not in busy]
                if c2:
                    w2 = [max(1.0, 20.0 + self.H[i][j] - self.A[i][j] * 0.5) for j in c2]
                    j = self.rng.choices(c2, weights=w2, k=1)[0]
                    self.do_rumor(i, j)
                    busy.add(i)
                    busy.add(j)
                    continue
            # 阈值类：举报（敌对累积到阈值即发生）
            for j in range(n):
                if i == j or self.H[i][j] < 60:
                    continue
                if self.rng.random() < 0.05:  # 避免每 tick 都触发
                    self.do_report(i, j)
                    break
            # 意向类：搭话
            cands = [(j, self.gate(i, "join_chat", j)) for j in range(n) if j != i]
            cands = [j for j, ok in cands if ok and j not in busy]
            if cands:
                alpha = self.alpha(i)
                scores = []
                for j in cands:
                    gain_a = self.B["affinity"][i][j] / 100.0 * 3.0  # 预期收益（读信念）
                    gain_t = self.B["trust"][i][j] / 100.0 * 2.0
                    risk_h = self.B["hostility"][i][j] / 100.0 * 2.0
                    u = alpha["affinity"] * gain_a + alpha["trust"] * gain_t - alpha["hostility"] * risk_h
                    u += self.crowd_bias(i, "loud")   # 氛围项：吵则更想搭话（从众者）
                    scores.append(u)
                if scores:
                    k = softmax(scores, self.tau(i), self.rng)
                    j = cands[k]
                    self.do_join_chat(i, j)
                    busy.add(i)
                    busy.add(j)

    def pick_target(self, i):
        n = self.N
        others = [j for j in range(n) if j != i]
        if not others:
            return None
        return self.rng.choice(others)

    def occupy(self, i, j, behavior):
        """按行为耗时把双方置为忙碌（“收益越大耗时越长”，不再一律 20 tick）"""
        self.current_act[i] = behavior
        self.current_act[j] = behavior
        dur = self.behaviors.get(behavior, {}).get("duration", 0)
        if dur > 0:
            self.busy_until[i] = self.global_tick + dur
            self.busy_until[j] = self.global_tick + dur
            self.busy_phase[i] = self.phase_index
            self.busy_phase[j] = self.phase_index

    def do_chat(self, i, j):
        """闲聊：话题共鸣事件 + 双方观测"""
        self.in_conversation[i] = True
        self.in_conversation[j] = True
        self.occupy(i, j, "chat")
        self.apply_event(i, j, "topic_affinity")
        self.apply_event(i, j, "topic_trust")
        self.apply_event(i, j, "topic_stress")
        self.apply_event(j, i, "topic_affinity")
        self.apply_event(j, i, "topic_trust")
        self.observe(i, j, "affinity")
        self.observe(j, i, "affinity")
        self.stats["chats"] += 1

    def do_join_chat(self, i, j):
        """搭话：走对方回应判定（拒绝则反噬）。

        判据 = **信念** `B_A[i][j]`（i 眼中"对方对我多有好感"）+ 对方**外向度**修正；
        门槛来自 `behavior_thresholds.csv` 的 `join_chat_affinity`（默认 45，**高于** `prior_a`=40）。
        ⚠️ 早期实现用 `B_A >= 40`，而先验正好是 40 → 永远通过 → 「好感扣减」路径从不触发（§10.17）。
        """
        self.in_conversation[i] = True
        self.in_conversation[j] = True
        self.occupy(i, j, "join_chat")
        accept = self.B["affinity"][i][j] + (self.dims[j][0] - 50.0) * 0.3
        if accept >= self.thresholds_lookup["join_chat_affinity"] and self.Stress[j] <= 70:
            self.do_chat(i, j)
            self.stats["joins"] += 1
        else:
            self.apply_event(i, j, "reject_affinity")
            self.apply_event(i, j, "reject_hostility")
            self.apply_event(i, j, "reject_stress")
            self.observe(i, j, "affinity")
            self.stats["joins"] += 1
            self.stats["skipped_events"] += 1

    def do_report(self, i, j):
        self.apply_event(i, j, "report_hostility")
        self.apply_event(i, j, "report_stress")
        self.H[i][j] = clamp100(self.H[i][j] - 5.0)  # 举报后敌对回落
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
        self.apply_event(j, i, "exclude_affinity")
        for k in crowd:
            if k != i:
                self.apply_event(j, k, "exclude_affinity")
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
            act = self.current_act[i] or "study"
            target += self.behaviors.get(act, {}).get("noise", 0.0)
        target = clamp(target, 0.0, e.get("volume_max", 100.0))
        rate = e.get("adapt_rate", 0.02)
        self.volume = clamp(self.volume + rate * (target - self.volume), 0.0, e.get("volume_max", 100.0))

    def conformity(self, i):
        """从众度 ∈ [0,1]：**大部分人从众，少数人有主见**。

        · 高 F（情感型、在意氛围）→ 从众；
        · 高 J（判断型，有自己的计划）+ 高 N（直觉型，脑内自成一套）→ 反从众。
        从众者跟着环境走（吵就更想聊、静就更想学），反从众者不受环境影响 ——
        所以「安静也要聊天」「吵闹也会学习」这两种人天然存在，**不需要特例**。
        """
        f, j, n = self.dims[i][2], self.dims[i][3], self.dims[i][1]
        return clamp(0.5 + (f - 50.0) / 100.0 - (j - 50.0) / 100.0 * 0.5 - (n - 50.0) / 100.0 * 0.5,
                     0.0, 1.0)

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
            elif act == "study" and v > 0.6:
                self.Stress[i] = clamp100(self.Stress[i] + k * (v - 0.6) * 10.0)

    def noise_pressure(self):
        """超阈音量 → 压力。极慢的涓流（每次结算一次），怕吵程度由性格决定。"""
        e = self.env
        excess = max(0.0, self.volume - e.get("volume_threshold", 60.0))
        if excess <= 0:
            return
        k = e.get("stress_k", 0.0)
        fj, fe = e.get("fear_j", 0.0), e.get("fear_e", 0.0)
        for i in range(self.N):
            fear = fj * (self.dims[i][3] - 50.0) / 50.0 + fe * (50.0 - self.dims[i][0]) / 50.0
            fear = max(0.0, fear)
            self.Stress[i] = clamp100(self.Stress[i] + excess * k * fear)

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

    def check_interrupt(self):
        """跨相位中断：行为还没做完就被「下课铃 / 上课铃」打断。

        耗时机制的直接推论 —— 课间只有 100 tick，一个 60 tick 的秘密交换很容易跨越过相位边界。
        被打断者获得压力代价（`interrupted_stress`），因为「话说到一半被打断」本身就是压力源。
        这也让「长行为」有了真实的代价：不是不能做，而是**要挑时机做**。
        """
        cost = self.probs.get("interrupted_stress", 0.0)
        for i in range(self.N):
            if self.busy_phase[i] >= 0 and self.busy_phase[i] != self.phase_index:
                self.busy_until[i] = 0
                self.busy_phase[i] = -1
                if cost > 0:
                    self.Stress[i] = clamp100(self.Stress[i] + cost)
                self.stats["interrupts"] = self.stats.get("interrupts", 0) + 1

    def tick(self):
        self.global_tick += 1
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
            self.check_interrupt()            # 相位切换 → 未完成的行为被打断
            for _ in range(ticks):
                self.tick()
                self.tick_in_phase += 1
                total_ticks += 1
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
        print("  调侃 %d（过火 %d）/ 流言 %d / 排挤 %d / 打闹 %d / 被打断 %d" % (
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
