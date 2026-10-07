"""玩法指标门（第四道门）—— **分布判据版**

设计原则（三次演进）：
  ① 前三道门不检查玩法指标 → 曾出现「三道门全绿、却提交了四项不达标状态」；
  ② 改多 seed 后又发现**单 seed 标定 = 过拟合**（8 seed 只 1 个达标）；
  ③ **但「每局都达标」也是错的** —— 用户指出：**涌现的本意就是「每局都不一样」**，
     逼每局相同等于扼杀涌现。

∴ 本门现在判**分布**，不判单局：
  · **跨局均值** 落在目标区间（「平均对不对」）；
  · **畸形项**（如好感饱和）要求**每一局都守住** —— 那是病态，不是多样性；
  · **跨局分化度**要求足够大 —— 防止退化成「每局一模一样」。

即：**允许每局不同，但不允许平均不对、也不允许全员畸形。**

运行：
  python tools/check_metrics.py                     # 默认 40 个种子（长尾指标需要大样本）
  python tools/check_metrics.py --seeds 60 --days 30
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim  # noqa: E402

# 默认种子集 **40**（2026-10-07 由 8 提到 40）。
# 起因：爆发次数是**长尾**指标 —— 少数几局就能主导均值，8 局会系统性误判。
# 实测同一份代码只换种子集：8 局 → 11.6 / 20 局 → 13.6 / 40 局 → 17.8 / 60 局 → 21.9。
# 门必须跑在大样本上，否则「达标」只是拟合了那几个种子（§3.4.1 第六条）。
SEEDS = [12345, 42, 2024, 999, 31415, 2718, 1618] + list(range(1, 34))   # 7 + 33 = 40，无重复


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
        "stress_mean": sum(s.Stress) / n,
        "reports": s.stats.get("reports", 0),
        "excludes": s.stats.get("excludes", 0),
        "humiliations": s.stats.get("humiliations", 0),
        "deep_max": max(s.H_deep[i][j] for i in range(n) for j in range(n) if i != j),
        "h_max": max(s.H[i][j] for i in range(n) for j in range(n) if i != j),
    }
    if verbose:
        print("  seed=%-6d 爆发%3d 举报%2d 排挤%2d 羞辱%3d | mean%5.1f sd%4.1f sat%4.1f 压力%5.1f | 敌对max%6.1f 深层max%6.1f"
              % (seed, r["bursts"], r["reports"], r["excludes"], r["humiliations"],
                 r["mean"], r["sd"], r["sat"], r["stress_mean"], r["h_max"], r["deep_max"]))
    return r


def avg(vals):
    return sum(vals) / len(vals)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--npc", type=int, default=16)
    ap.add_argument("--seeds", type=int, default=len(SEEDS))
    a = ap.parse_args()

    # 超出默认集时用 1000+ 的种子续接，避免与默认集重复
    seeds = (SEEDS[: a.seeds] if a.seeds <= len(SEEDS)
             else SEEDS + list(range(1000, 1000 + a.seeds - len(SEEDS))))
    print("=== 玩法指标门（分布判据 ：%d 局 × %d 天）===" % (len(seeds), a.days))
    rows = [run_one(sd, a.days, a.npc, verbose=True) for sd in seeds]

    ok_all = True

    def line(ok, name, got, want, extra=""):
        nonlocal ok_all
        ok_all = ok_all and ok
        print("  %s %-14s %-30s 目标 %s%s" % ("✓" if ok else "✗", name, got, want, extra))

    print("\n  — 跨局分布（允许每局不同，只要求「平均对」）—")
    b = [r["bursts"] for r in rows]
    mn = [r["mean"] for r in rows]
    sd_ = [r["sd"] for r in rows]
    line(15 <= avg(b) <= 30, "压力爆发(均值)",
         "均值 %.1f ［%d, %d］" % (avg(b), min(b), max(b)), "15 – 30")
    line(45 <= avg(mn) <= 65, "好感均值", "均值 %.1f ［%.1f, %.1f］" % (avg(mn), min(mn), max(mn)), "45 – 65")
    line(avg(sd_) >= 20, "好感标准差", "均值 %.1f ［%.1f, %.1f］" % (avg(sd_), min(sd_), max(sd_)), "≥ 20")

    print("\n  — 畸形项（病态，必须每局守住）—")
    sat = [r["sat"] for r in rows]
    line(max(sat) < 10, "好感饱和率", "最大 %.1f%%（均值 %.1f%%）" % (max(sat), avg(sat)), "每局 < 10%")

    print("\n  — 分化度（防止退化成「每局一模一样」）—")
    spread_m = max(mn) - min(mn)
    spread_b = max(b) - min(b)
    line(spread_m >= 3.0, "好感均值跨局差", "%.1f（%.1f → %.1f）" % (spread_m, min(mn), max(mn)), "≥ 3.0")
    line(spread_b >= 5, "爆发跨局差", "%d（%d → %d）" % (spread_b, min(b), max(b)), "≥ 5")

    print("\n  — 涌现现象（跨局覆盖率，不要求每局都发生）—")
    rep = sum(1 for r in rows if r["reports"] > 0)
    exc = sum(1 for r in rows if r["excludes"] > 0)
    hum = sum(1 for r in rows if r["humiliations"] > 0)
    print("     举报 %d/%d 局（%.0f%%，共 %d 次）" % (rep, len(rows), 100.0 * rep / len(rows), sum(b2["reports"] for b2 in rows)))
    print("     排挤 %d/%d 局（共 %d 次）" % (exc, len(rows), sum(b2["excludes"] for b2 in rows)))
    print("     当众羞辱 %d/%d 局（共 %d 次）" % (hum, len(rows), sum(b2["humiliations"] for b2 in rows)))
    print("     压力均值跨局 ［%.1f, %.1f］" % (min(r["stress_mean"] for r in rows), max(r["stress_mean"] for r in rows)))
    print("     深层敌对最高 ［%.1f, %.1f］" % (min(r["deep_max"] for r in rows), max(r["deep_max"] for r in rows)))

    print("\n  %s" % ("✓ 分布判据全部达标" if ok_all else "✗ 有判据未达标 —— 不要提交"))
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
