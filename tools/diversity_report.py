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
  python tools/diversity_report.py                 # 默认 100 局
  python tools/diversity_report.py --seeds 200 --days 30
  python tools/diversity_report.py --jobs 1        # 强制串行（调试用）

并行：局与局互相独立（各自 Sim(seed) + random.Random(seed)），默认按核数并行，
      结果与串行**逐位一致**（executor.map 保序）。100 局：串行约 190s → 并行约 17s。

⚠️ 样本量为什么是 100（2026-10-07 由 20 提高）：
  本门的判据是**出场率**（`hit / 局数`），而 20 局的二项标准误约 **10 个百分点** ——
  门槛 70% 的机制，真实率 72% 时，20 局样本有相当概率测出 65%（不合格）。
  实测同一份代码、同一种子起点、只改样本量：排挤出现率 20 局 65% / 80 局 72% / 100 局 72%。
  ∴ 20 局的「达标」与「不达标」都不可信 —— 门必须跑在大样本上（§3.4.1 六）。
  100 局的标准误降到约 4.5 个百分点 —— 但排挤真实率约 72%，距 70% 下限只剩约 2pp，
  仍属**边缘达标**（成因见主文档 §10.23：排挤的证据完全由当众羞辱喂给 `hurt_day`）。
"""

import argparse
import itertools
import os
import statistics as st
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim  # noqa: E402

# 判定门槛 = **「机制下限」**，不是「目标值」。按 §3.4.1 七：这里管的是「机制在不在场」。
# ⚠️ 基线说明（2026-10-05 重定）：语义修正（P0-1/P0-2/P1/选项C）后机制**变稀有是正常的** ——
#   · 举报：深层敌对只由「当众羞辱」写入，而羞辱又要求「被围满且围观者众」，
#     因此它是**罕见但不应绝迹**的机制 —— 下限 10%（旧值 15% 是错误前提下的产物）；
#   · 排挤：要求「近期 ≥2 人做过重大损害」，实测 75%，下限取 70%；
#   · 羞辱：应几乎必现，下限 90%；
#   · **爆发：100% → 90%（2026-10-07 用户裁决）**。100% 是「**普适性要求**」，
#     而本门管的是「**机制在不在场**」（§3.4.1 七）—— 「96% 的局里爆发过」显然属于在场。
#     更根本的是：没有任何机制有「必现」的保证，写 100% 等于宣告本门在小样本下必然绿灯、
#     在大样本下必然红灯 —— 那是**样本量的函数，不是机制的信号**。
#     实测（同批 100 个种子）：θ=3 时 94%、θ=4 时 96%；20 局时之所以是 20/20，
#     只是抽样还没抽到尾部。门槛必须与样本量匹配（§3.4.1 六）。
MIN_ACTIVE = {"举报": 0.10, "排挤": 0.70, "当众羞辱": 0.90, "爆发": 0.90}
MAX_CORR = 0.90        # 两两相关度超过它的对数比例上限（涌现死亡信号）
MAX_LOCKED = 0.50      # 「深层顶到上限」的局占比上限（吸收态先兆）


def corr(a, b):
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    da = sum((x - ma) ** 2 for x in a) ** 0.5
    db = sum((y - mb) ** 2 for y in b) ** 0.5
    return num / (da * db) if da * db else 0.0


def run_one(seed, days, npc):
    """跑一局并抽出本门需要的指纹字段"""
    s = Sim(seed=seed, npc_count=npc)
    for _ in range(days):
        s.run_day()
    n = s.N
    aff = [s.A[i][j] for i in range(n) for j in range(n) if i != j]
    return {
        "seed": seed,
        "reports": s.stats.get("reports", 0),
        "excludes": s.stats.get("excludes", 0),
        "humiliations": s.stats.get("humiliations", 0),
        "bursts": s.stats["bursts"],
        "deep_max": max(s.H_deep[i][j] for i in range(n) for j in range(n) if i != j),
        "sat": 100.0 * sum(1 for x in aff if x >= 95) / len(aff),
        "A": aff,
    }


def run_seeds(seeds, days, npc, jobs):
    """跑一批种子。

    可并行：每局 = 独立的 `Sim(seed)` + 独立的 `random.Random(seed)`，局与局之间没有
    任何共享状态，所以并行结果与串行**逐位一致**（`executor.map` 保序返回）。
    """
    if jobs <= 1 or len(seeds) <= 1:
        return [run_one(sd, days, npc) for sd in seeds]
    from concurrent.futures import ProcessPoolExecutor
    with ProcessPoolExecutor(max_workers=jobs) as ex:
        return list(ex.map(run_one, seeds, itertools.repeat(days), itertools.repeat(npc)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--npc", type=int, default=16)
    ap.add_argument("--seeds", type=int, default=100)
    ap.add_argument("--jobs", type=int, default=0,
                    help="并行进程数（0=按 CPU 核数自动，1=强制串行）")
    a = ap.parse_args()

    seeds = list(range(1000, 1000 + a.seeds))
    # 自动并行度：核数、局数、上限三者取小。
    # 加 16 的上限是因为 `cpu_count()` 只报逻辑核，**报不准「本进程实际能用的核」**——
    # 容器/cgroup 配额下实测报 32 而实际约 6 核，多开的进程只是在白付启动与调度开销
    # （实测 100 局：jobs=6 → 17.4s，jobs=32 → 21.0s）。知道自家机器余量时用 --jobs 覆盖。
    jobs = a.jobs if a.jobs > 0 else min(os.cpu_count() or 1, 16, len(seeds))
    print("=== 第五道门：多样性与存在性（%d 局 × %d 天，并行 %d 进程）===" % (len(seeds), a.days, jobs))

    rows = run_seeds(seeds, a.days, a.npc, jobs)

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
