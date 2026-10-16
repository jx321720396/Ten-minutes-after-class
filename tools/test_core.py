"""内核与文档一致性测试（含负反馈 `feedback` 的口径）

用途：断言 tools/core_sim.py 的实现与 docs/design/ 里的公式一致，并检查关键不变式。
运行：python tools/test_core.py

覆盖：
  · 手算例：关系调制 / 软饱和 / round(0.1)
  · 事件写入链路、负反馈、事件去重
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
sim2.A[0][1], sim2.H[0][1] = 60.0, 0.0           # M = clamp(60/50) = 1.0（留出加法空间）
sim2.Stress[0] = 0.0
before = sim2.A[0][1]
sim2.apply_event(0, 1, "topic_affinity")         # base=3（老师版无四维倍率）
delta = round(sim2.A[0][1] - before, 2)
# 期望链：3 × M(1.0) = 3.0 → sat(3.0, U=25) = 3.0/1.12 = 2.679 → round(0.1) = 2.7
#         → × 负反馈 room = 1 − 1.0×60/100 = 0.4 → 2.7×0.4 = 1.08 → round = 1.1
check("话题共鸣增量 = +1.1（软饱和、负反馈与 round，无性格倍率）", abs(delta - 1.1) < 0.011, delta)

# 负反馈专项：同一事件在低好感目标上增量更大（越满越难涨）
sim_nf = Sim(seed=11, npc_count=4)
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

print("\n=== 4. 不变式 ===")
sim3 = Sim(seed=99, npc_count=6)
sim3.run_day()
n = sim3.N
in_range = all(0.0 <= sim3.A[i][j] <= 100.0 and 0.0 <= sim3.H[i][j] <= 100.0
               for i in range(n) for j in range(n))
check("A/H 落在 [0, 100]", in_range)
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

# 静态扫描：决策路径不得读真实值 A[j][i]（别人对我的态度；§18.7 不变式 3）
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "core_sim.py"), encoding="utf-8").read()
decide_body = src.split("def decide_and_act")[1].split("def pick_target")[0]
# 非法模式：读了"别人对我的态度"（第一个下标为别人、第二个下标为 i）
illegal = re.findall(r"self\.(A|H)\[j\]\[i\]", decide_body)
check("决策函数内未读 A[j][i]（别人对我的态度）", len(illegal) == 0, illegal)

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
check("随机睡觉对所有学生生效", sim_player.sleeping[0] and all(sim_player.sleeping))
print("=== 6. 周考 ===")
exam = Sim(seed=99, npc_count=8)
for i in range(exam.N):
    exam.Grade[i] = 100.0
exam.Grade[0] = 400.0
exam.Stress = [0.0] * exam.N
exam.exam_last = [0.0] * exam.N
check("非考试日不结算", exam.settle_exam(6) is False)
grade_snapshot = list(exam.Grade)
check("周考不改平时成绩", exam.settle_exam(8) is True and exam.Grade == grade_snapshot)
check("周考按考分排名（最高分第一）", exam.exam_rank[0] == 1)
check("同分按节点号破平", exam.exam_rank[1] == 2)
# D05：第八天考试的目标均分 380 与达标判定。
check("D05：目标均分为 380", exam.exam_target_mean == 380.0)
check("D05：考试日结算后记录班级均分", exam.exam_means.get(8, -1.0) > 0.0)
check("D05：达标判定按均分与目标比较",
      exam.exam_passed.get(8) == (exam.exam_means.get(8, 0.0) >= exam.exam_target_mean))
check("D05：第七天是考前日、第八天是考试日",
      exam.is_exam_eve(7) is True and exam.is_exam_day(8) is True)
check("D05：考试当天只有考试", exam.exam_only_day == 1)
exam.settle_exam(30)
check("期末考也不改平时成绩", exam.Grade == grade_snapshot)


print("=== 6b. D07 伤害与关系修复（《老师版规则合并稿》）===")
harm = Sim(seed=12345, npc_count=8)
harm.phase = "break"
harm.harm["trigger_p"] = 1.0
harm.harm["shove_choice_p"] = 1.0
harm.neighbor_idx[0] = [1]
harm.neighbor_idx[1] = [0]
harm.H[0][1] = 40.0
harm.begin_harm_phase()
harm.check_harm()
check("D07：恰好 40 不触发恶语攻击", len(harm.harm_events) == 0)
harm.H[0][1] = 41.0
stress_before = harm.Stress[1]
hostility_before = harm.H[1][0]
harm.begin_harm_phase()
harm.check_harm()
check("D07：>40 触发恶语攻击",
      len(harm.harm_events) == 1 and harm.harm_events[0]["kind"] == "aggression")
check("D07：恶语使目标压力 +5", abs(harm.Stress[1] - (stress_before + 5.0)) < 1e-6)
check("D07：恶语使目标对发起者敌对 +3", abs(harm.H[1][0] - (hostility_before + 3.0)) < 1e-6)
harm.H[0][1] = 71.0
harm.begin_harm_phase()
harm.check_harm()
check("D07：>70 归为推搡", harm.harm_events[0]["kind"] == "shove")
harm.phase_state[0] = "study"
harm.begin_harm_phase()
harm.check_harm()
check("D07：学习锁定的学生不参与伤害", len(harm.harm_events) == 0)
harm.phase_state[0] = "free"
harm.phase = "class"
harm.begin_harm_phase()
harm.check_harm()
check("D07：上课段不发生伤害（课间接触才判）", len(harm.harm_events) == 0)

chat = Sim(seed=12345, npc_count=8)
chat.start_conversation(0, 1)
chat.H[0][1] = 30.0
chat.H[1][0] = 30.0
chat.busy_act[0] = "chat"
chat.busy_phase[0] = 0
chat.busy_until[0] = 0
chat.settle_finished_actions()
check("D07：完成聊天后对子双方敌对各 −2",
      abs(chat.H[0][1] - 28.0) < 1e-6 and abs(chat.H[1][0] - 28.0) < 1e-6)

print("=== 6c. D06 风险判定与退学 ===")
risk = Sim(seed=12345, npc_count=8)
for k in range(3):
    risk.H[k][5] = 60.0
risk.note_harm(0, 5, "aggression")
risk.settle_risk(2)
check("D06：满足霸凌条件第一天只预警（不触发、不辞退）",
      risk.risk_warned[5] and not risk.risk_triggered[5] and not risk.dropped[5])
for k in range(3):
    risk.H[k][5] = 60.0
risk.note_harm(0, 5, "aggression")
risk.settle_risk(2)
check("D06：连续第二天正式触发霸凌", risk.risk_triggered[5])
risk.register_breakdown(5)
risk.settle_risk(4)
check("D06：正式触发风险后再崩溃一次 → 退学",
      risk.dropped[5] and risk.class_failed())

four = Sim(seed=12345, npc_count=8)
for _k in range(4):
    four.register_breakdown(3)
four.settle_risk(3)
check("D06：累计崩溃超过 3 次（第 4 次）→ 退学", four.dropped[3])
three = Sim(seed=12345, npc_count=8)
for _k in range(3):
    three.register_breakdown(7)
three.settle_risk(3)
check("D06：恰好 3 次崩溃不退学", not three.dropped[7])
iso = Sim(seed=12345, npc_count=8)
for j in range(8):
    if j != 5:
        iso.A[j][5] = 10.0
for _k in range(2):
    iso.register_join_reject(5)
iso.settle_risk(2)
check("D06：好感低 + 当天被拒 2 次 + 没参加活动 → 孤立预警", iso.risk_warned[5])

print("=== 6d. 崩溃休息与心结（§5.3）===")
rest = Sim(seed=12345, npc_count=8)
rest.begin_phase_state()
rest.Stress[0] = 95.0
rest.Vitality[0] = 60.0
rest.check_breakdown()
check("崩溃休息：当天只睡觉", rest.Broken[0] and rest.sleeping[0])
check("崩溃休息：不参与结算（unit_kind 为空）", rest.unit_kind(0) == "")
rest.Stress[0] = 10.0
rest.check_breakdown()
check("旧「压力 <70 即时恢复」出口已废止", rest.Broken[0])
rest.Stress[0] = 60.0
rest.Vitality[0] = 60.0
rest.resting[0] = True
rest.knot_days[0] = 0
for _j in rest.neighbor_idx[0]:
    rest.knot_days[_j] = 0
rest.day = 6
rest.settle_day()
check("崩溃次日压力 −50（替代普通 −20）", abs(rest.Stress[0] - 10.0) < 1e-6)
check("崩溃次日动力 −50（替代普通 −10，且不联动）", abs(rest.Vitality[0] - 10.0) < 1e-6)
check("崩溃休息在次日跨天时解除", not rest.Broken[0])

knot = Sim(seed=12345, npc_count=8)
knot.begin_phase_state()
knot.neighbor_idx[0] = [1]
knot.Stress[0] = 95.0
knot.check_breakdown()
check("心结：崩溃者本人获得 3 天", knot.knot_days[0] == 3)
check("心结：正交邻座同样获得", knot.knot_days[1] == 3)
check("心结：不遍及非邻座（不传染）", knot.knot_days[2] == 0)
knot.knot_days[0] = 1
knot.Broken[0] = False
knot.Stress[0] = 96.0
knot.check_breakdown()
check("心结：重复获得只刷新为 3 天，不叠层", knot.knot_days[0] == 3)

knot_day = Sim(seed=12345, npc_count=8)
knot_day.knot_days[0] = 3
for _d in range(3):
    knot_day.day = 6
    knot_day.Stress[0] = 30.0
    knot_day.Vitality[0] = 30.0
    knot_day.settle_day()
check("心结：连续 3 天后结束", knot_day.knot_days[0] == 0)
check("心结每天压力净 −10（跨天 −20 后 +10）", abs(knot_day.Stress[0] - 20.0) < 1e-6)
check("心结动力按一般规则同步 +10", abs(knot_day.Vitality[0] - 30.0) < 1e-6)

print("=== 6e. 辞退原因（§11.4）===")
fail = Sim(seed=12345, npc_count=8)
for _k in range(4):
    fail.register_breakdown(3)
fail.settle_risk(3)
check("触发退学判据后有失败原因", fail.failure_reason() != "")
check("失败原因说明是退学", "退学" in fail.failure_reason())
clean = Sim(seed=12345, npc_count=8)
check("未触发判据时没有失败原因", clean.failure_reason() == "")
exam_fail = Sim(seed=12345, npc_count=8)
exam_fail.exam_means[8] = 300.0
exam_fail.exam_passed[8] = False
check("考核不达标的原因含判据、实际均分与目标均分",
      "首次考核不达标" in exam_fail.failure_reason()
      and "300" in exam_fail.failure_reason()
      and "380" in exam_fail.failure_reason())

print("=== 7. 持续学习回归（《老师版规则合并稿》D02：每 20 秒 +1 学业收益、−5 动力）===")
study = Sim(seed=12345, npc_count=8)
me = 0
study.Grade[me] = 100.0
study.phase_state[me] = "study"
gain_before = study.GainToday[me]
vitality_before = study.Vitality[me]
study.do_study(me)
for _ in range(20):
    study.settle_units()
    study.update_environment()
check("学习不会被过期占用清理", study.current_act[me] == "study")
check("学习每 20 秒记 1 点学业收益", study.GainToday[me] == gain_before + 1.0)
check("学习每 20 秒扣 5 点动力", abs(study.Vitality[me] - (vitality_before - 5.0)) < 1e-9)
check("成绩当天不变（D02：跨天才并入成绩）", study.Grade[me] == 100.0)
study.cleanup_phase([])
check("铃声退出学习且当天成绩不变", study.current_act[me] is None and study.Grade[me] == 100.0)

print("=== 8. 通用加入（§9.1.4：找伴 / 确定 / 跟随 / 加入 / 带朋友）===")
join_sim = Sim(seed=20261015, npc_count=8)

# —— 8.1 找伴：最高有向好感优先；正在活动也可以被邀请 ——
for i in range(join_sim.N):
    for j in range(join_sim.N):
        join_sim.A[i][j] = 20.0
        join_sim.H[i][j] = 0.0
join_sim.A[0][3] = 80.0
check("找伴：选自己好感最高的人", join_sim._find_partner(0, "chat") == 3)
join_sim.A[0][3] = 20.0
join_sim.A[0][5] = 80.0
join_sim.A[0][7] = 80.0  # 与 5 并列 → 取最低节点号（join_tie_break = 0）
check("找伴：好感并列取最低节点号（可复现）", join_sim._find_partner(0, "chat") == 5)
# 正在学习的人可被邀请（§9.1.4：正在活动也可以被邀请）
study_sim = Sim(seed=20261015, npc_count=8)
for i in range(study_sim.N):
    for j in range(study_sim.N):
        study_sim.A[i][j] = 20.0
        study_sim.H[i][j] = 0.0
for k in range(study_sim.N):
    if k != 2:
        study_sim.sleeping[k] = True   # 只留 2 号醒着（正在学习）
study_sim.do_study(2)
study_sim.A[0][2] = 60.0
check("找伴：正在学习的人可被邀请", study_sim._find_partner(0, "chat") == 2)
check("找伴：睡觉的人不可被邀请（条件不满足）", study_sim._find_partner(0, "chat") != 1)

# —— 8.2 接受：好感−敌对 ≥ 10 投同意；严格过半；平票拒绝 ——
vote_sim = Sim(seed=20261015, npc_count=8)
vote_sim.A[1][0] = 25.0
vote_sim.H[1][0] = 15.0   # 25 − 15 = 10，恰好等于门槛 → 同意
ok, yes, no = vote_sim._vote_accept([1], 0)
check("投票：好感−敌对恰好 10 投同意", ok and yes == [1])
vote_sim.H[1][0] = 15.5   # 9.5 < 10 → 拒绝
ok, yes, no = vote_sim._vote_accept([1], 0)
check("投票：好感−敌对低于 10 投拒绝", not ok)
vote_sim.A[1][0], vote_sim.H[1][0] = 50.0, 0.0
vote_sim.A[2][0], vote_sim.H[2][0] = 0.0, 0.0
ok, yes, no = vote_sim._vote_accept([1, 2], 0)   # 1 同意 1 拒绝 → 平票拒绝
check("投票：两人团体平票拒绝", not ok and yes == [1] and no == [2])
vote_sim.A[3][0], vote_sim.H[3][0] = 50.0, 0.0
ok, yes, no = vote_sim._vote_accept([1, 2, 3], 0)  # 三人两票同意 → 通过
check("投票：三人团体至少两票同意才接受", ok and len(yes) == 2)

# —— 8.3 同活动合流：申请加入既有会话（全体成员投票） ——
conv_sim = Sim(seed=20261015, npc_count=8)
for i in range(conv_sim.N):
    for j in range(conv_sim.N):
        conv_sim.A[i][j] = 20.0
        conv_sim.H[i][j] = 0.0
conv_sim.A[1][0] = 60.0   # 成员 1 欢迎加入者 0
conv_sim.A[2][0] = 60.0   # 成员 2 欢迎加入者 0
conv_sim.do_chat(1, 2)    # 1 与 2 成会
check("合流前会话为两人", len(conv_sim.conversations) == 1 and conv_sim.conversations[0]["members"] == {1, 2})
conv_sim._propose_activity(0, 1, "chat")
check("同活动合流：申请加入既有会话成功", conv_sim.conv_of[0] is conv_sim.conversations[0])
check("同活动合流：不另开重复活动", len(conv_sim.conversations) == 1)
# 拒绝路径：成员对加入者好感不足 → 关系拒绝，不占用发起者
conv_sim2 = Sim(seed=20261015, npc_count=8)
for i in range(conv_sim2.N):
    for j in range(conv_sim2.N):
        conv_sim2.A[i][j] = 20.0
        conv_sim2.H[i][j] = 0.0
conv_sim2.A[1][0] = 5.0    # 两位成员都对加入者不足门槛 → 关系拒绝
conv_sim2.A[2][0] = 5.0
conv_sim2.do_chat(1, 2)
conv_sim2._propose_activity(0, 1, "chat")
check("合流被拒：关系拒绝不占用发起者", conv_sim2.conv_of[0] is None)
check("合流被拒：日志记 vote_reject", conv_sim2.join_log[-1]["stage"] == "vote_reject")

# —— 8.4 不同活动跟随：好感更高的一方跟随另一方；相等不合流 ——
follow_sim = Sim(seed=20261015, npc_count=8)
for i in range(follow_sim.N):
    for j in range(follow_sim.N):
        follow_sim.A[i][j] = 20.0
        follow_sim.H[i][j] = 0.0
for k in range(follow_sim.N):
    if k not in (0, 1):
        follow_sim.sleeping[k] = True
follow_sim.do_study(1)             # 1 在学习
follow_sim.StudyAcc[1] = 3.5       # 已有学业收益
follow_sim.A[1][0] = 70.0          # 1 更在意 0 → 1 跟随 0 的闲聊
follow_sim.A[0][1] = 30.0
follow_sim._propose_activity(0, 1, "chat")
check("跟随：更在意对方的人放弃原活动跟随（1 → 闲聊）",
      follow_sim.conv_of[1] is not None and follow_sim.current_act[1] == "chat")
check("跟随：活动切换不清空既有学业收益", abs(follow_sim.StudyAcc[1] - 3.5) < 1e-9)
follow_sim2 = Sim(seed=20261015, npc_count=8)
for i in range(follow_sim2.N):
    for j in range(follow_sim2.N):
        follow_sim2.A[i][j] = 20.0
        follow_sim2.H[i][j] = 0.0
for k in range(follow_sim2.N):
    if k not in (0, 1):
        follow_sim2.sleeping[k] = True
follow_sim2.do_study(1)
follow_sim2.A[0][1] = 70.0          # 0 更在意 1 → 0 加入 1 的学习
follow_sim2.A[1][0] = 30.0
follow_sim2._propose_activity(0, 1, "chat")
check("跟随：发起者更在意对方时加入对方活动（0 → 一起学习）",
      follow_sim2.current_act[0] == "study" and follow_sim2.study_of[0] is follow_sim2.study_of[1])
follow_sim3 = Sim(seed=20261015, npc_count=8)
for i in range(follow_sim3.N):
    for j in range(follow_sim3.N):
        follow_sim3.A[i][j] = 20.0
        follow_sim3.H[i][j] = 0.0
for k in range(follow_sim3.N):
    if k not in (0, 1):
        follow_sim3.sleeping[k] = True
follow_sim3.do_study(1)
follow_sim3.A[0][1] = 42.0
follow_sim3.A[1][0] = 42.0          # 相等 → 不合流
follow_sim3._propose_activity(0, 1, "chat")
check("跟随：两个方向好感相等各自保持活动（不合流）",
      follow_sim3.conv_of[0] is None and follow_sim3.current_act[1] == "study")
check("跟随：日志记 tie_no_merge", follow_sim3.join_log[-1]["stage"] == "tie_no_merge")

# —— 8.5 零食分享：加入者无需自带；完成单位后对分享者好感 ↑（去重） ——
snack_sim = Sim(seed=20261015, npc_count=8)
for i in range(snack_sim.N):
    for j in range(snack_sim.N):
        snack_sim.A[i][j] = 20.0
        snack_sim.H[i][j] = 0.0
for k in range(snack_sim.N):
    if k not in (0, 1):
        snack_sim.sleeping[k] = True
snack_sim.start_leisure(1, "eat_snack")   # 1 独自吃零食
snack_sim.A[0][1] = 70.0                  # 0 更在意 1 → 0 加入 1 的零食分享
snack_sim.A[1][0] = 30.0
snack_sim._propose_activity(0, 1, "chat")
check("零食分享：加入者并入分享活动（无需自带零食）",
      snack_sim.snack_of[0] is snack_sim.snack_of[1] and snack_sim.busy_act[0] == "eat_snack")
snack_sim.A[0][1] = 20.0                  # 重置，看事件带来的增量
before_share = snack_sim.A[0][1]
snack_sim.busy_until[0] = snack_sim.global_tick   # 让 0 的进食单位到期
snack_sim.settle_finished_actions()
check("零食分享：完成单位后对分享者好感 ↑", snack_sim.A[0][1] > before_share)
check("零食分享：分享单位计数去重（每对子记 1 次）", snack_sim.share_units.get((1, 0)) == 1)

# —— 8.6 带朋友：成员邀请朋友，仍走全体成员投票；A 拒 C 则不成 ——
friend_sim = Sim(seed=20261015, npc_count=8)
for i in range(friend_sim.N):
    for j in range(friend_sim.N):
        friend_sim.A[i][j] = 20.0
        friend_sim.H[i][j] = 0.0
for k in range(friend_sim.N):
    if k not in (0, 1, 2, 3):
        friend_sim.sleeping[k] = True
friend_sim.A[1][0] = 60.0
friend_sim.A[2][0] = 60.0
friend_sim.do_chat(1, 2)            # A=1, B=2 成会
friend_sim.A[2][3] = 75.0           # B(2) 最想带 C(3)
friend_sim.A[1][3] = 60.0           # A(1) 也同意 C
friend_sim.A[3][1] = 20.0
friend_sim.A[3][2] = 20.0
friend_sim.probs["invite_friend_p"] = 1.0   # 邀请必然尝试
friend_sim._invite_friends_pass()
check("带朋友：B 带 C 加入原会话（全体投票通过）", 3 in friend_sim.conversations[0]["members"])
check("带朋友：不另开重复活动", len(friend_sim.conversations) == 1)
# A 拒 C：A 对 C 好感不足 → C 进不来
friend_sim2 = Sim(seed=20261015, npc_count=8)
for i in range(friend_sim2.N):
    for j in range(friend_sim2.N):
        friend_sim2.A[i][j] = 20.0
        friend_sim2.H[i][j] = 0.0
for k in range(friend_sim2.N):
    if k not in (1, 2, 3):
        friend_sim2.sleeping[k] = True   # 只留 A、B、C 在场，避免第四人连环邀请放行
friend_sim2.do_chat(1, 2)
friend_sim2.A[2][3] = 75.0
friend_sim2.A[1][3] = 5.0            # A 拒 C（5 − 0 < 10）
friend_sim2.probs["invite_friend_p"] = 1.0
friend_sim2._invite_friends_pass()
check("带朋友：A 拒 C 时 C 不能加入（邀请者不能替别人保证接纳）",
      3 not in friend_sim2.conversations[0]["members"])
check("带朋友：被拒不占用被邀请者", friend_sim2.busy_until[3] == 0)

# —— 8.7 满员与同刻竞争 ——
cap_sim = Sim(seed=20261015, npc_count=8)
for i in range(cap_sim.N):
    for j in range(cap_sim.N):
        cap_sim.A[i][j] = 80.0
        cap_sim.H[i][j] = 0.0
for k in range(cap_sim.N):
    if k > 4:
        cap_sim.sleeping[k] = True
cap_sim.do_chat(1, 2)
cap_sim._apply_join_group(3, 1, "chat", cap_sim.conversations[0])   # 3 人
ok4 = cap_sim._apply_join_group(4, 1, "chat", cap_sim.conversations[0])  # 4 人（= max_members）
check("满员：人数上限内可加入（4 人）", ok4 and len(cap_sim.conversations[0]["members"]) == 4)
check("满员：超过上限属条件不满足（不算关系拒绝）",
      cap_sim._apply_join_group(0, 1, "chat", cap_sim.conversations[0]) is False
      and cap_sim.join_log[-1]["stage"] == "condition_fail")

# —— 8.8 新加入者本决策点不能带朋友；每人每决策点最多一次邀请 ——
cd_sim = Sim(seed=20261015, npc_count=8)
for i in range(cd_sim.N):
    for j in range(cd_sim.N):
        cd_sim.A[i][j] = 60.0
        cd_sim.H[i][j] = 0.0
for k in range(cd_sim.N):
    if k not in (0, 1, 2, 3):
        cd_sim.sleeping[k] = True
cd_sim.do_chat(1, 2)
cd_sim.global_tick = 5
cd_sim._apply_join_group(3, 1, "chat", cd_sim.conversations[0])
check("冷却：本决策点新加入者（joined_tick = 当前 tick）暂不能带朋友", cd_sim.joined_tick[3] == 5)
cd_sim.A[2][0] = 90.0
cd_sim.probs["invite_friend_p"] = 1.0
cd_sim._invite_friends_pass()
check("冷却：老成员（2 号）仍可带 0 号入会", 0 in cd_sim.conversations[0]["members"])

# —— 8.9 同种子复现（新路径全量运行） ——
sim_a = Sim(seed=777, npc_count=16)
sim_b = Sim(seed=777, npc_count=16)
for _ in range(2):
    sim_a.run_day()
    sim_b.run_day()
check("通用加入：同种子同结果（可复现）", sim_a.stats == sim_b.stats and sim_a.A == sim_b.A)

print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
if FAILED:
    print("  失败清单：", FAILED)
sys.exit(1 if FAILED else 0)
