"""1000 局角色类型统计（只读调用 tools.core_sim，不修改内核）。"""
import argparse
import csv
import os
import sys
from collections import Counter, defaultdict
from multiprocessing import freeze_support
from concurrent.futures import ProcessPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from tools.core_sim import Sim  # noqa: E402


def load_aliases():
    path = os.path.join(ROOT, "data", "characters", "seeds.csv")
    with open(path, encoding="utf-8-sig", newline="") as f:
        return [r["alias"] for r in csv.DictReader(line for line in f if not line.startswith("#"))]


def hook_events(sim, event_counts):
    for name in ("do_report", "do_exclude", "do_tease", "do_roughhouse", "do_chat"):
        original = getattr(sim, name, None)
        if original is None:
            continue

        def wrapped(*args, _original=original, _name=name, **kwargs):
            if args:
                actor = args[0]
                target = args[1] if len(args) > 1 else None
                event_counts[actor][_name + "_actor"] += 1
                if target is not None:
                    event_counts[target][_name + "_target"] += 1
            return _original(*args, **kwargs)

        setattr(sim, name, wrapped)


def one(seed, npc_count, days, aliases):
    sim = Sim(seed=seed, npc_count=npc_count)
    events = defaultdict(Counter)
    hook_events(sim, events)
    for _ in range(days):
        sim.run_day()

    n = sim.N
    names = [c["alias"] for c in sim.chars]
    indices = range(min(npc_count, n))
    result = {a: Counter() for a in aliases}
    for i in indices:
        name = names[i]
        others = [j for j in range(n) if j != i]
        recv = sum(sim.A[j][i] for j in others) / len(others)
        give = sum(sim.A[i][j] for j in others) / len(others)
        hostile = sum(sim.H[j][i] for j in others) / len(others)
        result[name]["recv_aff_sum"] += recv
        result[name]["give_aff_sum"] += give
        result[name]["stress_sum"] += sim.Stress[i]
        result[name]["recv_host_sum"] += hostile
        if sim.Stress[i] >= 70:
            result[name]["high_stress"] += 1
        if hostile >= 25:
            result[name]["high_hostility"] += 1
        if max(sim.H[j][i] for j in others) >= 40:
            result[name]["hostility_edge"] += 1
        for key, value in events[i].items():
            result[name][key] += value

    recv = {i: sum(sim.A[j][i] for j in range(n) if j != i) / (n - 1) for i in indices}
    give = {i: sum(sim.A[i][j] for j in range(n) if j != i) / (n - 1) for i in indices}
    avg_recv = sum(recv.values()) / len(recv)
    for i in indices:
        if recv[i] < avg_recv - 15 and give[i] > recv[i] + 15:
            result[names[i]]["isolated"] += 1

    adjacency = {i: set() for i in indices}
    for i in indices:
        for j in indices:
            if i < j and sim.A[i][j] >= 60 and sim.A[j][i] >= 60:
                adjacency[i].add(j)
                adjacency[j].add(i)
    seen = set()
    for i in indices:
        if i in seen:
            continue
        stack, component = [i], []
        while stack:
            x = stack.pop()
            if x in seen:
                continue
            seen.add(x)
            component.append(x)
            stack.extend(adjacency[x] - seen)
        if len(component) >= 3:
            for x in component:
                result[names[x]]["cluster_member"] += 1
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=1000)
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--npc", type=int, default=16)
    ap.add_argument("--seed", type=int, default=1000)
    ap.add_argument("--jobs", type=int, default=1)
    args = ap.parse_args()
    aliases = load_aliases()
    totals = {a: Counter() for a in aliases}
    seeds = range(args.seed, args.seed + args.runs)
    if args.jobs > 1:
        with ProcessPoolExecutor(max_workers=args.jobs) as pool:
            batches = pool.map(one, seeds, [args.npc] * args.runs,
                               [args.days] * args.runs, [aliases] * args.runs,
                               chunksize=1)
            for batch in batches:
                for alias in aliases:
                    totals[alias].update(batch[alias])
    else:
        batches = (one(seed, args.npc, args.days, aliases) for seed in seeds)
        for batch in batches:
            for alias in aliases:
                totals[alias].update(batch[alias])

    print("runs=%d days=%d npc=%d seed_start=%d jobs=%d" % (args.runs, args.days, args.npc, args.seed, args.jobs))
    print("角色|孤立|高敌对|强敌对边|高压力|强连接簇|举报者|被举报|排挤发起|被排挤|羞辱发起|被羞辱|最终收件好感|最终给出好感|最终压力|最终收到敌对")
    for alias in aliases:
        row = totals[alias]
        q = lambda key: row[key]
        print("%s|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%.1f|%.1f|%.1f|%.1f" % (
            alias, q("isolated"), q("high_hostility"), q("hostility_edge"), q("high_stress"),
            q("cluster_member"), q("do_report_actor"), q("do_report_target"),
            q("do_exclude_actor"), q("do_exclude_target"), q("do_tease_actor"), q("do_tease_target"),
            q("recv_aff_sum") / args.runs, q("give_aff_sum") / args.runs,
            q("stress_sum") / args.runs, q("recv_host_sum") / args.runs))


if __name__ == "__main__":
    freeze_support()
    main()
