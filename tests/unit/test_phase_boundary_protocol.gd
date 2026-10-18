extends GutTest
## 统一相位边界协议单测（修复 Python↔GDScript 同种子对拍破裂）。
##
## 依据：docs/design/架构总览.md「相位边界协议」；主文档 §3.2 / §3.3 / §10.4 / §10.8。
##
## 统一协议顺序（不推进任何 tick）：
##   ① 到期结算 ② 睡眠收尾 ③ 中断 ④ 清理 ⑤ 日末跨天 ⑥ 切换 ⑦ 新段判定。
## 断言聚焦于：完成/中断互斥、清理一致性、幂等（_settled_boundary）、抽象内核无移动锁。

const SEED := 12345
const NPC := 8


func _core() -> SimCore:
	return SimCore.new(SEED, NPC, ConfigLoader.new().load_all())


func _advance_to(core: SimCore, tick: int) -> void:
	while int(core.time_snapshot()["tick_in_phase"]) < tick:
		core.advance_tick()


## 直接给节点 i 造一个占用（跨段与否由 until 决定），并清掉会话/睡眠干扰。
func _set_busy(core: SimCore, i: int, until: int, phase: int, act: String) -> void:
	core._sessions.clear()
	var busy_until: Array = core._busy_until
	var busy_phase: Array = core._busy_phase
	var current_act: Array = core._current_act
	var busy_act: Array = core._busy_act
	var sleeping: Array = core._sleeping
	var in_conv: Array = core._in_conversation
	busy_until[i] = until
	busy_phase[i] = phase
	current_act[i] = act
	busy_act[i] = act
	sleeping[i] = false
	in_conv[i] = true
	core._busy_until = busy_until
	core._busy_phase = busy_phase
	core._current_act = current_act
	core._busy_act = busy_act
	core._sleeping = sleeping
	core._in_conversation = in_conv


# ------------------------------------------------------------------ ① 到期结算：完成与中断互斥


func test_completion_exactly_at_bell_is_completion_not_interrupt() -> void:
	var core := _core()
	_advance_to(core, 99)
	_set_busy(core, 0, 100, 0, "chat")  # 恰好第 100 tick 到期
	core.advance_tick()  # 第 100 tick
	assert_eq(core._last_finished[0], "chat", "到期即完成，有完成记录")
	assert_eq(int(core._stats["interrupts"]), 0, "完成不计中断代价")


# ------------------------------------------------------------------ ③ 中断：未到期且跨段 → 打断一次


func test_crossing_bell_interrupts_without_completion() -> void:
	var core := _core()
	_advance_to(core, 100)
	_set_busy(core, 0, 101, 0, "chat")  # 比铃声晚 1 tick
	core.finish_time_boundary()
	assert_true(core._interrupted_nodes.has(0), "0 号被打断")
	assert_eq(core._busy_until[0], 0, "占用到期点归零")
	assert_eq(core._busy_phase[0], -1, "占用相位记录已清")
	assert_eq(core._last_finished[0], null, "无完成记录（不是完成）")


# ------------------------------------------------------------------ ④ 清理：cleanup_phase 清 current_act / busy_act / 会话


func test_cleanup_clears_residual_action_state() -> void:
	var core := _core()
	_advance_to(core, 100)
	_set_busy(core, 0, 101, 0, "chat")
	core.finish_time_boundary()
	assert_eq(core._current_act[0], null, "current_act 已清（free_join 看到空闲）")
	assert_eq(core._busy_act[0], null, "busy_act 已清")
	assert_eq(core._in_conversation[0], false, "in_conversation 已清")


# ------------------------------------------------------------------ 幂等：_settled_boundary = (天, 旧相位)


func test_repeated_end_phase_is_idempotent() -> void:
	var core := _core()
	_advance_to(core, 100)
	_set_busy(core, 0, 105, 0, "chat")
	var interrupts_before := int(core._stats["interrupts"])
	core._end_phase()  # 直接处理边界一次（不切段，_phase_index 仍为 0）
	var interrupts_after := int(core._stats["interrupts"])
	assert_gt(interrupts_after, interrupts_before, "第一次处理确有中断")
	var stress_after := float(core._stress[0])
	core._end_phase()  # 同一 (day=1, phase_index=0) 边界 → 幂等跳过
	assert_eq(int(core._stats["interrupts"]), interrupts_after, "中断计数不翻倍")
	assert_eq(core._stress[0], stress_after, "压力不再叠加")


# ------------------------------------------------------------------ ② 睡眠收尾：课间睡下 → 跨过上课段，在它的末点结算一次


func test_sleep_survives_break_end_and_settles_after_class() -> void:
	var core := _core()
	_advance_to(core, 1)  # 已在课间段内（段首判定已完成）
	core._sessions.clear()
	var stress: Array = core._stress
	stress[0] = 50.0
	core._stress = stress
	var vitality: Array = core._vitality
	vitality[0] = 50.0
	core._vitality = vitality
	var sleeping: Array = core._sleeping
	sleeping[0] = true
	core._sleeping = sleeping
	var relief := float(core._probs.get("sleep_relief", 0.0))
	var gain := float(core._probs.get("sleep_vitality_gain", 0.0))

	# 课间段末：下一段是上课 → 不唤醒、不减压（2026-10-19：睡觉跨过紧邻上课段）
	core._settle_sleep()
	assert_true(core._sleeping[0], "课间末不唤醒：睡觉跨过紧邻的上课段")
	assert_almost_eq(core._stress[0], 50.0, 0.001, "课间末不减压")

	# 上课段末（`skip_class()` 被调用的位置）→ 结算一次
	core._phase_index += 1
	core._settle_sleep()
	assert_false(core._sleeping[0], "上课段结束时醒来")
	assert_almost_eq(core._stress[0], 50.0 - relief, 0.001, "睡眠减压恰好一次")
	assert_almost_eq(core._vitality[0], 50.0 + gain, 0.001, "睡觉同时动力 +10")


# ------------------------------------------------------------------ 抽象内核：无移动输入，is_moving 恒 false


func test_abstract_kernel_has_no_movement_locks() -> void:
	var core := _core()
	var n := core.node_count()
	for i in range(n):
		assert_false(core.is_moving(i), "抽象内核无移动输入：is_moving 恒 false")
	_advance_to(core, 100)
	core.finish_time_boundary()
	for i in range(n):
		assert_false(core.is_moving(i), "边界处理后（cleanup 移动锁清理为 no-op）仍无移动锁")
