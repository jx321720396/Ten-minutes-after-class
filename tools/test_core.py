"""内核与文档一致性测试（含负反馈 `feedback` 的口径）

用途：断言 tools/core_sim.py 的实现与 docs/design/ 里的公式一致，并检查关键不变式。
运行：python tools/test_core.py

覆盖：
  · 手算例：性格倍率 / 关系调制 / 软饱和 / round(0.1)
  · 事件写入链路、负反馈、事件去重
  · **重大敌对的「作用对象」**（举报 / 当众羞辱的方向与 hurt_day）—— 门只对拍数值，
    方向写反不会被拦住，故单列断言（见 §3.5 / §3.6）
  · 不变式：决策禁读 A[j][i]、同种子同结果、数值范围、tau > 0
  · 一次小规模运行的分布输出（供人眼检查）
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim, clamp, r1, softmax  # noqa: E402

PASSED = []
FAILED = []


def check(name, cond, detail=""):
    (PASSED if cond else FAILED).append(name)
    print("  %s %s%s" % ("✓" if cond else "✗", name, ("  ← " + str(detail)) if (detail is not None and not cond) else ""))


print("=== 1. 手算例（与文档数值对照）===")
sim = Sim(seed=1, npc_count=4)
sim.dims[0] = [85.0, 50.0, 50.0, 50.0]          # E=85 → d_E = 0.7
row = {"w_e": 0.2, "w_s": 0, "w_f": 0, "w_j": 0}
check("性格倍率 (E=85, w_E=+0.2) = 1.14", abs(sim.mult_personality(row, 0) - 1.14) < 0.005,
      sim.mult_personality(row, 0))

sim.dims[0] = [0.0, 50.0, 50.0, 50.0]            # E=0 → d_E = -1，倍率 0.8（仍在区间内）
check("性格倍率受 w 削弱但不下钳（0.8）", abs(sim.mult_personality(row, 0) - 0.8) < 1e-9)
row_all_neg = {"w_e": -1.0, "w_s": -1.0, "w_f": -1.0, "w_j": -1.0}
sim.dims[0] = [100.0, 100.0, 100.0, 100.0]       # 1 + (-4) = -3 → 钳到下限
check("性格倍率下限 0.1 生效", sim.mult_personality(row_all_neg, 0) == 0.1)
sim.dims[0] = [100.0, 50.0, 50.0, 50.0]          # E=100 → 1 + 0.2 = 1.2
check("性格倍率上限 1.2 生效", abs(sim.mult_personality(row, 0) - 1.2) < 1e-9)

sim.A[0][1], sim.H[0][1] = 65.0, 0.0
check("关系调制 M(65, 0) = +1.0", abs(sim.m_relation(0, 1) - 1.0) < 1e-9)
sim.A[0][1], sim.H[0][1] = 30.0, 45.0
check("关系调制 M(30, 45) = −0.3（敌对压过好感 → 反转）", abs(sim.m_relation(0, 1) + 0.3) < 1e-9)
sim.A[0][1], sim.H[0][1] = 100.0, 0.0
check("关系调制上限 +1.0", abs(sim.m_relation(0, 1) - 1.0) < 1e-9)

check("软饱和 sat(5.7, U_A=25) ≈ 4.64", abs(sim.sat(5.7, "affinity") - 4.64) < 0.01, sim.sat(5.7, "affinity"))
check("软饱和小量近似直通 sat(0.5) ≈ 0.49", abs(sim.sat(0.5, "affinity") - 0.49) < 0.02, sim.sat(0.5, "affinity"))

check("round(0.75) = 0.8", r1(0.75) == 0.8)
check("round(1.175) = 1.2", r1(1.175) == 1.2)
check("round(0.04) = 0.0（过小增量被舍去）", r1(0.04) == 0.0)

print("\n=== 2. 事件写入链路（话题共鸣 · 好感）===")
sim2 = Sim(seed=7, npc_count=4)
sim2.dims[0] = [100.0, 50.0, 50.0, 50.0]         # E=100 → 倍率 1.2
sim2.A[0][1], sim2.H[0][1] = 60.0, 0.0           # M = clamp(60/50) = 1.0（留出加法空间）
before = sim2.A[0][1]
sim2.apply_event(0, 1, "topic_affinity")         # base=3, w_e=0.2, w_s=0.2
delta = round(sim2.A[0][1] - before, 2)
# 期望链：3 × clamp(1+0.2×1.0+0.2×0, 0.1, 1.2) = 3 × 1.2 = 3.6
#         → × M(1.0) = 3.6 → sat(3.6, U=25) = 3.6/1.144 = 3.146 → round(0.1) = 3.1
#         → × 负反馈 room = 1 − 1.0×60/100 = 0.4 → 3.1×0.4 = 1.24 → round = 1.2
check("话题共鸣增量 = +1.2（含性格 ×1.2、软饱和、负反馈与 round）", abs(delta - 1.2) < 0.011, delta)

# 负反馈专项：同一事件在低好感目标上增量更大（越满越难涨）
sim_nf = Sim(seed=11, npc_count=4)
sim_nf.dims[0] = [100.0, 50.0, 50.0, 50.0]
sim_nf.H[0][1], sim_nf.Stress[0] = 0.0, 0.0
sim_nf.A[0][1] = 20.0
sim_nf.settled.clear()
b1 = sim_nf.A[0][1]
sim_nf.apply_event(0, 1, "topic_affinity")
d_low = round(sim_nf.A[0][1] - b1, 3)
sim_nf.A[0][1] = 90.0
sim_nf.settled.clear()
b2 = sim_nf.A[0][1]
sim_nf.apply_event(0, 1, "topic_affinity")
d_high = round(sim_nf.A[0][1] - b2, 3)
check("负反馈生效：A=20 增量(%.2f) 应大于 A=90 增量(%.2f)" % (d_low, d_high), d_low > d_high)
check("负反馈生效：A=90 时增量被压到极小（%.2f < 0.6）" % d_high, d_high < 0.6)
check("增量是 0.1 的整数倍", abs(delta * 10 - round(delta * 10)) < 1e-9, delta)

print("\n=== 3. 事件去重（同一对子同一规则每课间段只结算一次）===")
before2 = sim2.A[0][1]
ok = sim2.apply_event(0, 1, "topic_affinity")    # 第二次，同一天同一相位 → 应被跳过
check("重复事件返回 False 且不改数值", ok is False and sim2.A[0][1] == before2)

print("\n=== 3.5 举报的作用对象（方向回归，§10.2 / §10.22 / §10.25）===")
# 断言的是「效果落在谁身上」，不是「数值算得对不对」。
# 起因（2026-10-07）：report_stress / report_hostility 曾写成 apply_event(i, j)，
# 于是被举报者压力恒为 0、深层敌对记到了举报者一侧 —— 而四道门全部照常通过。
NEG_HURT = -10 ** 9
sim_rep = Sim(seed=5, npc_count=4)
reporter, target = 0, 2                                  # i = 举报者，j = 被举报者
sim_rep.dims[target] = [50.0, 50.0, 50.0, 50.0]           # 四维中性 → M_personality = 1.0
sim_rep.Stress[reporter] = sim_rep.Stress[target] = 0.0   # 避开 M_state 区间系数
sim_rep.A[reporter][target], sim_rep.H[reporter][target] = 0.0, 90.0
sim_rep.hurt_day[reporter][target] = sim_rep.hurt_day[target][reporter] = NEG_HURT
sim_rep.settled.clear()
s_rep_before, s_tgt_before = sim_rep.Stress[reporter], sim_rep.Stress[target]
h_ij_before, h_ji_before = sim_rep.H[reporter][target], sim_rep.H[target][reporter]
sim_rep.do_report(reporter, target)

check("举报：被举报者压力上升（major +5 档 → 实得 4.3）",
      abs((sim_rep.Stress[target] - s_tgt_before) - 4.3) < 0.06,
      sim_rep.Stress[target] - s_tgt_before)
check("举报：举报者不承担这份压力（§18.9 的口径）",
      sim_rep.Stress[reporter] == s_rep_before,
      sim_rep.Stress[reporter] - s_rep_before)
check("举报：敌对与深层都记在「被举报者 → 举报者」",
      abs((sim_rep.H[target][reporter] - h_ji_before) - 4.2) < 0.06
      and abs(sim_rep.H_deep[target][reporter] - 4.2) < 0.06
      and sim_rep.H_deep[reporter][target] == 0.0)
check("举报：举报者对被举报者的敌对回落 −5（§10.2 第 3 条）",
      abs(sim_rep.H[reporter][target] - (h_ij_before - 5.0)) < 1e-9,
      sim_rep.H[reporter][target] - h_ij_before)
check("举报：hurt_day 记施害者视角（举报者 → 被举报者），且不污染反向条目",
      sim_rep.hurt_day[reporter][target] == sim_rep.day
      and sim_rep.hurt_day[target][reporter] == NEG_HURT)

print("\n=== 3.6 当众羞辱的 hurt_day（同一根因的另一条链）===")
sim_hum = Sim(seed=5, npc_count=6)
attacker, victim = 0, 2
sim_hum.A[attacker][victim], sim_hum.H[attacker][victim] = 10.0, 50.0   # 落嘲讽档
sim_hum.hurt_day[attacker][victim] = sim_hum.hurt_day[victim][attacker] = NEG_HURT
sim_hum.settled.clear()
sim_hum.do_tease(attacker, victim, [3, 4, 5, 6])                        # 围观 4 人（= 共同邻居几何上界）→ 升级为羞辱
check("羞辱：hurt_day 记施害者视角（发起者 → 被调侃者），且不污染反向条目",
      sim_hum.hurt_day[attacker][victim] == sim_hum.day
      and sim_hum.hurt_day[victim][attacker] == NEG_HURT)

print("\n=== 3.7 主动接近类行为的方向（安慰 / 求助 / 道歉，2026-10-07 新增）===")
# 只断言「效果落在谁身上、方向对不对」，不比对数值 ——
# 方向写反（安慰扣了自己好感 / 道歉反而加深心结）**不会让任何一道门变红**，
# 所以与 §3.5 / §3.6 同类，必须单列断言。

sim_cf = Sim(seed=13, npc_count=6)
helper, sad = 0, 2
sim_cf.dims[helper] = sim_cf.dims[sad] = [50.0, 50.0, 50.0, 50.0]   # 中性 → M_personality = 1.0
sim_cf.Stress[helper], sim_cf.Stress[sad] = 0.0, 75.0               # 发起者不高压、目标在高压区
sim_cf.A[helper][sad] = 60.0
sim_cf.settled.clear()
s_hlp, s_sad = sim_cf.Stress[helper], sim_cf.Stress[sad]
a_sad2hlp, t_sad2hlp, a_hlp2sad = sim_cf.A[sad][helper], sim_cf.T[sad][helper], sim_cf.A[helper][sad]
sim_cf.do_comfort(helper, sad)
check("安慰：目标压力下降", sim_cf.Stress[sad] < s_sad, "%s → %s" % (s_sad, sim_cf.Stress[sad]))
check("安慰：目标对安慰者 好感↑ / 信任↑",
      sim_cf.A[sad][helper] > a_sad2hlp and sim_cf.T[sad][helper] > t_sad2hlp)
check("安慰：发起者付出压力成本（不论结果）", sim_cf.Stress[helper] > s_hlp)
check("安慰：发起者自身对目标的好感不变（不是双向增益）", sim_cf.A[helper][sad] == a_hlp2sad)

sim_hp = Sim(seed=17, npc_count=6)
asker, hlp2 = 1, 3
sim_hp.dims[asker] = sim_hp.dims[hlp2] = [50.0, 50.0, 50.0, 50.0]
sim_hp.Stress[asker] = 0.0
sim_hp.A[asker][hlp2], sim_hp.H[asker][hlp2] = 40.0, 0.0
sim_hp.A[hlp2][asker], sim_hp.H[hlp2][asker] = 30.0, 0.0   # 判定读真值 → M > 0，正向效果不被反转
sim_hp.settled.clear()
_orig_random = sim_hp.rng.random
sim_hp.rng.random = lambda: 0.999                          # 强制走「被拒」分支
st_a, h_a, t_a = sim_hp.Stress[asker], sim_hp.H[asker][hlp2], sim_hp.T[asker][hlp2]
sim_hp.do_ask_help(asker, hlp2)
check("求助被拒：求助者 压力↑ / 敌对↑ / 信任↓",
      sim_hp.Stress[asker] > st_a and sim_hp.H[asker][hlp2] > h_a and sim_hp.T[asker][hlp2] < t_a)
sim_hp.settled.clear()
sim_hp.rng.random = lambda: 0.0                            # 强制走「成功」分支
a_h2a, t_h2a = sim_hp.A[hlp2][asker], sim_hp.T[hlp2][asker]
sim_hp.do_ask_help(asker, hlp2)
check("求助成功：帮忙者对求助者 好感↑ / 信任↑",
      sim_hp.A[hlp2][asker] > a_h2a and sim_hp.T[hlp2][asker] > t_h2a)
sim_hp.rng.random = _orig_random

# 道歉：构造「敌对压过好感」的处境（M < 0）—— 这既是道歉成立的前提，
# 也正是关系调制会把「修复」翻成「恶化」的地方（故 do_apologize 走 no_modulation）。
sim_ap = Sim(seed=19, npc_count=6)
a1, a2 = 0, 4
sim_ap.dims[a1] = sim_ap.dims[a2] = [50.0, 50.0, 50.0, 50.0]
sim_ap.Stress[a1] = sim_ap.Stress[a2] = 0.0
sim_ap.A[a1][a2] = sim_ap.A[a2][a1] = 20.0
sim_ap.H[a1][a2] = sim_ap.H[a2][a1] = 40.0
sim_ap.H_deep[a1][a2] = sim_ap.H_deep[a2][a1] = 25.0
sim_ap.settled.clear()
deep_before = sim_ap.H_deep[a1][a2]
_orig_random = sim_ap.rng.random
sim_ap.rng.random = lambda: 0.0                            # 强制「接受」
sim_ap.do_apologize(a1, a2)
check("道歉被接受：双向敌对下降（M < 0 时也不被翻成上升）",
      sim_ap.H[a1][a2] < 40.0 and sim_ap.H[a2][a1] < 40.0,
      "%s / %s" % (sim_ap.H[a1][a2], sim_ap.H[a2][a1]))
check("道歉被接受：只消表层敌对，心结 H_deep 纹丝不动（§10.22）",
      sim_ap.H_deep[a1][a2] == deep_before and sim_ap.H_deep[a2][a1] == deep_before,
      "%s / %s" % (sim_ap.H_deep[a1][a2], sim_ap.H_deep[a2][a1]))
check("道歉被接受：双向好感回升", sim_ap.A[a1][a2] > 20.0 and sim_ap.A[a2][a1] > 20.0)
sim_ap.rng.random = _orig_random

print("\n=== 4. 不变式 ===")
sim3 = Sim(seed=99, npc_count=6)
sim3.run_day()
n = sim3.N
in_range = all(0.0 <= sim3.A[i][j] <= 100.0 and 0.0 <= sim3.H[i][j] <= 100.0
               and 0.0 <= sim3.T[i][j] <= 100.0 for i in range(n) for j in range(n))
check("所有轴落在 [0, 100]", in_range)
check("压力落在 [0, 100]", all(0.0 <= s <= 100.0 for s in sim3.Stress))

sim4 = Sim(seed=99, npc_count=6)
sim4.run_day()
same = (sim3.stats == sim4.stats and sim3.A == sim4.A)
check("同种子同结果（可复现）", same)

try:
    softmax([1.0, 2.0], 0.0, sim3.rng)
    check("tau = 0 应报错", False)
except ValueError:
    check("tau = 0 抛错（温度必须 > 0）", True)

try:
    softmax([1.0, 2.0], -1.0, sim3.rng)
    check("tau < 0 应报错", False)
except ValueError:
    check("tau < 0 抛错", True)

# 静态扫描：决策路径不得读真实值 A[j][i]（信念矩阵 §9 不变式 1）
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "core_sim.py"), encoding="utf-8").read()
decide_body = src.split("def decide_and_act")[1].split("def pick_target")[0]
# 非法模式：读了"别人对我的态度"（第一个下标为别人、第二个下标为 i）
illegal = re.findall(r"self\.(A|H|T)\[j\]\[i\]", decide_body)
# 合法模式：读"我自己的立场"（self.X[i][j]）与信念（self.B[...]）
legal_own = re.findall(r"self\.(A|H|T)\[i\]\[j\]", decide_body)
check("决策函数内未读 A[j][i]（别人对我的态度）", len(illegal) == 0, illegal)
check("决策确实读了信念 B（而非真值）", "self.B[" in decide_body)

print("\n=== 5. 一次小规模运行（3 天）===")
sim5 = Sim(seed=12345, npc_count=16)
for _ in range(3):
    sim5.run_day()
sim5.report()
print("  压力：max %.1f / 均值 %.1f" % (max(sim5.Stress), sum(sim5.Stress) / sim5.N))

print("\n=== 结论 ===")
sim_player = Sim(seed=12345, npc_count=16)
sim_player.sleeping = [False] * sim_player.N
sim_player.busy_until = [0] * sim_player.N
sim_player.probs["sleep"] = 100.0
sim_player.roll_sleep()
check("随机睡觉只决定 NPC，不替玩家选择", not sim_player.sleeping[-1])
check("随机睡觉仍允许 NPC 睡觉", sim_player.sleeping[0])
sim_player.sleeping = [False] * sim_player.N
sim_player.busy_until = [0] * sim_player.N
sim_player.current_act = [None] * sim_player.N
sim_player.current_act[-1] = "player_choice"
sim_player.neighbor_idx[-1] = [0]
sim_player.current_act[0] = "study"
sim_player.behaviors["study"]["join_mode"] = "free"
sim_player.probs["free_join_rate"] = 100.0
sim_player.free_join()
check("自由跟随不替玩家选择活动", sim_player.current_act[-1] == "player_choice")
sim_invite = Sim(seed=12345, npc_count=16)
sim_invite.do_chat(0, sim_invite.N - 1)
pending = sim_invite.get_player_invitation()
check("NPC 找玩家聊天先邀请，不占用玩家", bool(pending) and sim_invite.busy_until[-1] == 0)
sim_invite.respond_player_invitation(pending["id"], False)
check("玩家拒绝聊天后仍自由", sim_invite.busy_until[-1] == 0 and sim_invite.stats["chats"] == 0)
sim_help = Sim(seed=12345, npc_count=16)
sim_help.A[-1][0] = 0.0
sim_help.dims[-1][0] = 0.0
sim_help.do_ask_help(0, sim_help.N - 1)
pending = sim_help.get_player_invitation()
sim_help.respond_player_invitation(pending["id"], True)
check("玩家接受求助不掷愿意帮忙的骰子", sim_help.stats["helps"] == 1 and sim_help.busy_until[-1] > 0)
sim_help.respond_player_invitation(pending["id"], False)
check("邀请重复回应只结算一次", sim_help.stats["helps"] == 1)
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
if FAILED:
    print("  失败清单：", FAILED)
sys.exit(1 if FAILED else 0)
