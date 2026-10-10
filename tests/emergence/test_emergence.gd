extends GutTest
## 涌现验收骨架：主文档第十六章「涌现现象对照表」的 13 条现象。
##
## 现状：GDScript 内核（`scripts/core/`）与行为层尚未移植（冲刺计划 D8–D10），
## 因此逐条以 `pending()` 占位 —— **不是通过，是明确的「待实现」**。
## 每条用例的现象、机制来源与验收观测点见同目录 `cases.md`。
##
## 内核落地后：把 `pending(...)` 换成真实断言（固定种子 + 操作序列 → 机制指标），
## 并保证「关掉该机制时用例会失败」——否则测的是脚本，不是涌现。

const PENDING_REASON := "待 GDScript 内核落地（scripts/core/、scripts/npc/、scripts/systems/）后接入真实断言，见 cases.md"


func test_01_open_student_fades_after_repeated_teasing() -> void:
	pending(PENDING_REASON + " —— 现象：本来开朗的学生被反复调侃后变成小透明")


func test_02_small_groups_form_spontaneously() -> void:
	pending(PENDING_REASON + " —— 现象：小团体自发抱团")


func test_03_wronged_student_bursts_after_pressure_builds() -> void:
	pending(PENDING_REASON + " —— 现象：受委屈的同学积攒情绪后突然爆发")


func test_04_note_diverges_per_recipient() -> void:
	pending(PENDING_REASON + " —— 现象：纸条让人对被说者态度分化（同一条纸条给态度不同的收件人）")


func test_05_group_member_leaves_on_internal_conflict() -> void:
	pending(PENDING_REASON + " —— 现象：小团体内部矛盾成员主动脱离")


func test_06_player_is_isolated_by_note() -> void:
	pending(PENDING_REASON + " —— 现象：玩家被纸条误伤导致被孤立")


func test_07_introvert_starts_chat_when_stress_low() -> void:
	pending(PENDING_REASON + " —— 现象：内向学生在压力低时意外主动开口闲聊")


func test_08_whistleblower_is_ostracized() -> void:
	pending(PENDING_REASON + " —— 现象：泄密者被全班疏远")


func test_09_one_report_splits_the_class() -> void:
	pending(PENDING_REASON + " —— 现象：一次举报导致班级分裂成两派")


func test_10_comfort_vs_avoid_after_breakdown() -> void:
	pending(PENDING_REASON + " —— 现象：压力崩溃后谁安慰谁躲开一目了然")


func test_11_fence_sitter_flips_between_camps() -> void:
	pending(PENDING_REASON + " —— 现象：墙头草在两个阵营间反复横跳")


func test_12_even_the_kindest_abandons_the_isolated() -> void:
	pending(PENDING_REASON + " —— 现象：连最和善的人都不理的人被全班孤立")


func test_13_poaching_triggers_old_circle_resentment() -> void:
	pending(PENDING_REASON + " —— 现象：挖墙脚引发原圈子记恨")
