extends GutTest


func _stack() -> Array:
	var core := SimCore.new(20261014, 16, ConfigLoader.new().load_all())
	for index in range(core.node_count()):
		core._stress[index] = 0.0
		core._current_act[index] = null
	core._stress[0] = 80.0
	core._stress[1] = 79.0
	core._stress[2] = 95.0
	core._current_act[0] = "study"
	core._current_act[1] = "chat"
	core._current_act[2] = "sleep"
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
