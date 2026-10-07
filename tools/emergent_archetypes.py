"""涌现个体原型报告（分析工具，**不属于六道门**）

要回答的问题：**跑很多局之后，班级里反复冒出来的「独特个体」是哪几类、多常见？**

设计约束（与主文档铁律一致）：
  · §11.1 禁止按角色名 / ID 做行为判断 —— 所以这里**不定义身份**，只定义**原型**：
    「举报者」= 发起过举报的人，「被排挤者」= 被排挤结算指向的人……
    全部是 f(行为事件, 终局结构, 状态) 的纯判定，角色只是**事后贴上去的标签**。
  · **只读**：本工具用子类覆写 `do_*` 钩子做记录，不改动 core_sim 的任何模拟逻辑，
    不改任何矩阵（与 ObserverLayer 同一条「观察层只读」纪律，§10）。
  · 玩家节点（索引 N-1）无角色种子，**不参与统计**，但仍计入「全班」分母。

原型三族：
  施予方（制造事端） 举报者 / 嘲讽发起者 / 当众羞辱者 / 排挤发起者 / 流言源头 / 打闹搭子
  承受方（被针对）   被举报者 / 被嘲讽者 / 被当众羞辱者 / 被排挤者 / 被传谣者 / 压力爆发者
  结构位（终局拓扑） 被孤立者 / 人气中心 / 众矢之的

运行：
  python tools/emergent_archetypes.py                                  # 40 局 × 30 天 × 16 NPC
  python tools/emergent_archetypes.py --seeds 1000 --jobs 16           # 大样本：按种子分片并行
  python tools/emergent_archetypes.py --seeds 60 --days 30 --tag 试验

并行说明：每局各自持有带种子的 RandomNumberGenerator，**进程数不影响结果**，
--jobs 只改跑得快慢（结果与串行逐字节一致）。
"""

import argparse
import collections
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from core_sim import Sim  # noqa: E402

# ---------------------------------------------------------------- 原型定义
FAMILIES = [
    ("施予方", ["举报者", "嘲讽发起者", "当众羞辱者", "排挤发起者", "流言源头", "打闹搭子"]),
    ("承受方", ["被举报者", "被嘲讽者", "被当众羞辱者", "被排挤者", "被传谣者", "压力爆发者"]),
    ("结构位", ["被孤立者", "人气中心", "众矢之的"]),
]
ORDER = [a for _, xs in FAMILIES for a in xs]
FAMILY_OF = {a: f for f, xs in FAMILIES for a in xs}


class ProbeSim(Sim):
    """覆写行为结算入口，记录「谁对谁做了什么」。所有覆写都先记录、后 super()。"""

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self.roles = collections.defaultdict(collections.Counter)   # 原型 -> Counter(节点索引 -> 次数)
        self.player = self.N - 1

    def _mark(self, role, idx):
        if idx is None or idx == self.player:
            return
        self.roles[role][idx] += 1

    # --- 施予 / 承受 成对的四个行为 ---
    def do_report(self, i, j):
        self._mark("举报者", i)
        self._mark("被举报者", j)
        return super().do_report(i, j)

    def do_tease(self, i, j, audience):
        # 复刻 do_tease 的**分档判据**（在 super() 改动矩阵之前求值，故读到的与 super 相同）
        th = self.thresholds_lookup
        laugh = (self.A[i][j] >= th["tease_laugh_affinity"]
                 and self.H[i][j] < th["tease_laugh_hostility"])
        if not laugh and (self.H[i][j] >= th["tease_taunt_hostility"]
                          or self.A[i][j] < th["tease_taunt_affinity"]):
            self._mark("嘲讽发起者", i)
            self._mark("被嘲讽者", j)
            if len(audience) >= th.get("humiliate_bystanders", 3.0):
                # §10.23：被一群人围着嘲笑 = 当众羞辱，写进永不衰减的深层
                self._mark("当众羞辱者", i)
                self._mark("被当众羞辱者", j)
        return super().do_tease(i, j, audience)

    def do_exclude(self, i, j, crowd):
        self._mark("排挤发起者", i)
        self._mark("被排挤者", j)
        return super().do_exclude(i, j, crowd)

    def do_rumor(self, i, j):
        self._mark("流言源头", i)
        self._mark("被传谣者", j)
        return super().do_rumor(i, j)

    def do_roughhouse(self, i, j, bystanders):
        self._mark("打闹搭子", i)
        self._mark("打闹搭子", j)
        return super().do_roughhouse(i, j, bystanders)

    def try_burst(self):
        # 爆发只体现在 knot_days 被抬高（stress 归零后无从反推），故做前后差
        before = list(self.knot_days)
        super().try_burst()
        for i in range(self.N):
            if self.knot_days[i] > before[i]:
                self._mark("压力爆发者", i)


def structural_roles(sim):
    """终局结构位：由终局矩阵判定，与行为事件无关。

    · 被孤立者 §10.26.3：「全班都不喜欢他，而他还喜欢大家」——他人→他显著低 + 他→他人接近正常。
    · 人气中心 / 众矢之的：入度好感 / 入度深层敌对 的最高者（结构性 position，每局必然存在一个）。
    """
    n = sim.N
    player = n - 1
    cand = [i for i in range(n) if i != player]
    cls = list(range(n))                                     # 「全班」含玩家
    out = collections.defaultdict(collections.Counter)

    recv, give = {}, {}
    for j in cand:
        recv[j] = sum(sim.A[i][j] for i in cls if i != j) / (n - 1)
        give[j] = sum(sim.A[j][i] for i in cls if i != j) / (n - 1)
    avg = sum(recv.values()) / len(recv)
    for j in cand:
        if recv[j] < avg - 15.0 and give[j] > recv[j] + 15.0:
            out["被孤立者"][j] += 1

    liked = [(recv[j], j) for j in cand]
    liked.sort(key=lambda t: (-t[0], t[1]))
    out["人气中心"][liked[0][1]] += 1

    hated = [(sum(sim.H_deep[i][j] for i in cls if i != j) / (n - 1), j) for j in cand]
    hated.sort(key=lambda t: (-t[0], t[1]))
    out["众矢之的"][hated[0][1]] += 1
    return out


def run_one(seed, days, npc):
    """跑一局，返回 {原型: {角色别名: 次数}}。

    返回值是**纯数据**（不含 Sim 对象），因此可以安全地在进程间传递 —— 这是 --jobs 的前提。
    """
    s = ProbeSim(seed=seed, npc_count=npc)
    for _ in range(days):
        s.run_day()
    for role, cnt in structural_roles(s).items():
        s.roles[role].update(cnt)
    alias = {i: s.chars[i]["alias"] for i in range(npc)}
    return {role: {alias[i]: c for i, c in cnt.items() if i in alias}
            for role, cnt in s.roles.items()}


def _worker(task):
    """multiprocessing 入口：参数打成一个 tuple 才可 pickle。"""
    return run_one(*task)


def topn(counter, k=None):
    """次数降序、**同次数按角色名升序**。

    为什么不用 `Counter.most_common`：它对并列项按**插入顺序**返回，而插入顺序取决于
    局的处理顺序（--jobs 下 imap_unordered 的完成顺序）—— 会让「谁是第三名」在并行/串行
    之间漂移。并列就该由名字决定，结果才与进程数无关。
    """
    items = sorted(counter.items(), key=lambda kv: (-kv[1], kv[0]))
    return items[:k] if k else items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--npc", type=int, default=16)
    ap.add_argument("--seeds", type=int, default=40)
    ap.add_argument("--seed-start", type=int, default=1000)
    ap.add_argument("--jobs", type=int, default=1)
    ap.add_argument("--tag", default=None, help="输出文件名里的标识；默认「<局数>局」")
    ap.add_argument("--out-dir", default="docs/qa")
    a = ap.parse_args()

    seeds = list(range(a.seed_start, a.seed_start + a.seeds))
    tag = a.tag if a.tag is not None else "%d局" % a.seeds
    step = max(1, len(seeds) // 10)
    print("=== 涌现个体原型（%d 局 × %d 天 × %d NPC × %d 进程）===" % (
        len(seeds), a.days, a.npc, a.jobs))
    sys.stdout.flush()

    runs = []                       # 每局：{原型: {角色别名: 次数}}
    if a.jobs > 1:
        import multiprocessing as mp
        tasks = [(sd, a.days, a.npc) for sd in seeds]
        with mp.Pool(a.jobs) as pool:
            # imap_unordered：先完成先回，进度条才有意义（每局独立同分布，顺序不影响聚合）
            for k, r in enumerate(pool.imap_unordered(_worker, tasks, chunksize=1), 1):
                runs.append(r)
                if k % step == 0 or k == len(seeds):
                    print("  ... %d/%d" % (k, len(seeds)))
                    sys.stdout.flush()
    else:
        for k, sd in enumerate(seeds, 1):
            runs.append(run_one(sd, a.days, a.npc))
            if k % step == 0 or k == len(seeds):
                print("  ... %d/%d" % (k, len(seeds)))
                sys.stdout.flush()

    # ---- 聚合 ----
    hit_runs = collections.Counter()                    # 原型 -> 出现局数
    hit_people = collections.Counter()                  # 原型 -> 累计命中人次（每局去重后相加）
    hit_times = collections.Counter()                   # 原型 -> 累计次数
    char_times = collections.defaultdict(collections.Counter)   # 原型 -> Counter(角色 -> 次数)
    char_runs = collections.defaultdict(collections.Counter)    # 原型 -> Counter(角色 -> 出现局数)
    for r in runs:
        for role, cnt in r.items():
            if not cnt:
                continue
            hit_runs[role] += 1
            hit_people[role] += len(cnt)
            hit_times[role] += sum(cnt.values())
            for name, c in cnt.items():
                char_times[role][name] += c
                char_runs[role][name] += 1

    N = len(runs)
    # 逐局指纹：某两个原型若在**每一局**的命中集合都完全相同，它们就不是两类人（自动检测，不写死）
    sig = {role: tuple(sorted(tuple(sorted(r.get(role, {}).items())) for r in runs)) for role in ORDER}
    dup_of = {}
    for x, y in [(ORDER[i], ORDER[j]) for i in range(len(ORDER)) for j in range(i + 1, len(ORDER))]:
        if hit_times[x] > 0 and sig[x] == sig[y] and x not in dup_of:
            dup_of[x] = y

    os.makedirs(a.out_dir, exist_ok=True)
    p1 = os.path.join(a.out_dir, "涌现个体原型-%s-2026-10-07.csv" % tag)
    p2 = os.path.join(a.out_dir, "涌现个体原型-%s-角色明细-2026-10-07.csv" % tag)
    for p in (p1, p2):
        if os.path.exists(p):
            print("✗ 目标已存在，未覆盖：%s\n  （要覆盖请先自行删除，或换一个 --tag）" % p)
            return 1

    with open(p1, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["原型", "家族", "出现局数", "总局数", "出现率%", "累计次数",
                    "场均次数", "平均每局命中人数", "候选人数", "头部集中度%",
                    "最常见角色1", "次数1", "最常见角色2", "次数2", "最常见角色3", "次数3", "备注"])
        for role in ORDER:
            top = topn(char_times[role], 3)
            conc = 100.0 * top[0][1] / hit_times[role] if hit_times[role] and top else 0.0
            top += [("", "")] * (3 - len(top))
            note = ("命中集合与「%s」逐局完全相同（当前实现下两者不可区分）" % dup_of[role]) if role in dup_of else ""
            w.writerow([role, FAMILY_OF[role], hit_runs[role], N,
                        round(100.0 * hit_runs[role] / N, 1), hit_times[role],
                        round(hit_times[role] / N, 2),
                        round(hit_people[role] / N, 2), a.npc, round(conc, 1),
                        top[0][0], top[0][1], top[1][0], top[1][1], top[2][0], top[2][1], note])

    with open(p2, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["原型", "家族", "角色", "出现局数", "总局数", "出现率%", "累计次数", "场均次数"])
        for role in ORDER:
            for name, c in topn(char_times[role]):
                w.writerow([role, FAMILY_OF[role], name, char_runs[role][name], N,
                            round(100.0 * char_runs[role][name] / N, 1), c, round(c / N, 2)])

    # ---- 屏幕上的速览（Markdown）----
    print("\n| 原型 | 家族 | 出现率 | 累计次数 | 场均命中人数 | 头部集中度 | 最常见角色 | 备注 |")
    print("|---|---|---|---|---|---|---|---|")
    for role in ORDER:
        top = topn(char_times[role], 3)
        tops = "、".join("%s(%d)" % t for t in top) or "—"
        conc = 100.0 * top[0][1] / hit_times[role] if hit_times[role] and top else 0.0
        print("| %s | %s | %.0f%%（%d/%d） | %d | %.2f/%d | %.0f%% | %s | %s |" % (
            role, FAMILY_OF[role], 100.0 * hit_runs[role] / N, hit_runs[role], N,
            hit_times[role], hit_people[role] / N, a.npc, conc, tops,
            ("与「%s」逐局完全相同" % dup_of[role]) if role in dup_of else ""))

    print("\n已写出：\n  %s\n  %s" % (p1, p2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
