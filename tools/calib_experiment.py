"""标定实验 v2：引入负反馈后能否同时满足「均值落在朋友区间」与「低饱和」

纯调参的问题（见上一轮）：保留率高 → 全班一起封顶；保留率低 → 全班一起归零。
分布是"整体平移"而非"分化" —— 正反馈的特征。负反馈：传导增益 × (1 − feedback·A/100)。

稳态估算（keep=0.95, g=9.6, feedback=1.0）：0.05·A* = 9.6(1 − A*/100) → A* ≈ 66
且 C 大的对子稳态更高 → 分化，而非平移。

运行：python tools/calib_experiment.py [days]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim  # noqa: E402


def run(beta_a, keep_a, fb, days, seed=12345):
    s = Sim(seed=seed, npc_count=16)
    s.p["beta_a"] = beta_a
    s.decay["affinity"] = keep_a
    s.feedback = fb
    for _ in range(days):
        s.run_day()
    n = s.N
    aff = sorted(s.A[i][j] for i in range(n) for j in range(n) if i != j)
    sat = 100.0 * sum(1 for v in aff if v >= 95) / len(aff)
    over60 = 100.0 * sum(1 for v in aff if v >= 60) / len(aff)
    over30 = 100.0 * sum(1 for v in aff if v >= 30) / len(aff)
    # 分化度：标准差（越大越有"格局"）
    mean = sum(aff) / len(aff)
    sd = (sum((v - mean) ** 2 for v in aff) / len(aff)) ** 0.5
    print("  beta=%.3f keep=%.2f fb=%.1f | 均值 %5.1f 中位 %5.1f SD %4.1f | >=30 %4.1f%% >=60 %4.1f%% >=95 %4.1f%% | 压力峰值 %4.1f"
          % (beta_a, keep_a, fb, mean, aff[len(aff) // 2], sd, over30, over60, sat, max(s.Stress)))


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 15
    print("=== 实验 v2（%d 天，seed=12345，17 节点）===" % days)
    print("  目标：均值 45–65、饱和 <10%%、SD 尽量大（分化）")
    for beta_a, keep_a, fb in [
        (0.120, 0.95, 0.0),    # 现状（对照）
        (0.120, 0.95, 1.0),    # 满负反馈
        (0.160, 0.95, 1.0),    # 加大 beta 补偿负反馈的削弱
        (0.200, 0.95, 1.0),
        (0.160, 0.92, 1.0),
    ]:
        run(beta_a, keep_a, fb, days)


if __name__ == "__main__":
    main()
