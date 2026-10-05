"""第五道门：多样性与存在性报告

为什么需要它（第四道门之后的下一步）：
  · 第四道门管「平均对不对」（跨局均值 / 畸形项 / 粗粒度分化度）；
  · 但**方差分两种**，只有一种该管：
      **良性方差**（谁成为欺凌者、哪条边结死仇、派系怎么切、爆发落在哪天）→ **要保护**，
                   任何标定都不该压缩它；
      **失效方差**（机制整条线没上场）→ **要拦截**，那不是「另一种结局」，
                   而是「策划案承诺的体验在这局里缺席了」。
  · ∴ 本门做两类**存在性检查**，而不是均值对齐：
      ① **机制上场率** —— 跑 N 个种子，统计出现至少一次某机制的局的百分比；
      ② **结果多样性** —— 给每局一个「指纹」（最终 A 矩阵等），跨局比较相关度，
         高度重合才是「涌现死亡」的真信号。
      ③ **吸收态检查** —— 是否已有状态锁死（如深层敌对顶到上限），
         那是「局与局的差异被时间单调抹掉」的先兆。

运行：
  python tools/diversity_report.py                 # 默认 20 局
  python tools/diversity_report.py --seeds 40 --days 30
"""

import argparse
import itertools
import os
import statistics as st
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim  # noqa: E402

# 判定门槛（可调）
MIN_ACTIVE = {"举报": 0.15, "排挤": 0.80, "当众羞辱": 0.90, "爆发": 1.00}
MAX_CORR = 0.90        # 两两相关度超过它的对数比例上限（涌现死亡信号）
MAX_LOCKED = 0.50      # 「深层顶到上限」的局占比上限（吸收态先兆）


def corr(a, b):
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    da = sum((x - ma) ** 2 for x in a) ** 0.5
    db = sum((y - mb) ** 2 for y in b) ** 0.5
    return num / (da * db) if da * db else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--npc", type=int, default=16)
    ap.add_argument("--seeds", type=int, default=20)
    a = ap.parse_args()

    seeds = list(range(1000, 1000 + a.seeds))
    print("=== 第五道门：多样性与存在性（%d 局 × %d 天）===" % (len(seeds), a.days))

    rows = []
    for sd in seeds:
        s = Sim(seed=sd, npc_count=a.npc)
        for _ in range(a.days):
            s.run_day()
        n = s.N
        aff = [s.A[i][j] for i in range(n) for j in range(n) if i != j]
        rows.append({
            "seed": sd,
            "reports": s.stats.get("reports", 0),
            "excludes": s.stats.get("excludes", 0),
            "humiliations": s.stats.get("humiliations", 0),
            "bursts": s.stats["bursts"],
            "deep_max": max(s.H_deep[i][j] for i in range(n) for j in range(n) if i != j),
            "sat": 100.0 * sum(1 for x in aff if x >= 95) / len(aff),
            "A": aff,
        })

    ok_all = True

    def line(ok, name, got, want):
        nonlocal ok_all
        ok_all = ok_all and ok
        print("  %s %-12s %-42s 目标 %s" % ("✓" if ok else "✗", name, got, want))

    print("\n  — ① 机制上场率（存在性：机制在不在场）—")
    for key, label, th in [("reports", "举报", MIN_ACTIVE["举报"]),
                           ("excludes", "排挤", MIN_ACTIVE["排挤"]),
                           ("humiliations", "当众羞辱", MIN_ACTIVE["当众羞辱"]),
                           ("bursts", "爆发", MIN_ACTIVE["爆发"])]:
        hit = sum(1 for r in rows if r[key] > 0)
        rate = 100.0 * hit / len(rows)
        line(rate >= th * 100, label,
             "%2d/%d 局上场（%.0f%%，共 %d 次）" % (hit, len(rows), rate, sum(r[key] for r in rows)),
             "≥ %.0f%% 的局" % (th * 100))

    sil = [r for r in rows if r["reports"] == 0 and r["excludes"] == 0 and r["bursts"] == 0]
    print("     完全静默局（三项全 0）：%d/%d" % (len(sil), len(rows)))

    print("\n  — ② 结果多样性（良性方差：要保护，不得压缩）—")
    cs = [corr(r1["A"], r2["A"]) for r1, r2 in itertools.combinations(rows, 2)]
    hi = 100.0 * sum(1 for c in cs if c > MAX_CORR) / len(cs) if cs else 0
    line(hi <= 20, "指纹相关度",
         "均值 %.3f ｜ [%.3f, %.3f] ； >%.2f 占比 %.0f%%" % (st.mean(cs), min(cs), max(cs), MAX_CORR, hi),
         ">0.90 占比 ≤20%")
    b = [r["bursts"] for r in rows]
    print("     爆发跨局 ［%d, %d］（差距越大说明结局越分散）" % (min(b), max(b)))

    print("\n  — ③ 吸收态检查（时间把差异抹掉的先兆）—")
    locked = 100.0 * sum(1 for r in rows if r["deep_max"] >= 69.9) / len(rows)
    line(locked <= MAX_LOCKED * 100, "深层锁死率",
         "%d/%d 局顶到上限（%.0f%%）" % (sum(1 for r in rows if r["deep_max"] >= 69.9), len(rows), locked),
         "≤ %.0f%%" % (MAX_LOCKED * 100))
    print("     deep_max ［%.1f, %.1f］ 均值 %.1f" % (
        min(r["deep_max"] for r in rows), max(r["deep_max"] for r in rows),
        st.mean([r["deep_max"] for r in rows])))

    print("\n  %s" % ("✓ 存在性与多样性判据全部达标" if ok_all else "✗ 有判据未达标 —— 不要提交"))
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
