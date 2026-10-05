"""标定实验 v3：负反馈作用于「统一写入点」后，能否同时满足均值与低饱和

v2 的教训：只把负反馈加在传导上不够 —— 事件增益不受约束，且 C 会随越阈人数增长而抵消抑制。
v3：负反馈作用于统一写入点的正向轴（好感/信任），负面轴不适用。

稳态估算：keep=0.90, 总增益 g=20 → 0.10·A* = 20(1 − A*/100) → A* ≈ 67

运行：python tools/calib_experiment.py [days]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim  # noqa: E402


def run(keep_a, fb, beta_a, days, seed=12345):
    s = Sim(seed=seed, npc_count=16)
    s.decay["affinity"] = keep_a
    s.feedback = fb
    s.p["beta_a"] = beta_a
    for _ in range(days):
        s.run_day()
    n = s.N
    aff = sorted(s.A[i][j] for i in range(n) for j in range(n) if i != j)
    mean = sum(aff) / len(aff)
    sd = (sum((v - mean) ** 2 for v in aff) / len(aff)) ** 0.5
    sat = 100.0 * sum(1 for v in aff if v >= 95) / len(aff)
    over60 = 100.0 * sum(1 for v in aff if v >= 60) / len(aff)
    print("  keep=%.2f fb=%.1f beta=%.2f | 均值 %5.1f 中位 %5.1f SD %4.1f | >=60 %4.1f%% >=95 %4.1f%% | 敌对均值 %4.1f | 压力峰值 %4.1f"
          % (keep_a, fb, beta_a, mean, aff[len(aff) // 2], sd, over60, sat,
             sum(s.H[i][j] for i in range(n) for j in range(n) if i != j) / (n * (n - 1)), max(s.Stress)))


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 25
    print("=== 实验 v3（%d 天，seed=12345，17 节点）===" % days)
    print("  目标：均值 45–65、饱和 <10%%、SD ≥20")
    for keep_a, fb, beta_a in [
        (0.95, 1.0, 0.20),   # v2 方案（负反馈只在传导）
        (0.90, 1.0, 0.20),   # 负反馈在统一写入 + 加强衰减
        (0.90, 1.0, 0.12),
        (0.92, 1.0, 0.12),
        (0.90, 0.6, 0.12),
    ]:
        run(keep_a, fb, beta_a, days)


if __name__ == "__main__":
    main()
