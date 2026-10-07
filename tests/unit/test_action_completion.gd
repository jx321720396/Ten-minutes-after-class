extends GutTest
## 行为完成语义单测（策划 2026-10-07 裁决 · 阶段 2）。
##
## 依据：§10.4 / §12.2（行为耗时契约）；策划裁决「行为完成才发信息 —— 发起不等于做完」。
## 覆盖：到期 = 完成（清占用 + 可观测）、未到期不算完成、被打断不算完成。

const SEED := 12345
const NPC := 8
## data/rules/behaviors.csv 里 chat 的 duration
const CHAT_DURATION := 30


func _core() -> SimCore:
	return SimCore.from_npc(SEED, NPC, ConfigLoader.new().load_all())


func test_finished_action_clears_occupancy_and_is_observable() -> void:
	var core := _core()
	core._occupy(0, 1, "chat", true)
	var until: int = core._busy_until[0]
	assert_eq(until, core.global_tick() + CHAT_DURATION, "闲聊占用 %d tick" % CHAT_DURATION)

	# 占用期内：记录仍在、也没有「刚完成」
	while core.global_tick() < until - 1:
		core.advance_tick()
	assert_eq(int(core._busy_phase[0]), core.phase_index(), "未到期：占用记录仍在")
	assert_eq(core._current_act[0], "chat", "未到期：当前动作仍在")
	assert_eq(core._last_finished[0], null, "未到期不算完成")

	# 跨过到期点：本 tick 的收尾把行为标记为完成
	core.advance_tick()
	assert_eq(int(core._busy_phase[0]), -1, "到期后占用记录被清理")
	assert_eq(core._current_act[0], null, "到期后当前动作清空（空闲即在学）")
	assert_eq(core._last_finished[0], "chat", "刚完成的行为可被观测（供「完成才发信息」挂载）")

	# 只在本 tick 有效：下一 tick 清空
	core.advance_tick()
	assert_eq(core._last_finished[0], null, "「刚完成」只在本 tick 有效")


func test_interrupted_action_is_not_counted_as_finished() -> void:
	var core := _core()
	var interrupts_before := int(core._stats["interrupts"])
	# 先推到课间段末尾（只剩 5 tick），再占用一个 30 tick 的行为 → 必然跨相位
	while int(core.time_snapshot()["tick_in_phase"]) < 95:
		core.advance_tick()
	core._occupy(0, 1, "chat", true)
	assert_true(core._busy_until[0] > core.global_tick() + 5, "占用应跨过本段边界（否则测不到中断）")

	while str(core.time_snapshot()["phase_id"]) == "morning_break":
		core.advance_tick()

	# 断言语义而不是瞬时值：0 号可能在上课段又被别人占用（那时 busy_phase 会被重新写入），
	# 真正要保证的是「被打断 ≠ 完成」。
	assert_true(int(core._stats["interrupts"]) > interrupts_before, "应记录到铃声中断")
	assert_ne(core._last_finished[0], "chat", "被打断不算完成，不能发放「完成」类信息")


func test_busy_act_records_the_behaviour_even_for_quiet_side() -> void:
	# quiet 一方的 _current_act 会被清成 null（同一场对话只算一个声源），
	# 但「他在做什么」仍要记得住 —— 否则完成时无法知道做完了什么。
	var core := _core()
	core._occupy(0, 1, "chat", true)
	assert_eq(core._current_act[1], null, "被动方不计入声源")
	assert_eq(core._busy_act[1], "chat", "但仍记录占用中的行为")
