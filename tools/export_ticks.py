#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""逐 tick 状态导出（对拍基建）。

用途：把 Python 内核原型（`tools/core_sim.py`）在**同一 seed** 下每个 tick 的关键状态导出成序列，
供 GDScript 内核移植后逐 tick 对拍 —— 对应冲刺计划 D6–D7「对拍基建」与
D8–D9 硬闸门（同种子关键指标误差 ≤ 1%，见 `docs/production/聚光灯21天冲刺计划.md`）。

做法：**不复制内核逻辑**。导出器 hook 住 ``Sim.tick``（实例属性覆盖），每次 tick 后采样一张快照 ——
因此它与内核永远同一份逻辑，内核改了导出跟着改。

每个 tick 一行，字段：

| 字段 | 含义 |
|---|---|
| `tick` / `day` / `phase` / `phase_index` / `tick_in_phase` | 时间定位（与内核 §3 时间系统一致） |
| `A_mean` / `H_mean` / `T_mean` | 关系三轴均值（对拍用「≤ 1% 误差」判据） |
| `O_mean` / `stress_mean` | 透明度 / 压力均值 |
| `A_hash` / `H_hash` / `T_hash` | 矩阵按 0.1 精度展开后的 sha256 前 16 位（严格对拍） |
| `events` / `bursts` / `transmits` | 累计事件 / 爆发 / 传导次数 |

输出默认落在 `tools/out/`（已在 `.gitignore`，属导出产物，不入库）。

用法：
    python tools/export_ticks.py --days 3 --seed 12345 --npc 8
    python tools/export_ticks.py --days 30 --seed 12345 --npc 8 --format csv --out tools/out/ticks.csv
"""

from __future__ import print_function

import argparse
import csv
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import core_sim  # noqa: E402  (同目录内核原型)

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

FIELDS = [
    "tick", "day", "phase", "phase_index", "tick_in_phase",
    "A_mean", "H_mean", "T_mean", "O_mean", "stress_mean",
    "A_hash", "H_hash", "T_hash",
    "events", "bursts", "transmits",
]


def _mean(values):
    return round(sum(values) / len(values), 3) if values else 0.0


def _digest(values):
    """0.1 精度（与统一影响公式的 round 精度一致）的序列指纹，供逐项对拍。"""
    text = ",".join("%.1f" % v for v in values)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def _flat(matrix):
    return [v for row in matrix for v in row]


def snapshot(sim):
    a, h, t = _flat(sim.A), _flat(sim.H), _flat(sim.T)
    return {
        "tick": sim.global_tick,
        "day": sim.day,
        "phase": sim.phase,
        "phase_index": sim.phase_index,
        "tick_in_phase": sim.tick_in_phase,
        "A_mean": _mean(a),
        "H_mean": _mean(h),
        "T_mean": _mean(t),
        "O_mean": _mean(list(sim.O)),
        "stress_mean": _mean(list(sim.Stress)),
        "A_hash": _digest(a),
        "H_hash": _digest(h),
        "T_hash": _digest(t),
        "events": sim.stats.get("events", 0),
        "bursts": sim.stats.get("bursts", 0),
        "transmits": sim.stats.get("transmission_ticks", 0),
    }


def collect(seed, npc, days):
    """跑内核并逐 tick 采样（hook 实例上的 tick，不碰内核源码）。"""
    sim = core_sim.Sim(seed=seed, npc_count=npc)
    rows = []
    original_tick = sim.tick

    def hooked_tick():
        original_tick()
        rows.append(snapshot(sim))

    sim.tick = hooked_tick
    for _ in range(days):
        sim.run_day()
    return sim, rows


def write_rows(rows, path, fmt):
    directory = os.path.dirname(os.path.abspath(path))
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        if fmt == "csv":
            writer = csv.DictWriter(handle, fieldnames=FIELDS)
            writer.writeheader()
            for row in rows:
                writer.writerow(row)
        else:
            for row in rows:
                handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Python 内核逐 tick 状态导出（对拍基建）")
    parser.add_argument("--days", type=int, default=1)
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--npc", type=int, default=8)
    parser.add_argument("--format", choices=("jsonl", "csv"), default="jsonl")
    parser.add_argument("--out", default=None, help="输出文件（默认 tools/out/ticks_*.jsonl）")
    parser.add_argument("--quiet", action="store_true", help="只打印路径与行数")
    args = parser.parse_args(argv)

    out = args.out or os.path.join(
        OUT_DIR, "ticks_seed%d_npc%d_%dd.%s" % (args.seed, args.npc, args.days,
                                                "csv" if args.format == "csv" else "jsonl"))
    sim, rows = collect(args.seed, args.npc, args.days)
    write_rows(rows, out, args.format)

    print("导出完成：%d 个 tick -> %s" % (len(rows), out))
    print("口径：seed=%d，npc=%d（含玩家节点共 %d），%d 天" % (
        args.seed, args.npc, sim.N, args.days))
    if not args.quiet and rows:
        print("")
        print("前 3 个 tick：")
        for row in rows[:3]:
            print("  tick=%-4d day=%d %-5s A_mean=%-7s A_hash=%s" % (
                row["tick"], row["day"], row["phase"], row["A_mean"], row["A_hash"]))
        print("末个 tick ：tick=%-4d day=%d %-5s A_mean=%-7s A_hash=%s" % (
            rows[-1]["tick"], rows[-1]["day"], rows[-1]["phase"],
            rows[-1]["A_mean"], rows[-1]["A_hash"]))
        print("")
        print("对拍提示：GDScript 侧读同一文件，逐 tick 比 A_mean/H_mean/T_mean（1% 判据），")
        print("          必要时用 A_hash/H_hash/T_hash 做严格逐项比对。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
