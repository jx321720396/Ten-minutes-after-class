"""玩法指标门（第四道门）

背景：前三道门（`check_config` / `test_core` / `verify_formula`）都不检查**玩法指标**，
于是曾出现「三道门全绿、却提交了四项不达标状态」的情况。本工具把 §3.4 的四项目标变成可自动判定的门。

运行：python tools/check_metrics.py [--days 30] [--seed 12345]
达标线（依据主文档 §3.4）：
  · 压力爆发次数     15 – 30（30 天）
  · 好感饱和率(≥95)  < 10%
  · 好感均值         45 – 65
  · 好感标准差       ≥ 20（分化度）
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--npc", type=int, default=16)
    a = ap.parse_args()

    s = Sim(seed=a.seed, npc_count=a.npc)
    for _ in range(a.days):
        s.run_day()
    n = s.N
    aff = sorted(s.A[i][j] for i in range(n) for j in range(n) if i != j)
    mean = sum(aff) / len(aff)
    sd = (sum((x - mean) ** 2 for x in aff) / len(aff)) ** 0.5
    sat = 100.0 * sum(1 for x in aff if x >= 95) / len(aff)
    b = s.stats["bursts"]

    ok = True
    def chk(name, cond, val, want):
        nonlocal ok
        ok = ok and cond
        print("  %s %-22s %8.1f   目标 %s" % ("✓" if cond else "✗", name, val, want))

    print("=== 玩法指标门（%d 天，seed=%d）===" % (a.days, a.seed))
    chk("压力爆发次数", 15 <= b <= 30, b, "15 – 30")
    chk("好感饱和率(%)", sat < 10, sat, "< 10")
    chk("好感均值", 45 <= mean <= 65, mean, "45 – 65")
    chk("好感标准差", sd >= 20, sd, "≥ 20")
    print("\n  %s" % ("✓ 四项全部达标" if ok else "✗ 有指标不达标 —— 不要提交"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
