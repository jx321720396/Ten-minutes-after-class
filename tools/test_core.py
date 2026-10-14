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
check("随机睡觉只决定 NPC，不替玩家选择", not sim_player.sleeping[-1])
check("随机睡觉仍允许 NPC 睡觉", sim_player.sleeping[0])
sim_invite = Sim(seed=12345, npc_count=16)
sim_invite.do_chat(0, sim_invite.N - 1)
pending = sim_invite.get_player_invitation()
check("NPC 找玩家聊天先邀请，不占用玩家", bool(pending) and sim_invite.busy_until[-1] == 0)
sim_invite.respond_player_invitation(pending["id"], False)
check("玩家拒绝聊天后仍自由", sim_invite.busy_until[-1] == 0 and sim_invite.stats["chats"] == 0)

print("=== 6. 周考 ===")
exam = Sim(seed=99, npc_count=8)
for i in range(exam.N - 1):
    exam.Grade[i] = 100.0
exam.Grade[-1] = 400.0
exam.exam_last = [0.0] * exam.N
check("非考试日不结算", exam.settle_exam(6) is False)
grade_snapshot = list(exam.Grade)
check("周考不改平时成绩", exam.settle_exam(7) is True and exam.Grade == grade_snapshot)
check("玩家高分拿特等奖免罚卷", exam.exam_rank[-1] <= 3 and exam.exam_tokens[-1] == 1)
check("拉开 50 分以上记进步奖", exam.exam_gave_progress is True)
exam.settle_exam(30)
check("期末考不发进步奖", exam.exam_gave_progress is False)
check("期末考也不改平时成绩", exam.Grade == grade_snapshot)

print("=== 7. 持续学习回归 ===")
study = Sim(seed=12345, npc_count=8)
me = study.N - 1
before = study.Grade[me]
study.do_study(me)
for _ in range(12):
    study.study_accumulate()
    study.update_environment()
check("学习不会被过期占用清理", study.current_act[me] == "study")
check("持续学习实际增加成绩", study.Grade[me] > before)
earned = study.Grade[me]
study.cleanup_phase([])
check("铃声退出学习且保留已结算成绩", study.current_act[me] is None and study.Grade[me] == earned)
check("铃声清除未结算进度", study.StudyAcc[me] == 0.0)

print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
if FAILED:
    print("  失败清单：", FAILED)
sys.exit(1 if FAILED else 0)
