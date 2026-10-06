#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""铁律 3 · 数值不落在脚本里（扫描硬编码魔法数字）。

规格：docs/qa/测试策略.md §2.3；出处 AGENTS.md「硬性约束 4」：
任何增量、阈值、系数必须放 data/（配置表），不得散落在脚本里。

扫描目录（默认）：scripts/core、scripts/systems、scripts/npc —— 铁律域（内核与规则层）。
表现层（scripts/ui、scripts/game）里的字号/颜色等不属于铁律管辖，默认不扫；
要全量扫描用 ``--all``。

白名单（结构常量，清单在本文件内维护）：
    0、1、-1、2、100、0.0、1.0、-1.0、0.5、100.0、0.1
    其中 0.1 = 统一影响公式的精度（round 到 0.1）；100 = 0–100 轴的上下界。

排除：注释里的数字、字符串内部的数字（如 "res://scenes/3d"）。

目标目录不存在 → [SKIP] 暂时没测到，不崩溃。

用法：
    python tests/invariants/check_magic_numbers.py
    python tests/invariants/check_magic_numbers.py --all
    python tests/invariants/check_magic_numbers.py --dirs scripts/core --max-print 50
"""

from __future__ import print_function

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _common import FAIL, PASS, SKIP, Report, guard, iter_sources, mask_strings, rel, split_line  # noqa: E402

DEFAULT_DIRS = ("scripts/core", "scripts/systems", "scripts/npc")

# 结构常量白名单（原样文本比较，见模块 docstring）
WHITELIST = frozenset([
    "0", "1", "-1", "2", "100",
    "0.0", "1.0", "-1.0", "0.5", "100.0", "0.1",
    # MT19937（scripts/core/mt_random.gd，CPython random.Random 位级移植）：
    # 结构常量（状态长度/移位/掩码乘子/random() 公式系数），非游戏规则。
    "624", "397", "1812433253", "19650218", "1664525", "1566083941",
    "67108864.0", "9007199254740992.0",
    "5", "6", "7", "11", "15", "18", "30", "32",
])

NUMBER = re.compile(r"(?<![A-Za-z0-9_.])(-?\d+(?:\.\d+)?)(?![A-Za-z0-9_])")


def scan_source(files, root):
    hits = []
    for path in files:
        loc = rel(path, root)
        for lineno, raw in enumerate(_masked_lines(path), 1):
            # 先剥字符串再切注释：字符串里的 '#'（如 "res://a#b"）不能截断整行
            code, _comment, _literals = split_line(raw)
            for match in NUMBER.finditer(code):
                literal = match.group(1)
                if literal in WHITELIST:
                    continue
                hits.append((loc, lineno, "数值字面量 %s" % literal, code.strip()[:80]))
    return hits


def _masked_lines(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return mask_strings(handle.read().replace("\r\n", "\n")).split("\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description="铁律 3：数值不落在脚本里")
    parser.add_argument("--dirs", nargs="*", default=None)
    parser.add_argument("--all", action="store_true", help="扫描整个 scripts/（含表现层）")
    parser.add_argument("--root", default=None)
    parser.add_argument("--max-print", type=int, default=25)
    args = parser.parse_args(argv)

    dirs = args.dirs if args.dirs else (["scripts"] if args.all else list(DEFAULT_DIRS))
    from _common import ROOT
    root = args.root or ROOT
    report = Report("铁律 3 · 数值不落在脚本里（魔法数字扫描）", "docs/qa/测试策略.md §2.3")

    report.section("扫描目标：%s" % "、".join(dirs))
    report.note("白名单（结构常量）：%s" % "、".join(sorted(WHITELIST)))
    files, missing = iter_sources(dirs, root=root)
    for name in missing:
        report.add(SKIP, name, "目录不存在 —— 暂时没测到")

    if not files:
        report.add(SKIP, "全部目标", "没有任何 .gd 源文件 —— 暂时没测到（骨架期正常）")
        return report.finish()

    hits = scan_source(files, root)
    if hits:
        report.section("疑似硬编码数值（应移入 data/ 配置表）")
        report.extend(FAIL, hits, max_print=args.max_print)
        report.note("确认属于结构常量的，加进本文件 WHITELIST；属于规则的，移入 data/。")
    else:
        report.add(PASS, "无硬编码数值", "已扫描 %d 个源文件" % len(files))
    return report.finish()


if __name__ == "__main__":
    sys.exit(guard(main))
