#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""逐 tick 对拍：Python 内核 ↔ GDScript 内核（误差 ≤ 1%）。

对应冲刺计划 D6–D7「对拍基建」与 **D8–D9 硬闸门**：
> Python 与 GDScript 同种子局关键指标（饱和度 / 均值 / 分化 / 爆发次数）误差 ≤ 1%

口径
----
* 基准（reference）：Python 内核原型 `tools/core_sim.py` 导出的逐 tick 序列；
* 对拍（candidate）：GDScript 内核经 `tests/integration/export_ticks_gd.gd` 导出的同种子序列；
* 判据：每个 tick 的 `A_mean / H_mean / T_mean / O_mean / stress_mean` 相对误差 ≤ `--tol`（默认 1%）；
  `*_hash` 只作参考打印（浮点末位差异不应判死）。

现状
----
GDScript 内核（`scripts/core/`）尚未移植，所以对拍对象缺失 → 本脚本明确 **SKIP**。
但它**永远保留一条自检**：拿「故意偏 5%」的假数据喂给比对逻辑，必须判红 ——
否则对拍器本身坏了却显示「通过」，比不测更糟。

用法
----
    python tests/integration/test_tick_parity.py
    python tests/integration/test_tick_parity.py --days 3 --seed 12345 --npc 8 --tol 0.01
    python tests/integration/test_tick_parity.py --godot "E:/godot/Godot_v4.7.2-stable_win64_console.exe"
"""

from __future__ import print_function

import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tests", "invariants"))

from _common import FAIL, PASS, SKIP, Report, guard  # noqa: E402

KERNEL = os.path.join(ROOT, "scripts", "core", "term.gd")
GD_EXPORTER = os.path.join(ROOT, "tests", "integration", "export_ticks_gd.gd")
GODOT_PATH_FILE = os.path.join(ROOT, ".godot_path")

NUMERIC_FIELDS = ("A_mean", "H_mean", "T_mean", "O_mean", "stress_mean")
HASH_FIELDS = ("A_hash", "H_hash", "T_hash")


# ------------------------------------------------------------------ 比对逻辑
def compare_series(reference, candidate, tol):
    """逐 tick 比对数值字段的相对误差。返回 ``(ok, problems)``。"""
    problems = []
    if len(reference) != len(candidate):
        problems.append("tick 数不一致：基准 %d vs 对拍 %d" % (len(reference), len(candidate)))
        return False, problems
    for ref_row, cand_row in zip(reference, candidate):
        for field in NUMERIC_FIELDS:
            a = float(ref_row.get(field, 0.0))
            b = float(cand_row.get(field, 0.0))
            rel = abs(a - b) / max(abs(a), 1e-9)
            if rel > tol:
                problems.append("tick=%s %s：基准 %.3f vs 对拍 %.3f（相对差 %.2f%%）" % (
                    ref_row.get("tick"), field, a, b, rel * 100.0))
                if len(problems) >= 10:
                    problems.append("... 仅显示前 10 条")
                    return False, problems
    return (not problems), problems


def self_check(tol):
    """哨兵：比对逻辑必须能判出「偏 5%」，且不能误杀「偏 0.4%」。"""
    base = {"tick": 1, "A_mean": 25.0, "H_mean": 5.0, "T_mean": 27.0,
            "O_mean": 46.0, "stress_mean": 0.75}
    near = [dict(base, A_mean=25.1)]      # 0.4% —— 应通过
    far = [dict(base, A_mean=26.25)]      # 5.0% —— 应判红
    tolerates_small, _ = compare_series([base], near, tol)
    _, far_problems = compare_series([base], far, tol)
    return tolerates_small, bool(far_problems)


# ------------------------------------------------------------------ 执行环境
def find_godot(explicit):
    if explicit:
        return explicit
    env = os.environ.get("GODOT_BIN")
    if env:
        return env
    if os.path.isfile(GODOT_PATH_FILE):
        with open(GODOT_PATH_FILE, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                text = line.strip()
                if text and not text.startswith("#"):
                    return text
    return ""


def load_reference(days, seed, npc):
    import export_ticks  # 同目录离线脚本：hook 内核 tick 导出序列
    _sim, rows = export_ticks.collect(seed, npc, days)
    return rows


def run_gdscript_export(godot, days, seed, npc, out_path):
    cmd = [godot, "--headless", "--path", ROOT, "--script", GD_EXPORTER,
           "--", "--days=%d" % days, "--seed=%d" % seed, "--npc=%d" % npc,
           "--out=%s" % out_path]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output, _ = proc.communicate()
    text = output.decode("utf-8", "replace") if output else ""
    if proc.returncode != 0:
        return None, "Godot 导出失败（exit=%d）：%s" % (proc.returncode, text[-300:])
    if not os.path.isfile(out_path):
        return None, "Godot 未产出导出文件：%s" % out_path
    rows = []
    with open(out_path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows, text


# ------------------------------------------------------------------ 入口
def main(argv=None):
    parser = argparse.ArgumentParser(description="逐 tick 对拍：Python 内核 ↔ GDScript 内核")
    parser.add_argument("--days", type=int, default=3)
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--npc", type=int, default=8)
    parser.add_argument("--tol", type=float, default=0.01, help="相对误差上限（默认 1% = 0.01）")
    parser.add_argument("--godot", default=None)
    parser.add_argument("--keep", default=None, help="GDScript 导出文件路径（默认临时文件）")
    args = parser.parse_args(argv)

    report = Report("逐 tick 对拍：Python ↔ GDScript（误差 ≤ %.1f%%）" % (args.tol * 100.0),
                    "docs/production/聚光灯21天冲刺计划.md D8–D9 硬闸门")

    # --- ① 哨兵：比对逻辑必须有效 ---
    report.section("哨兵自检（对拍逻辑必须能判出偏差，且不误杀微小差异）")
    tolerates_small, catches_large = self_check(args.tol)
    if not tolerates_small:
        report.add(FAIL, "哨兵误杀", "0.4% 的偏差被判为超标 —— 阈值逻辑有问题")
    if not catches_large:
        report.add(FAIL, "哨兵失效", "5% 的偏差竟然判为通过 —— 比对逻辑坏了")
    if tolerates_small and catches_large:
        report.add(PASS, "对拍逻辑自检", "0.4% 通过、5% 判红，符合预期")

    # --- ② 对拍对象是否就位 ---
    report.section("对拍对象")
    godot = find_godot(args.godot)
    if not os.path.isfile(KERNEL):
        report.add(SKIP, "GDScript 内核", "scripts/core/term.gd 尚未落地（冲刺计划 D8–D9）—— 暂时没测到")
    if not godot:
        report.add(SKIP, "Godot 可执行文件", "未指定（--godot / $GODOT_BIN / .godot_path）—— 暂时没测到")
    elif not os.path.isfile(GD_EXPORTER):
        report.add(SKIP, "GDScript 导出入口", "tests/integration/export_ticks_gd.gd 缺失")

    if not os.path.isfile(KERNEL) or not godot or not os.path.isfile(GD_EXPORTER):
        report.note("内核与 Godot 就位后，本脚本会自动开始逐 tick 对拍，无需改动调用方式。")
        return report.finish()

    # --- ③ 真对拍 ---
    report.section("逐 tick 比对")
    reference = load_reference(args.days, args.seed, args.npc)
    report.note("基准（Python 内核原型）：%d 个 tick" % len(reference))

    out_path = args.keep or os.path.join(ROOT, "tools", "out", "ticks_gd.jsonl")
    directory = os.path.dirname(out_path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    candidate, log = run_gdscript_export(godot, args.days, args.seed, args.npc, out_path)
    if candidate is None:
        report.add(FAIL, "GDScript 导出", log)
        return report.finish()

    report.note("对拍（GDScript 内核）：%d 个 tick" % len(candidate))
    ok, problems = compare_series(reference, candidate, args.tol)
    if ok:
        report.add(PASS, "逐 tick 一致", "%d 个 tick 全部在 %.1f%% 以内" % (
            len(reference), args.tol * 100.0))
    else:
        for problem in problems:
            report.add(FAIL, problem)
    tail = log.strip().splitlines()
    if tail:
        report.note("Godot 输出摘要：%s" % tail[-1])
    return report.finish()


if __name__ == "__main__":
    sys.exit(guard(main))
