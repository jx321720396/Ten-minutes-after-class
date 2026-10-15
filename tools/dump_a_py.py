#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""临时诊断：dump 指定 tick 的完整 A 矩阵（0.1 精度，逗号分隔），与内核 headless_dump_a.gd 对齐。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import core_sim

tick_target = int(sys.argv[1]) if len(sys.argv) > 1 else 11
seed = int(sys.argv[2]) if len(sys.argv) > 2 else 12345
npc = int(sys.argv[3]) if len(sys.argv) > 3 else 16

sim = core_sim.Sim(seed=seed, npc_count=npc)
orig = sim.tick


def hook():
    orig()
    if sim.global_tick == tick_target:
        print(",".join("%.1f" % v for row in sim.A for v in row))


sim.tick = hook
sim.run_day()
