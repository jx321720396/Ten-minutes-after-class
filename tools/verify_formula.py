"""公式对拍验证（实现 vs 文档）

对拍目标：确认 `tools/core_sim.py` 的实现真的按 `docs/design/统一影响公式.md` 的公式运行，
而不是"看起来差不多"。按 UIF §8 的建议 dump `(i, k, X, E, C, P, Δ)` 的思路，
用**独立重算**与实现结果逐项比对。

覆盖：事件链（E 与写入）、传导链（C 与写入）、跨天衰减链、以及报告 ④ 的轨迹诊断。

运行：python tools/verify_formula.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim, clamp, r1  # noqa: E402

FAIL = []


def check(name, actual, expect, tol=0.06):
    ok = abs(actual - expect) <= tol
    print("  %s %-44s 实现=%7.3f 独立=%7.3f" % ("✓" if ok else "✗", name, actual, expect))
    if not ok:
        FAIL.append(name)
    return ok


# ============================================================ 1. 事件链
print("=== 1. 事件链：Δ = round( sat( base · M_personality · M(i,j), U ), 0.1 ) ===")
sim = Sim(seed=1, npc_count=4)
sim.dims[0] = [100.0, 40.0, 80.0, 60.0]          # E=100 S=40 F=80 J=60
sim.Stress[0] = 0.0                               # 避开 M_state 歧义（压力区间系数）


def independent_event(base, w, dims, A, H, U, axis="affinity", target_val=None, fb=0.0):
    d = [(dims[k] - 50.0) / 50.0 for k in range(4)]
    mp = clamp(1.0 + sum(w[k] * d[k] for k in range(4)), 0.1, 1.2)
    m = clamp((A - H) / 50.0, -1.0, 1.0)
    e = base * mp * m
    delta = r1(e / (1.0 + abs(e) / U))
    # 负反馈：正向轴在写入点乘 (1 − fb·X/100)；负面轴不适用
    if fb > 0 and axis not in ("hostility", "stress") and target_val is not None:
        delta = r1(max(0.0, 1.0 - fb * target_val / 100.0) * delta)
    return delta, mp, m


for eid, A, H, U in [("topic_affinity", 60.0, 0.0, 25.0),
                     ("topic_trust", 60.0, 0.0, 20.0),
                     ("tease_hostility", 30.0, 45.0, 25.0)]:
    row = next(r for r in sim.event_rows if r["event_id"] == eid)
    axis = row["axis"]
    sim.A[0][1], sim.H[0][1] = A, H
    sim.settled.clear()
    tgt = {"affinity": sim.A, "hostility": sim.H, "trust": sim.T}[axis]
    before = tgt[0][1]
    sim.apply_event(0, 1, eid)
    actual = round(tgt[0][1] - before, 3)
    w = [float(row["w_e"]), float(row["w_s"]), float(row["w_f"]), float(row["w_j"])]
    expect, mp, m = independent_event(float(row["base"]), w, sim.dims[0], A, H, U,
                                      axis=axis, target_val=before, fb=sim.feedback)
    check("%s (base=%s, M_p=%.2f, M=%.2f)" % (eid, row["base"], mp, m), actual, expect)

# ============================================================ 2. 传导链
print("\n=== 2. 传导链：C 竞争归一化 → Δ = round( sat( β·C, U ), 0.1 ) ===")
sim2 = Sim(seed=7, npc_count=5)
# 先清空全部矩阵，避免未显式设置的随机初值混入竞争归一化
# （这曾让"独立算"与实现对不上：N=6 时 j=5 也在 for 循环里参与）
for a in range(sim2.N):
    for b in range(sim2.N):
        sim2.A[a][b] = sim2.H[a][b] = sim2.T[a][b] = 0.0
    sim2.O[a] = 100.0                             # 全透明，排除感知噪声干扰
sim2.A[0][2] = sim2.A[0][3] = 80.0                # i=0 只听从 2、3
sim2.A[2][1] = sim2.A[3][1] = 70.0                # 第三方对 k=1 的态度
sim2.H[2][1] = sim2.H[3][1] = 0.0
sim2.T[2][1] = sim2.T[3][1] = 60.0

th_a, th_h = sim2.p["theta_a"], sim2.p["theta_h"]
beta_a, eps, u_a = sim2.p["beta_a"], sim2.p["epsilon"], sim2.p["u_a"]
ws, num_a, num_h = [], 0.0, 0.0
for j in (2, 3):
    w = sim2.A[0][j] / 100.0
    ws.append(w)
    num_a += w * max(0.0, sim2.A[j][1] - th_a)
    num_h += w * max(0.0, sim2.H[j][1] - th_h)
denom = sum(ws) + eps
net = (num_a - num_h) / denom
c_val = beta_a * net
expect_d = r1(c_val / (1.0 + abs(c_val) / u_a))
before = sim2.A[0][1]
sim2.transmission()
actual_d = round(sim2.A[0][1] - before, 3)
check("传导 Δ_A（C=%.3f, net=%.2f）" % (c_val, net), actual_d, expect_d)

# ============================================================ 3. 衰减链
print("\n=== 3. 跨天衰减链（§3.5）===")
sim3 = Sim(seed=3, npc_count=3)
sim3.A[0][1], sim3.H[0][1], sim3.T[0][1], sim3.Stress[0] = 60.0, 40.0, 50.0, 80.0
sim3.settle_day()
check("好感 ×0.95", sim3.A[0][1], 57.0)
check("敌对 ×0.90", sim3.H[0][1], 36.0)
check("信任 ×0.93", sim3.T[0][1], 46.5)
check("压力 ×0.50", sim3.Stress[0], 40.0)

# ============================================================ 4. 报告 ④ 诊断
print("\n=== 4. 诊断：无事件对子的好感轨迹（报告 ④ 的怀疑）===")
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
print("  该对子当期真实 A/H/T：%.1f / %.1f / %.1f" % (sim4.A[i][j], sim4.H[i][j], sim4.T[i][j]))
print("  该对子信念 B_A（0 眼中）：%.1f" % sim4.B["affinity"][i][j])

# 传导为什么没启动：看有多少对子越过阈值
th_a = sim4.p["theta_a"]
over = sum(1 for a in range(sim4.N) for b in range(sim4.N)
           if a != b and sim4.A[a][b] > th_a)
total = sim4.N * (sim4.N - 1)
print("  好感越过传导阈值 %.0f 的对子：%d / %d（%.0f%%）" % (th_a, over, total, 100.0 * over / total))

print("\n=== 结论 ===")
print("  通过 %d 项，失败 %d 项 %s" % (0 if FAIL else 4, len(FAIL), FAIL if FAIL else ""))
sys.exit(1 if FAIL else 0)
