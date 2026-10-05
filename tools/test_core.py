"""内核与文档一致性测试

用途：断言 tools/core_sim.py 的实现与 docs/design/ 里的公式一致，并检查关键不变式。
运行：python tools/test_core.py

覆盖：
  · 手算例：性格倍率 / 关系调制 / 软饱和 / round(0.1)
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
check("话题共鸣增量 = +3.1（含性格 ×1.2、软饱和与 round）", abs(delta - 3.1) < 0.011, delta)
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
print("  通过 %d 项，失败 %d 项" % (len(PASSED), len(FAILED)))
if FAILED:
    print("  失败清单：", FAILED)
sys.exit(1 if FAILED else 0)
