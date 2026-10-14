extends GutTest


func _stack() -> Array:
	var core := SimCore.new(20261014, 16, ConfigLoader.new().load_all())
	for index in range(core.node_count()):
		core._stress[index] = 0.0
		core._current_act[index] = null
	core._stress[0] = 80.0
	core._stress[1] = 79.0
	core._stress[2] = 95.0
	core._stress[16] = 100.0
	core._current_act[0] = "study"
	core._current_act[1] = "chat"
	core._current_act[2] = "sleep"
	core._current_act[16] = "study"
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	assert_true(clock.bind_core(core))
	clock.set_process(false)
	var hud := TimeHUD.new()
	add_child_autofree(hud)
	hud.bind_clock(clock)
	hud.set_process(false)
	return [core, clock, hud]


func test_pressure_warning_includes_boundary_and_excludes_player() -> void:
	var parts := _stack()
	var entries: Array = parts[1].snapshot().get("high_pressure_students", [])
	assert_eq(entries.size(), 2)
	if entries.size() == 2:
		assert_eq(entries[0].index, 2)
		assert_eq(entries[1].index, 0)


func test_activity_counts_use_real_activities_and_cover_students() -> void:
	var parts := _stack()
	var counts: Dictionary = parts[1].snapshot().get("activity_counts", {})
	assert_eq(int(counts.get("study", -1)), 1)
	assert_eq(int(counts.get("entertainment", -1)), 2)
	assert_eq(int(counts.get("other", -1)), 13)


func test_missing_conflict_records_are_not_zero() -> void:
	var parts := _stack()
	var card: Node = parts[2].get_node_or_null("AttentionCard")
	assert_not_null(card)
	if card != null:
		assert_true(card.find_child("ConflictButton", true, false).text.contains("—"))


func test_conflict_records_distinguish_zero_and_active_events() -> void:
	var parts := _stack()
	var card: Node = parts[2].get_node_or_null("AttentionCard")
	assert_not_null(card)
	if card == null:
		return
	card.refresh({"ordinary_conflicts": []})
	assert_true(card.find_child("ConflictButton", true, false).text.contains("0 起"))
	card.refresh(
		{
			"ordinary_conflicts":
			[
				{"event_id": "a", "active": true, "description": "争吵记录"},
				{"event_id": "a", "active": true, "description": "争吵记录"},
				{"event_id": "b", "active": false, "description": "已结束"}
			]
		}
	)
	assert_true(card.find_child("ConflictButton", true, false).text.contains("1 起"))
	card.refresh(
		{
			"ordinary_conflicts":
			[{"event_id": "a", "active": true}, {"event_id": "a", "active": false}]
		}
	)
	assert_true(card.find_child("ConflictButton", true, false).text.contains("0 起"))


func test_warning_opens_students_and_requests_profile_without_mutating_core() -> void:
	var parts := _stack()
	var card: Node = parts[2].get_node_or_null("AttentionCard")
	assert_not_null(card)
	if card == null:
		return
	watch_signals(card)
	card.find_child("PressureButton", true, false).pressed.emit()
	assert_true(card.get_node("Details").visible)
	var student := card.find_child("Student_0", true, false) as Button
	assert_not_null(student)
	if student != null:
		student.pressed.emit()
		assert_signal_emitted_with_parameters(card, "student_requested", [0])
	assert_eq(parts[0].stress(0), 80.0)
