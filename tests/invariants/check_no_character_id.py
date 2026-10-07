#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""铁律 1 · 运行期禁止角色名 / 角色 ID 判断。

规格：docs/qa/测试策略.md §2.1；出处 docs/gdd/core-gameplay-v3.1.md §11.1、AGENTS.md「硬性约束 1」。
行为逻辑必须是 f(性格四维, 透明度, 当前状态) 的纯函数 —— 角色差异只能来自 data/ 的开局种子。

扫描目录（默认）：scripts/systems/、scripts/npc/
违规样式：
  R1 角色名（data/characters/seeds.csv 的 alias，如「陈阳」）作为字符串字面量或裸标识符写进代码
  R1b 角色编号字面量（"01"…"24"）与 char/npc/actor 类词出现在同一行
  R2 角色类标识符与数字比较：char_id == 7、npc_index != 3、actor_id in [1, 2]
  R3 以角色编号命名的常量：CHAR_01、NPC_05、ACTOR_12

白名单：注释与文档串中的角色名（只是说明文字，不参与运行）→ 记 INFO，不计失败；
        data/ 加载层不在扫描范围内（本脚本只扫脚本目录）。

目标目录不存在 → [SKIP] 暂时没测到（骨架期正常，不是失败）。

用法：
    python tests/invariants/check_no_character_id.py
    python tests/invariants/check_no_character_id.py --dirs scripts/systems scripts/npc
    python tests/invariants/check_no_character_id.py --root <工程根>     # 自测夹具用
"""

from __future__ import print_function

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _common import (  # noqa: E402  (同目录公共模块)
    FAIL,
    PASS,
    SKIP,
    Report,
    guard,
    iter_sources,
    load_seed_table,
    mask_strings,
    rel,
    split_line,
)

DEFAULT_DIRS = ("scripts/systems", "scripts/npc")

CHAR_TOKENS = ("char", "npc", "actor", "role", "character", "student", "juese", "roleid")
CONST_ID = re.compile(r"\b(?:CHAR|NPC|ACTOR|STUDENT|ROLE)_\d+\b")
COMPARE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*(==|!=|in)\s*([^:\n]+)")


def _is_character_id_name(name):
    """char_id / npc_index / actor_id 这类「角色编号」标识符。"""
    low = name.lower()
    if not any(token in low for token in CHAR_TOKENS):
        return False
    return ("id" in low) or ("idx" in low) or ("index" in low) or low.endswith("_no")


def scan_source(files, aliases, seed_ids, root):
    fails, infos = [], []
    for path in files:
        loc = rel(path, root)
        for lineno, raw in enumerate(masked_lines(path), 1):
            code, comment, literals = split_line(raw)
            literal_hits = set()
            for lit in literals:
                text = lit.strip()
                if text in aliases:
                    fails.append((loc, lineno, "R1 角色名字面量", '"%s"' % text))
                    literal_hits.add(text)
                elif text in seed_ids and any(t in code.lower() for t in CHAR_TOKENS):
                    fails.append((loc, lineno, "R1b 角色编号字面量", '"%s"' % text))
            for alias in aliases:
                if alias in comment:
                    infos.append((loc, lineno, "注释/文档串中的角色名 %s" % alias))
                elif alias in literal_hits:
                    continue
                elif re.search(r"(?<![A-Za-z0-9_])" + re.escape(alias) + r"(?![A-Za-z0-9_])", code):
                    fails.append((loc, lineno, "R1 角色名出现在代码", alias))
            for match in CONST_ID.finditer(code):
                fails.append((loc, lineno, "R3 角色编号常量", match.group(0)))
            for match in COMPARE.finditer(code):
                if _is_character_id_name(match.group(1)):
                    if re.search(r"\bfor\s+$", code[:match.start()]):
                        continue      # `for x in char_ids` 不是「角色 ID 比较」
                    fails.append((loc, lineno, "R2 角色 ID 比较",
                                  "%s %s %s" % (match.group(1), match.group(2), match.group(3).strip())))
    return fails, infos


def masked_lines(path):
    """按行读取，先屏蔽三引号块 —— 保留行数的做法见 _common.mask_strings。"""
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return mask_strings(handle.read().replace("\r\n", "\n")).split("\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description="铁律 1：无角色名 / 角色 ID 判断")
    parser.add_argument("--dirs", nargs="*", default=list(DEFAULT_DIRS))
    parser.add_argument("--root", default=None, help="工程根目录（默认仓库根）")
    parser.add_argument("--max-print", type=int, default=25)
    args = parser.parse_args(argv)

    from _common import ROOT
    root = args.root or ROOT
    report = Report("铁律 1 · 无角色名 / 角色 ID 判断", "docs/qa/测试策略.md §2.1")

    report.section("扫描目标：%s" % "、".join(args.dirs))
    files, missing = iter_sources(args.dirs, root=root)
    for name in missing:
        report.add(SKIP, name, "目录不存在 —— 暂时没测到")

    # --- 哨兵自检：先在 fixtures/ 里证明扫描器真能抓到违规，再扫真实目录 ---
    report.section("哨兵自检（fixtures/ 里故意写的违规，必须被抓到）")
    fx_root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
    fx_files, _ = iter_sources(args.dirs, root=fx_root)
    fx_aliases, fx_ids = load_seed_table(root=fx_root)
    if not fx_files or not fx_aliases:
        report.add(SKIP, "哨兵自检", "fixtures/ 缺失或为空 —— 无法自检")
    else:
        fx_fails, _ = scan_source(fx_files, fx_aliases, fx_ids, fx_root)
        if fx_fails:
            report.add(PASS, "哨兵能抓到故意违规", "fixtures/ 命中 %d 条 —— 扫描器有效" % len(fx_fails))
        else:
            report.add(FAIL, "哨兵失效", "fixtures/ 里的故意违规一条都没抓到 —— 扫描逻辑有问题")

    if not files:
        report.add(SKIP, "全部目标", "没有任何 .gd 源文件 —— 暂时没测到（骨架期正常）")
        return report.finish()

    aliases, seed_ids = load_seed_table(root=root)
    if not aliases:
        report.add(SKIP, "data/characters/seeds.csv", "读不到角色种子表 —— 暂时没测到")
        return report.finish()

    report.note("源文件 %d 个；角色名 %d 个（来自 data/characters/seeds.csv）" % (len(files), len(aliases)))
    fails, infos = scan_source(files, aliases, seed_ids, root)

    if infos:
        report.section("INFO（注释里的角色名：说明性文字，不算违规）")
        report.extend("INFO", infos, max_print=5)
    if fails:
        report.section("违规明细")
        report.extend(FAIL, fails, max_print=args.max_print)
    else:
        report.add(PASS, "无角色名 / 角色 ID 判断", "已扫描 %d 个源文件" % len(files))
    return report.finish()


if __name__ == "__main__":
    sys.exit(guard(main))
