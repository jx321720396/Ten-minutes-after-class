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
    # Dekker 拆半常数（scripts/core/sim_core.gd 的 _mul_err，2^27 + 1）：
    # 浮点误差补偿的算法结构常量，非游戏规则。
    "134217729.0",

    "5", "6", "7", "11", "15", "18", "30", "32",
    # 统一影响公式 / NPC 决策 / 信念矩阵 / FNV 哈希的结构常量
    # （scripts/core/sim_core.gd，与 tools/core_sim.py 参考实现逐字一致，待标定迁入 data/）：
    # 分段函数断点（m_state 40/70/90、观测档 80/50/20）、分段系数、软饱和兜底、性格夹紧上界、
    # 关系/观测归一化、NV 哈希乘子与归一化、噪声/从众/偏差/标签效应的阈值与量级。
    "-999", "3",
    "40.0", "70.0", "90.0", "80.0", "20.0", "50.0",
    "1.5", "0.75", "1.2", "25.0",
    "2.0", "0.05", "14.0", "0.4", "0.72", "10.0",
    "2166136261", "16777619", "10000", "10000.0",
    # D10 行为决策 / 观察层的结构常量（与 tools/core_sim.py 参考实现逐字一致，待标定迁入 data/）：
    # 软性决策权重（搭话收益 3.0 / 外向修正 0.3 / 观测学习率 0.3+0.7 / 温度下限 & 成功率精度 0.01）、
    # 抽样上限 4、举报敌对回落 5.0、簇强连接阈值 60.0、孤立差 15.0、打闹外向偏移 30.0、
    # 睡觉整段占用的 busy_until 哨兵 1000000000。
    "3.0", "0.3", "0.7", "0.01", "4", "5.0", "60.0", "15.0", "30.0", "1000000000",
    # scripts/core/sim_core.gd：difficulty 未命中时的**兜底 NPC 数**（2026-10-07 由 CI 首次暴露）。
    # ⚠️ 这是「待迁 data/」的临时白名单 —— 兜底值本就该来自 data/rules/difficulty.csv，
    #    标定时与上面同类常量一并迁走。
    "8",
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

    # --- 哨兵自检：先在 fixtures/ 里证明扫描器真能抓到违规，再扫真实目录 ---
    report.section("哨兵自检（fixtures/ 里故意写的违规，必须被抓到）")
    fx_root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
    fx_files, _ = iter_sources(dirs, root=fx_root)
    if not fx_files:
        report.add(SKIP, "哨兵自检", "fixtures/ 缺失或为空 —— 无法自检")
    else:
        fx_hits = scan_source(fx_files, fx_root)
        if fx_hits:
            report.add(PASS, "哨兵能抓到故意违规", "fixtures/ 命中 %d 条 —— 扫描器有效" % len(fx_hits))
        else:
            report.add(FAIL, "哨兵失效", "fixtures/ 里的故意违规一条都没抓到 —— 扫描逻辑有问题")

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
