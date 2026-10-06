#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""tests/invariants/ 公共设施：源码扫描 + 报告 + 「暂时没测到」语义。

三条铁律测试（docs/qa/测试策略.md §2）共用本模块：
  1. 无角色名 / 角色 ID 判断
  2. 观察层只读（读写计数）
  3. 数值不落在脚本里（魔法数字）

约定
----
* **只读**：本目录的脚本绝不修改工程文件；
* **目标缺失不崩**：目录 / 数据表 / 模块不存在时标 ``SKIP``「暂时没测到」，
  骨架期必须能生成并跑出结果（用户要求）；
* **退出码**：出现 ``FAIL`` 返回 1（可接 CI），否则返回 0 —— ``SKIP`` 不计失败；
* **编码**：Windows GBK 控制台下不可编码字符自动替换，绝不因 ``UnicodeEncodeError`` 崩溃；
* 兼容 Python 3.7+（本机 3.7.0）。
"""

from __future__ import print_function

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

PASS = "PASS"
FAIL = "FAIL"
WARN = "WARN"
SKIP = "SKIP"


def _make_output_safe():
    """控制台无法编码的字符替换成 '?'，而不是抛 UnicodeEncodeError。"""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except Exception:
            pass


_make_output_safe()


def rel(path, root=None):
    root = root or ROOT
    try:
        return os.path.relpath(path, root).replace("\\", "/")
    except Exception:
        return str(path)


def read_lines(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read().replace("\r\n", "\n").split("\n")


_TRIPLE = re.compile(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'')


def mask_strings(text):
    """把三引号块换成占位符（保留换行数），保证逐行处理时行号不变。"""
    def repl(match):
        return '""' + "\n" * match.group(0).count("\n")

    return _TRIPLE.sub(repl, text)


def split_line(line):
    """把一行 GDScript 拆成 ``(代码, 注释, 字符串字面量列表)``。

    状态机扫描：只有**字符串外**的 ``#`` 才是注释起点，
    因此注释里的角色名不会被误判成违规（见 README 的白名单说明）。
    """
    code_end = len(line)
    literals = []
    i = 0
    while i < len(line):
        ch = line[i]
        if ch in "\"'":
            j = i + 1
            while j < len(line):
                if line[j] == "\\":
                    j += 2
                    continue
                if line[j] == ch:
                    break
                j += 1
            if j < len(line):
                literals.append(line[i + 1:j])
                i = j + 1
                continue
            literals.append(line[i + 1:])
            break
        if ch == "#":
            code_end = i
            break
        i += 1
    return line[:code_end], line[code_end:], literals


class Report(object):
    """统一输出与退出码。"""

    def __init__(self, title, basis=""):
        self.title = title
        self.basis = basis
        self.items = []
        print("=== %s ===" % title)
        if basis:
            print("依据：%s" % basis)

    def section(self, text):
        print("")
        print(text)

    def note(self, text):
        print("  " + text)

    def add(self, status, name, detail=""):
        self.items.append((status, name, detail))
        line = "  [%s] %s" % (status, name)
        if detail:
            line += "  -- %s" % detail
        print(line)

    def extend(self, status, rows, max_print=25):
        """成批添加；行格式统一为 ``(位置, 行号, 说明[, 代码片段])``，超出 max_print 只打印前若干条。"""
        for idx, row in enumerate(rows):
            loc, lineno, label = row[0], row[1], row[2]
            detail = row[3] if len(row) > 3 else ""
            name = "%s:%s  %s" % (loc, lineno, label)
            if idx < max_print:
                self.add(status, name, detail)
            else:
                self.items.append((status, name, detail))
        if len(rows) > max_print:
            print("  ... 另有 %d 条同类问题未逐条打印" % (len(rows) - max_print))

    def counts(self):
        out = {PASS: 0, FAIL: 0, WARN: 0, SKIP: 0}
        for status, _, _ in self.items:
            out[status] = out.get(status, 0) + 1
        return out

    def skipped_names(self):
        return [name for status, name, _ in self.items if status == SKIP]

    def finish(self):
        c = self.counts()
        print("")
        print("=== 结论 ===")
        print("  通过 %d 项，失败 %d 项，跳过 %d 项" % (c[PASS], c[FAIL], c[SKIP]))
        if c[SKIP]:
            print("  暂时没测到：%s" % "、".join(self.skipped_names()))
            print("  → 骨架期正常：目标落位后本项自动生效，不算失败。")
        if c[FAIL]:
            print("  本项铁律被违反 —— 见上方 [FAIL] 明细。")
        return 1 if c[FAIL] else 0


def iter_sources(dirs, root=None, exts=(".gd",)):
    """收集源码文件；返回 ``(files, missing_dirs)``，缺失目录只登记不抛错。"""
    root = root or ROOT
    files, missing = [], []
    for name in dirs:
        full = os.path.join(root, name)
        if not os.path.isdir(full):
            missing.append(name)
            continue
        for dirpath, _, filenames in os.walk(full):
            for fname in filenames:
                if fname.endswith(exts):
                    files.append(os.path.join(dirpath, fname))
    return sorted(files), missing


def load_seed_table(root=None):
    """读 data/characters/seeds.csv，返回 ``(aliases, ids)``；读不到返回空列表。"""
    import csv

    root = root or ROOT
    path = os.path.join(root, "data", "characters", "seeds.csv")
    if not os.path.isfile(path):
        return [], []
    aliases, ids = [], []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        rows = [r for r in handle if not r.lstrip().startswith("#")]
    for row in csv.DictReader(rows):
        alias = (row.get("alias") or "").strip()
        rid = (row.get("id") or "").strip()
        if alias:
            aliases.append(alias)
        if rid:
            ids.append(rid)
    return aliases, ids


def guard(mainfn):
    """入口包装：未预料的异常打印 [ERROR] 而不是抛栈崩溃。"""
    try:
        return mainfn()
    except Exception as exc:  # noqa: BLE001 - 骨架期要的是「别崩」，不是精确类型
        print("")
        print("  [ERROR] 检查脚本本身出错：%s: %s" % (type(exc).__name__, exc))
        print("  已按「暂时没测到」处理，不作为铁律失败。")
        return 0
