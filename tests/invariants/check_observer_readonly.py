#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""铁律 2 · 观察层只读：簇标签器与「孤立」标签不得回写任何数值。

规格：docs/qa/测试策略.md §2.2；出处 docs/gdd/core-gameplay-v3.1.md §10（观察层）、AGENTS.md「硬性约束 2」。

两条腿
------
A **静态**：扫 scripts/systems/observer/（以及 scripts/ 下任何 observer 相关 .gd），
  查矩阵写入模式 —— ``A[i][j] = …``、``+=``、``set_affinity( …``；命中即 [FAIL]。
B **运行时**：借用 tools/core_sim.py 的 Python 内核原型做**真实读写计数** ——
  跑 1 天 → 给 A / H / T / O 装上计数代理 → 遍历每个 viewer 调 ``ObserverLayer.view()``
  → 断言观察层更新期间的写入次数 **必须为 0**，并报告读数。
  这就是「统计观察层读写次数」那条要求：读数有值、写数必须为 0。
  （GDScript 内核落地后，把同一条断言搬进 GUT 用例即可，见 docs/qa/测试策略.md §2.2。）

目标缺失（observer 目录不存在 / core_sim 不能导入）→ [SKIP] 暂时没测到，不崩溃。

用法：
    python tests/invariants/check_observer_readonly.py
    python tests/invariants/check_observer_readonly.py --days 1 --seed 12345 --npc 8
"""

from __future__ import print_function

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _common import FAIL, PASS, SKIP, Report, guard, iter_sources, read_lines, rel, split_line  # noqa: E402

MATRIX_WRITE = re.compile(
    r"^\s*(?:self\.)?(?:A|H|T|H_deep|B_[A-Z]|belief)(?:\[[^\]]*\])+\s*(?:[+\-*/]?=)(?!=)"
)
SETTER_WRITE = re.compile(r"\bset_(?:affinity|hostility|trust|opacity|stress)\s*\(")
OBSERVER_HINT = re.compile(r"observer|观察层|ObserverLayer", re.IGNORECASE)


# --------------------------------------------------------------- 静态腿
def scan_observer_sources(root):
    """返回 (检查的文件, 违规明细, 缺失说明)。"""
    files, missing = iter_sources(("scripts/systems/observer",), root=root)
    if not files:
        # 退回：scripts/ 下任何「observer」相关文件
        all_files, _ = iter_sources(("scripts",), root=root)
        files = [f for f in all_files if "observer" in os.path.basename(f).lower()
                 or OBSERVER_HINT.search(_peek(f))]
    fails = []
    for path in files:
        for lineno, line in enumerate(read_lines(path), 1):
            code = split_line(line)[0]
            if MATRIX_WRITE.match(code):
                fails.append((rel(path, root), lineno, "观察层写入矩阵", code.strip()))
            elif SETTER_WRITE.search(code):
                fails.append((rel(path, root), lineno, "观察层调用写接口", code.strip()))
    return files, fails, missing


def _peek(path, limit=200000):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return handle.read(limit)
    except Exception:
        return ""


# ------------------------------------------------------------- 运行时腿
class Counter(object):
    def __init__(self):
        self.reads = 0
        self.writes = 0
        self.write_sites = []

    def summary(self):
        if self.write_sites:
            return "%d 次读 / %d 次写（写入点：%s）" % (
                self.reads, self.writes, "、".join(self.write_sites[:5]))
        return "%d 次读 / %d 次写" % (self.reads, self.writes)


class CountingRow(object):
    def __init__(self, data, counter, name):
        self._d, self._c, self._n = data, counter, name

    def __len__(self):
        self._c.reads += 1
        return len(self._d)

    def __getitem__(self, j):
        self._c.reads += 1
        return self._d[j]

    def __setitem__(self, j, value):
        self._c.writes += 1
        self._c.write_sites.append("%s[%d]" % (self._n, j))
        self._d[j] = value

    def __iter__(self):
        self._c.reads += 1
        for j in range(len(self._d)):
            yield self._d[j]


class CountingMatrix(object):
    def __init__(self, data, counter, name):
        self._d, self._c, self._n = data, counter, name

    def __len__(self):
        self._c.reads += 1
        return len(self._d)

    def __getitem__(self, i):
        self._c.reads += 1
        return CountingRow(self._d[i], self._c, "%s[%d]" % (self._n, i))

    def __setitem__(self, i, value):
        self._c.writes += 1
        self._c.write_sites.append("%s[%d]" % (self._n, i))
        self._d[i] = value

    def __iter__(self):
        # 产出计数的行对象：`for row in sim.A: row[j] = x` 这类迭代式写入也必须被记到
        self._c.reads += 1
        for i in range(len(self._d)):
            yield CountingRow(self._d[i], self._c, "%s[%d]" % (self._n, i))


class CountingVector(object):
    def __init__(self, data, counter, name):
        self._d, self._c, self._n = data, counter, name

    def __len__(self):
        self._c.reads += 1
        return len(self._d)

    def __getitem__(self, i):
        self._c.reads += 1
        return self._d[i]

    def __setitem__(self, i, value):
        self._c.writes += 1
        self._c.write_sites.append("%s[%d]" % (self._n, i))
        self._d[i] = value

    def __iter__(self):
        self._c.reads += 1
        return iter(self._d)


def runtime_probe(root, seed, npc, days):
    """跑 Python 内核原型 + 观察层，返回 (viewer 数, Counter, 备注)。"""
    tools_dir = os.path.join(root, "tools")
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)
    try:
        import core_sim  # noqa: WPS433  (延迟导入：拿不到就 SKIP)
    except Exception as exc:
        return None, None, "无法导入 tools/core_sim.py（%s: %s）" % (type(exc).__name__, exc)

    # 接口缺失 = SKIP；接口在但抛错 = 真异常（交给调用方判 FAIL），不要静默降级
    for attr in ("view", "cluster_tags", "isolated_tags"):
        if not hasattr(core_sim.ObserverLayer, attr):
            return None, None, "ObserverLayer 缺少 %s() 接口，观察层尚未实现" % attr

    sim = core_sim.Sim(seed=seed, npc_count=npc)
    for _ in range(days):
        sim.run_day()

    counter = Counter()
    sim.A = CountingMatrix(sim.A, counter, "A")
    sim.H = CountingMatrix(sim.H, counter, "H")
    sim.T = CountingMatrix(sim.T, counter, "T")
    sim.O = CountingVector(sim.O, counter, "O")

    layer = core_sim.ObserverLayer(sim)
    views = 0
    for viewer in range(sim.N):
        layer.view(viewer)      # = 观察层的一次「更新周期」
        views += 1
    return views, counter, "%s 内核 · seed=%d · npc=%d · %d 天" % (
        "core_sim", seed, npc, days)


def main(argv=None):
    parser = argparse.ArgumentParser(description="铁律 2：观察层只读")
    parser.add_argument("--root", default=None)
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--npc", type=int, default=8)
    parser.add_argument("--days", type=int, default=1)
    args = parser.parse_args(argv)

    from _common import ROOT
    root = args.root or ROOT
    report = Report("铁律 2 · 观察层只读（簇标签 / 孤立标签不回写）", "docs/qa/测试策略.md §2.2")

    # --- 哨兵自检：先在 fixtures/ 里证明静态扫描真能抓到写矩阵，再扫真实目录 ---
    report.section("哨兵自检（fixtures/ 里故意写回矩阵，必须被抓到）")
    fx_root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
    fx_files, fx_fails, _ = scan_observer_sources(fx_root)
    if not fx_files:
        report.add(SKIP, "哨兵自检", "fixtures/ 缺失或为空 —— 无法自检")
    elif fx_fails:
        report.add(PASS, "哨兵能抓到故意违规", "fixtures/ 命中 %d 条 —— 静态扫描有效" % len(fx_fails))
    else:
        report.add(FAIL, "哨兵失效", "fixtures/ 里的矩阵写回一条都没抓到 —— 静态扫描有问题")

    # --- A 静态腿 ---
    report.section("A. 静态：scripts/systems/observer/ 是否写入矩阵")
    files, fails, missing = scan_observer_sources(root)
    if not files:
        report.add(SKIP, "scripts/systems/observer", "观察层源码尚未落地 —— 暂时没测到")
    elif fails:
        report.extend(FAIL, fails)
    else:
        report.add(PASS, "观察层源码只读", "已扫描 %d 个文件：%s" % (
            len(files), "、".join(rel(f, root) for f in files)))

    # --- B 运行时腿 ---
    report.section("B. 运行时：观察层更新期间的读写计数（Python 内核原型）")
    views, counter, note = runtime_probe(root, args.seed, args.npc, args.days)
    if counter is None:
        report.add(SKIP, "运行时读写计数", note)
    else:
        report.note("口径：ObserverLayer.view(viewer) 视为一次观察层更新；%s" % note)
        report.note("共 %d 个 viewer 完成更新" % views)
        if counter.writes:
            report.add(FAIL, "观察层写回数值",
                       counter.summary())
        else:
            report.add(PASS, "观察层零写入", counter.summary())
            report.note("读数是观察层的正常输入（真值矩阵经透明度过滤）；写数必须恒为 0。")
    return report.finish()


if __name__ == "__main__":
    sys.exit(guard(main))
