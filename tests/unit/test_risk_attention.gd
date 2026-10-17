extends GutTest

const Card := preload("res://scripts/ui/attention_card.gd")


func _stack() -> Array:
	var core := SimCore.new(20261016, 16, ConfigLoader.new().load_all())
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.bind_core(core)
	clock.set_process(false)
	return [core, clock]


func _bully(core: SimCore, target: int) -> void:
	for source in range(3):
		core._h[source * core.node_count() + target] = 60.0
	core._note_harm(0, target, "aggression")


func test_warning_uses_settled_evidence_and_clears_when_streak_resets() -> void:
	var parts := _stack()
	var core: SimCore = parts[0]
	_bully(core, 5)
	core._risk.settle_day(core, 1)
	var warnings: Dictionary = parts[1].snapshot().get("risk_attention", {})
	assert_eq(warnings.get("bully", []).size(), 1)
	if warnings.get("bully", []).size() == 1:
		assert_eq(warnings.bully[0].streak, 1)
		assert_false(warnings.bully[0].formal)
	core._risk.settle_day(core, 2)
	assert_true(core._risk.warned_of(5), "历史预警仍保留")
	assert_eq(parts[1].snapshot().get("risk_attention", {}).get("bully", []).size(), 0)


func test_isolation_becomes_formal_on_second_settled_day() -> void:
	var parts := _stack()
	var core: SimCore = parts[0]
	for source in range(core.node_count()):
		if source != 5:
			core._a[source * core.node_count() + 5] = 10.0
	for day in [1, 2]:
		core._risk.register_join_reject(5)
		core._risk.register_join_reject(5)
		core._risk.settle_day(core, day)
	var risks: Array = parts[1].snapshot().get("risk_attention", {}).get("isolate", [])
	assert_eq(risks.size(), 1)
	if risks.size() == 1:
		assert_true(risks[0].formal)
		assert_eq(risks[0].streak, 2)


func test_breakdown_is_actual_state_and_observation_is_readonly() -> void:
	var parts := _stack()
	var core: SimCore = parts[0]
	core._stress[4] = 95.0
	assert_eq(parts[1].snapshot().get("risk_attention", {}).get("broken", []).size(), 0)
	core._check_breakdown()
	var before := core._risk_snapshot()
	var relations := core._h.duplicate()
	var words := core._rng.words_consumed
	var card := Card.new()
	add_child_autofree(card)
	card.refresh(parts[1].snapshot())
	assert_eq(card.find_child("BrokenCount", true, false).text, "1人")
	card.find_child("BrokenButton", true, false).pressed.emit()
	assert_true(card.get_node("Details").visible)
	watch_signals(card)
	card.find_child("Student_4_broken", true, false).pressed.emit()
	assert_signal_emitted_with_parameters(card, "student_requested", [4])
	assert_eq(core._risk_snapshot(), before)
	assert_eq(core._h, relations)
	assert_eq(core._rng.words_consumed, words)
	core._stress[4] = 60.0
	core._check_breakdown()
	assert_eq(
		parts[1].snapshot().get("risk_attention", {}).get("broken", []).size(),
		1,
		"旧「压力 <70 即时恢复」已废止：压力降下来仍处于崩溃休息，等次日跨天恢复（§5.3）"
	)


func test_unknown_snapshot_is_distinct_from_zero_and_refresh_keeps_buttons() -> void:
	var card := Card.new()
	add_child_autofree(card)
	assert_eq(card.find_child("BullyCount", true, false).text, "—人")
	var button := card.find_child("BullyButton", true, false)
	card.refresh({"risk_attention": {"bully": [], "isolate": [], "broken": []}})
	assert_eq(card.find_child("BullyCount", true, false).text, "0人")
	assert_same(card.find_child("BullyButton", true, false), button)


func test_exam_keeps_warning_and_formal_risk_remains_after_no_harm_day() -> void:
	var parts := _stack()
	var core: SimCore = parts[0]
	_bully(core, 5)
	core._risk.settle_day(core, 7)
	assert_eq(parts[1].snapshot().risk_attention.bully.size(), 1)
	core._day = 8
	core._risk.settle_day(core, 8)
	var entries: Array = parts[1].snapshot().get("risk_attention", {}).get("bully", [])
	assert_eq(entries.size(), 1)
	if not entries.is_empty():
		assert_eq(entries[0].streak, 1)
	core._day = 9
	_bully(core, 5)
	core._risk.settle_day(core, 9)
	core._risk.settle_day(core, 10)
	entries = parts[1].snapshot().get("risk_attention", {}).get("bully", [])
	assert_eq(entries.size(), 1)
	if not entries.is_empty():
		assert_true(entries[0].formal)
		assert_eq(entries[0].streak, 0)
