"""玩法指标门（第四道门）—— **多种子版**

背景（两轮教训）：
  ① 前三道门都不检查**玩法指标**，曾出现「三道门全绿、却提交了四项不达标状态」；
  ② 随后又发现**单一种子标定 = 过拟合**：8 个 seed 里只有 1 个达标（举报 0/8），
     而此前几轮都是拿 seed=12345 一个种子调参数调到达标。

∴ 本门现在按**多种子分布**判定（均值 / 区间 / 达标比例），单局数字不再作为依据。
  这与 §3.4.1 的标定纪律一致。

运行：
  python tools/check_metrics.py                     # 默认 8 个种子
  python tools/check_metrics.py --seeds 20 --days 30
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim  # noqa: E402

SEEDS = [12345, 42, 7, 2024, 999, 31415, 2718, 1618]
# 每项：(名称, 取值函数, 单局达标判定, 合格比例门槛, 展示格式)
ITEMS = [
    ("压力爆发次数", lambda r: r["bursts"], lambda v: 15 <= v <= 30, 0.60, "%.0f"),
    ("好感饱和率(%)", lambda r: r["sat"], lambda v: v < 10, 0.90, "%.1f"),
    ("好感均值", lambda r: r["mean"], lambda v: 45 <= v <= 65, 0.60, "%.1f"),
    ("好感标准差", lambda r: r["sd"], lambda v: v >= 20, 0.50, "%.1f"),
]


def run_one(seed, days, npc, verbose=False):
    s = Sim(seed=seed, npc_count=npc)
    for _ in range(days):
        s.run_day()
    n = s.N
    aff = sorted(s.A[i][j] for i in range(n) for j in range(n) if i != j)
    mean = sum(aff) / len(aff)
    sd = (sum((x - mean) ** 2 for x in aff) / len(aff)) ** 0.5
    r = {
        "seed": seed,
        "bursts": s.stats["bursts"],
        "sat": 100.0 * sum(1 for x in aff if x >= 95) / len(aff),
        "mean": mean,
        "sd": sd,
        "reports": s.stats.get("reports", 0),
        "excludes": s.stats.get("excludes", 0),
        "humiliations": s.stats.get("humiliations", 0),
        "deep_max": max(s.H_deep[i][j] for i in range(n) for j in range(n) if i != j),
        "h_max": max(s.H[i][j] for i in range(n) for j in range(n) if i != j),
    }
    if verbose:
        print("  seed=%-6d 爆发%3d 举报%2d 排挤%2d 羞辱%3d | mean%5.1f sd%4.1f sat%4.1f | 敌对max%6.1f 深层max%6.1f"
              % (seed, r["bursts"], r["reports"], r["excludes"], r["humiliations"],
                 r["mean"], r["sd"], r["sat"], r["h_max"], r["deep_max"]))
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--npc", type=int, default=16)
    ap.add_argument("--seeds", type=int, default=len(SEEDS), help="取前 N 个种子")
    a = ap.parse_args()

    seeds = SEEDS[: a.seeds] if a.seeds <= len(SEEDS) else SEEDS + list(range(a.seeds - len(SEEDS)))
    print("=== 玩法指标门（多 seed：%d 个 × %d 天）===" % (len(seeds), a.days))
    rows = [run_one(sd, a.days, a.npc, verbose=True) for sd in seeds]

    ok_all = True
    print("\n  %-16s %8s %8s %8s %8s   %s" % ("指标", "均值", "最小", "最大", "合格率", "判定"))
    for name, get, good, need, fmt in ITEMS:
        vals = [get(r) for r in rows]
        hit = sum(1 for v in vals if good(v)) / len(vals)
        ok = hit >= need
        ok_all = ok_all and ok
        print("  %s %-14s %8s %8s %8s %7.0f%%   需 ≥%.0f%% %s"
              % ("✓" if ok else "✗", name, fmt % (sum(vals) / len(vals)),
                 fmt % min(vals), fmt % max(vals), hit * 100, need * 100, "" if ok else "← 不达标"))

    rep_hit = sum(1 for r in rows if r["reports"] > 0) / len(rows)
    exc_hit = sum(1 for r in rows if r["excludes"] > 0) / len(rows)
    print("\n  【涌现现象覆盖率】举报出现 %.0f%% 的局 ； 排挤出现 %.0f%% 的局 ； 举报均值 %.1f 次"
          % (rep_hit * 100, exc_hit * 100, sum(r["reports"] for r in rows) / len(rows)))

    print("\n  %s" % ("✓ 多 seed 全部达标" if ok_all else "✗ 有指标未达标 —— 不要提交"))
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
