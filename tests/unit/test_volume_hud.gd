extends GutTest


func test_live_volume_and_threshold_are_read_only() -> void:
	var core := SimCore.new(20261011, 16, ConfigLoader.new().load_all())
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.set_process(false)
	assert_true(clock.bind_core(core))
	var hud := TimeHUD.new()
	add_child_autofree(hud)
	hud.bind_clock(clock)
	var volume_before := core.volume()
	assert_eq(float(clock.snapshot().get("volume", -1)), volume_before)
	assert_eq(float(clock.snapshot().get("volume_threshold", -1)), 20.0)
	assert_not_null(hud.get_node_or_null("ClassOverviewCard"))
	clock.pump(1.0)
	assert_eq(float(clock.snapshot().get("volume", -1)), core.volume())
	assert_almost_eq(float(clock.snapshot().get("volume", -1)), core.volume(), 0.001)
	var after := core.volume()
	hud.get_node("ClassOverviewCard").refresh(clock.snapshot())
	assert_eq(core.volume(), after)


func test_unbound_hud_does_not_invent_class_grade() -> void:
	var hud := TimeHUD.new()
	add_child_autofree(hud)
	assert_eq(hud.get_node("ClassOverviewCard").find_child("GradeValue", true, false).text, "—")


func test_display_uses_snapshot_scale_and_clamps_only_its_copy() -> void:
	var card := preload("res://scripts/ui/volume_card.gd").new()
	add_child_autofree(card)
	var snapshot := {"volume": 120.0, "volume_max": 80.0, "volume_threshold": 15.0}
	card.refresh(snapshot)
	assert_eq(card.value, 80.0)
	assert_eq(card._threshold, 15.0)
	assert_eq(snapshot.volume, 120.0)
	assert_true(card.visible)
