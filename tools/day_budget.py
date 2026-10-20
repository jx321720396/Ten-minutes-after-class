#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""一天收支预算表（只读 data/，不改任何数值）。

回答三件事（不改数值、只算账）：
  1. 老师完全不操作的一天，班级动力／压力／收益会走到哪里；
  2. 老师一天最多能给出多少动力，够把多少人推过 30（自由）／60（学习）；
  3. 第八天「目标均分」（`exam_target_mean_1`，2026-10-20 起 490）在算术上需要多少人全天学习，与老师能给的数量差几倍。

所有数值都从 `data/rules/*.csv` 读，脚本里不写死参数；口径见主文档 §5.1／§5.2 与
`docs/production/老师版待确认参数.md`。运行：`python tools/day_budget.py`
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core_sim import default_npc_count, load_params, load_table  # noqa: E402


def main():
    npc = default_npc_count()
    psyche = load_params("rules/psyche.csv")
    acts = load_params("rules/activities.csv")
    timing = load_params("rules/teacher_commands.csv")
    exam = load_params("rules/exam.csv")
    phases = load_table("rules/phases.csv")

    break_ticks = sum(int(r["tick_count"]) for r in phases if r["kind"] == "break")
    class_ticks = sum(int(r["tick_count"]) for r in phases if r["kind"] == "class")
    day_ticks = break_ticks + class_ticks

    study_cost_rate = float(acts["study_vitality_cost"]) / float(acts["study_settle_seconds"])
    study_gain_rate = float(acts["study_gain"]) / float(acts["study_settle_seconds"])
    play_relief_rate = float(acts["play_relief"]) / float(acts["play_settle_seconds"])
    play_gain_rate = float(acts["play_gain"]) / float(acts["play_settle_seconds"])
    # 2026-10-17：游戏状态回复动力（与学习消耗对称），让动力能自动循环。
    play_vitality_rate = float(acts["play_vitality_gain"]) / float(acts["play_settle_seconds"])
    leisure_rate = float(acts["relief_per_unit"]) / float(acts["unit_seconds"])

    play_threshold = float(psyche["vitality_play_threshold"])
    study_threshold = float(psyche["vitality_study_threshold"])
    # 2026-10-17：跨天压力保留 −20，动力不再统一扣减（保留前日剩余值），故此项恒为 0。
    carry_vitality = 0.0
    carry_stress = float(psyche["carry_stress_cut"])

    # —— 单日：全天学习 / 全天游戏 / 全天自由娱乐（各自只在允许的相位结算）——
    study_day_vitality = study_cost_rate * day_ticks
    study_day_gain = study_gain_rate * day_ticks
    play_day_relief = play_relief_rate * break_ticks          # 游戏只在课间结算
    play_day_gain = play_gain_rate * break_ticks
    play_day_vitality = play_vitality_rate * break_ticks      # 游戏回动力（2026-10-17）
    leisure_day_relief = leisure_rate * break_ticks
    leisure_day_vitality = leisure_day_relief                 # 自由娱乐减压按一般联动扣动力

    # —— 老师一日预算 ——
    chat_seconds = float(timing["office_chat_seconds"])
    per_break_meetings = int(break_ticks / 3.0 / chat_seconds)  # 每课间可开会面次数（三段等长）
    meetings_per_day = per_break_meetings * 3
    praise = float(acts["office_praise_vitality"])
    scold = float(acts["office_scold_stress"])                 # 训斥：压力 +N，动力联动 +N
    comfort = float(acts["office_comfort_stress"])
    best_per_meeting = max(praise, scold)
    vitality_ceiling = meetings_per_day * best_per_meeting

    # —— 阈值需求 ——
    to_free = play_threshold
    to_study = study_threshold
    study_sustain = study_day_vitality + carry_vitality        # 维持全天学习的每日动力支出

    # —— 扩散：邻座学习涓流 ——
    drip = float(acts["neighbor_study_stress"])
    break_count = sum(1 for r in phases if r["kind"] == "break")
    drip_day = drip * break_count                              # 每邻座每天能带来的压力（联动同值动力）
    max_neighbors = 4                                          # 前后左右

    # —— 第八天目标可达性 ——
    init_mean = (float(psyche["grade_init_min"]) + float(psyche["grade_init_max"])) / 2.0
    target = float(exam.get("exam_target_mean_1", exam.get("exam_target_mean", 490.0)))
    exam_day = int(exam["exam_day_1"])
    need_total = (target - init_mean) * npc
    need_daily = need_total / exam_day
    # 设 x 人全天学习、其余全天游戏：x*study_gain + (npc-x)*play_gain = need_daily
    gain_per_studier = study_gain_rate * day_ticks
    gain_per_player = play_gain_rate * break_ticks
    x = (need_daily - npc * gain_per_player) / (gain_per_studier - gain_per_player)
    x_vitality = x * study_sustain
    gap = x_vitality / vitality_ceiling if vitality_ceiling else float("inf")

    print("=== 一天收支预算（只读 data/，不改数值）===")
    print("班级人数 %d ｜ 一天 %d s（课间 %d s ×3 + 上课 %d s ×2）" % (
        npc, day_ticks, break_ticks // break_count, class_ticks // 2))
    print("")
    print("[1] 单位速率（来自 activities.csv）")
    print("  学习：收益 +%.2f/s，动力 %+.2f/s（每 %d s 一单位）" % (
        study_gain_rate, -study_cost_rate, int(acts["study_settle_seconds"])))
    print("  游戏：收益 %+.2f/s，压力 %+.2f/s，动力 %+.2f/s（只在课间结算）" % (
        play_gain_rate, -play_relief_rate, play_vitality_rate))
    print("  自由娱乐：压力 %+.2f/s，动力 %+.2f/s（按一般联动）" % (
        -leisure_rate, -leisure_rate))
    print("")
    print("[2] 一整天待在某一状态的收支（不含老师与事件）")
    print("  全天学习：收益 %+.0f，动力 %+.0f，跨天再 %+.0f → 净动力 %+.0f" % (
        study_day_gain, -study_day_vitality, -carry_vitality,
        -study_day_vitality - carry_vitality))
    print("  全天游戏：收益 %+.0f，压力 %+.0f，动力 %+.0f（2026-10-17 起回动力）" % (
        play_day_gain, -play_day_relief, play_day_vitality))
    print("  全天自由娱乐：压力 %+.0f，动力 %+.0f，跨天再 %+.0f" % (
        -leisure_day_relief, -leisure_day_vitality, -carry_vitality))
    print("  压力跨天再减 %.0f" % carry_stress)
    print("")
    print("[3] 老师一日预算（办公室会面 %d s/人次，同时只 1 人）" % int(chat_seconds))
    print("  每课间可会面 %d 人次 → 一天上限 %d 人次（不含调座位 %d s、调解 %d s 的占用）" % (
        per_break_meetings, meetings_per_day,
        int(timing["seat_change_seconds"]), int(timing["mediate_seconds"])))
    print("  单人次效果：表扬 动力 %+.0f；训斥 压力 %+.0f／动力 %+.0f；安抚 压力 %+.0f／动力 %+.0f" % (
        praise, scold, scold, comfort, comfort))
    print("  动力输入上限（全用于最强项）= %d 人次 × %.0f = %.0f/天" % (
        meetings_per_day, best_per_meeting, vitality_ceiling))
    print("")
    print("[4] 阈值与维持成本")
    print("  进自由（动力 ≥%.0f）：+%.0f → 表扬 %.1f 次 或 训斥 %.1f 次" % (
        to_free, to_free, to_free / praise, to_free / scold))
    print("  进学习（动力 ≥%.0f）：+%.0f → 表扬 %.1f 次 或 训斥 %.1f 次" % (
        to_study, to_study, to_study / praise, to_study / scold))
    print("  维持 1 人全天学习：动力 %.0f + 跨天 %.0f = %.0f/天 → 训斥 %.1f 人次" % (
        study_day_vitality, carry_vitality, study_sustain, study_sustain / scold))
    print("  老师上限能维持的全天学习人数：%.0f ÷ %.0f = %.1f 人（且不做其它操作）" % (
        vitality_ceiling, study_sustain, vitality_ceiling / study_sustain))
    print("  自动循环：全天游戏回 %.0f 动力，全天学习耗 %.0f → 需 %.1f 天游戏补 1 天学习" % (
        play_day_vitality, study_day_vitality, study_day_vitality / max(1.0, play_day_vitality)))
    print("")
    print("[5] 扩散通道（邻座学习涓流，每课间末一次 ×%d 段）" % break_count)
    print("  每名学习邻座带来 压力 %+.0f／天（动力按联动同值）" % drip_day)
    print("  单人最多 %d 个正交邻座 → 最多 动力 %+.0f/天" % (max_neighbors, drip_day * max_neighbors))
    print("  与「维持全天学习 %.0f/天」相比：%.0f < %.0f，%s" % (
        study_sustain, drip_day * max_neighbors, study_sustain,
        "单靠涓流无法自持" if drip_day * max_neighbors < study_sustain else "可自持"))
    print("")
    print("[6] 第八天目标可达性（初始均分 %.0f → 目标 %.0f，第 %d 天）" % (
        init_mean, target, exam_day))
    print("  班级总分需 %+.0f → 每日净 %+.1f 收益" % (need_total, need_daily))
    print("  全日制学习 %.0f/人/天、全天游戏 %+.0f/人/天 → 需要 %.1f 人全天学习" % (
        gain_per_studier, gain_per_player, x))
    print("  这些人的动力需求 %.0f/天 vs 老师上限 %.0f/天 → 缺口 %.1f 倍" % (
        x_vitality, vitality_ceiling, gap))
    print("")
    print("[7] 其它已定数值（本次未计入上限，但会改变结论）")
    print("  去教室：每课间首次全班压力 %+.0f → 全班动力 %+.0f/人/天（共 %.0f）" % (
        float(acts["teacher_enter_stress"]), float(acts["teacher_enter_stress"]) * break_count,
        float(acts["teacher_enter_stress"]) * break_count * npc))
    print("  全班训斥：全班压力 %+.0f（动力联动同值），内核已有 scold_class，但无耗时、无次数上限、"
          "且 UI 未接线 —— 一旦接线会直接推翻上表的「老师时间预算」" % float(acts["class_scold_stress"]))
    print("  崩溃恢复：次日压力减 %.0f、动力减 %.0f（替代普通跨天）" % (
        float(psyche["breakdown_rest_stress_cut"]), float(psyche["breakdown_rest_vitality_cut"])))
    print("  考前 %+.0f 压力／考后 %+.0f 压力（考试日）" % (
        float(exam["pre_exam_stress_bonus"]), float(exam["post_exam_stress_cut"])))
    print("")
    print("[8] 缺口位置（只描述，不改数值）")
    print("  · 学习净支出 %.0f/天，而单人涓流上限 %+.0f/天：学习者必须靠老师持续补差 %.0f/天" % (
        study_sustain, drip_day * max_neighbors, study_sustain - drip_day * max_neighbors))
    print("  · 老师动力上限 %.0f/天只能维持 %.1f 人学习，目标需要 %.1f 人 → 差 %.1f 倍" % (
        vitality_ceiling, vitality_ceiling / study_sustain, x, gap))
    print("  · 游戏减压 %.2f/s 使不干预时压力恒 0：崩溃／爆发／风险链拿不到输入" % play_relief_rate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
