"""公式对拍验证（实现 vs 文档）

对拍目标：确认 `tools/core_sim.py` 的实现真的按 `docs/design/统一影响公式.md` 的公式运行，
而不是"看起来差不多"。用**独立重算**与实现结果逐项比对。

覆盖：事件链（E 与写入，含压力轴）与跨天衰减链。

运行：python tools/verify_formula.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim, clamp, r1  # noqa: E402

FAIL = []
PASSED = []


def check(name, actual, expect, tol=0.06):
    ok = abs(actual - expect) <= tol
    print("  %s %-44s 实现=%7.3f 独立=%7.3f" % ("✓" if ok else "✗", name, actual, expect))
    (PASSED if ok else FAIL).append(name)
    return ok


# ============================================================ 1. 事件链
print("=== 1. 事件链：Δ = round( round( sat( base · M(i,j), U ), 0.1 ) · room_for, 0.1 ) ===")
sim = Sim(seed=1, npc_count=4)


def independent_event(base, A, H, U, axis="affinity", target_val=None, fb=0.0):
    """独立重算 apply_event 的写入值（老师版：无四维倍率，无 tier 关系调制豁免）。

    · A/H 轴：e_val = base × M(i,j)，M = clamp((A−H)/50, −1, 1)；
    · 压力轴（§6.1 只管 A/H）：e_val = base，不乘 M；
    · 软饱和后 round(0.1)；负反馈（§2.5.3）仅正向轴在写入点乘 (1 − fb·X/100)。
    · 测试统一置 stress=0 → m_state=1.0（避开压力区间系数）。
    """
    e = base
    if axis in ("affinity", "hostility"):
        e *= clamp((A - H) / 50.0, -1.0, 1.0)
    delta = r1(e / (1.0 + abs(e) / U))            # sat + round(0.1)
    if axis in ("affinity", "hostility"):
        if fb > 0 and axis == "affinity" and target_val is not None:
            delta = r1(max(0.0, 1.0 - fb * target_val / 100.0) * delta)
    return delta


for eid, A, H in [("topic_affinity", 60.0, 0.0),        # 正向好感 + 负反馈
                  ("reject_affinity", 30.0, 45.0),      # 负 base（M 反转）好感
                  ("reject_hostility", 20.0, 70.0),     # 敌对轴（无负反馈）
                  ("roughhouse_affinity", 60.0, 0.0),   # 正向好感
                  ("study_stress", 60.0, 0.0)]:         # 压力轴（不走 M / 负反馈）
    row = next(r for r in sim.event_rows if r["event_id"] == eid)
    axis = row["axis"]
    U = {"affinity": 25.0, "hostility": 25.0, "stress": 30.0}[axis]
    is_stress = axis == "stress"
    sim.A[0][1], sim.H[0][1] = A, H
    sim.Stress[0] = 0.0
    sim.settled.clear()
    tgt = sim.Stress if is_stress else {"affinity": sim.A, "hostility": sim.H}[axis]
    before = tgt[0] if is_stress else tgt[0][1]
    sim.apply_event(0, 1, eid)
    actual = round((tgt[0] if is_stress else tgt[0][1]) - before, 3)
    expect = independent_event(float(row["base"]), A, H, U, axis=axis,
                               target_val=before, fb=sim.feedback)
    check("%s (base=%s)" % (eid, row["base"]), actual, expect)

# ============================================================ 2. 衰减链
print("\n=== 2. 跨天衰减链（§3.5）===")
# 期望值一律从 data/rules/decay.csv 读，避免"改了参数忘了改测试"。
# 本场景无事件结算 → 走「无互动」档 decay_a_no_interact；压力取 60（低于爆发入口 70，
# 避免 try_burst 概率分支改动压力）。
sim3 = Sim(seed=3, npc_count=3)
sim3.A[0][1], sim3.H[0][1], sim3.Stress[0] = 60.0, 40.0, 60.0
d3 = dict(sim3.decay)
sim3.settle_day()
check("好感(无互动) ×%.2f" % d3["decay_a_no_interact"], sim3.A[0][1],
      round(60.0 * d3["decay_a_no_interact"], 3))
check("敌对 ×%.2f" % d3["decay_h"], sim3.H[0][1], round(40.0 * d3["decay_h"], 3))
check("压力 ×%.2f" % d3["retain_s"], sim3.Stress[0], round(60.0 * d3["retain_s"], 3))

# 附：验证「有互动」档生效（当天该对子有事件结算 → 用 decay_a_interact）
sim3b = Sim(seed=3, npc_count=3)
sim3b.A[0][1] = 60.0
sim3b.day_events[(0, 1)] = 1                      # 模拟当天发生过一次事件结算
sim3b.settle_day()
check("好感(有互动) ×%.2f" % sim3b.decay["decay_a_interact"], sim3b.A[0][1],
      round(60.0 * sim3b.decay["decay_a_interact"], 3))

# ============================================================ 3. 报告诊断
print("\n=== 3. 诊断：无事件对子的好感轨迹 ===")
sim4 = Sim(seed=12345, npc_count=16)
i, j = 0, 1
trace = [sim4.A[i][j]]
stress_cap = []
for _ in range(3):
    sim4.run_day()
    trace.append(sim4.A[i][j])
    stress_cap.append(max(sim4.Stress))
print("  A[0][1] 轨迹：", " → ".join("%.1f" % v for v in trace))
print("  每日压力峰值：", " / ".join("%.1f" % s for s in stress_cap))
print("  该对子当期真实 A/H：%.1f / %.1f" % (sim4.A[i][j], sim4.H[i][j]))

print("\n=== 结论 ===")
print("  通过 %d 项，失败 %d 项 %s" % (len(PASSED), len(FAIL), FAIL if FAIL else ""))
sys.exit(1 if FAIL else 0)
