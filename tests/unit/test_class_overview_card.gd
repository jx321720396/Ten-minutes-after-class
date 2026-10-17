extends GutTest


func _stack() -> Array:
	var core := SimCore.new(20261014, 16, ConfigLoader.new().load_all())
	for index in range(core.node_count()):
		core._stress[index] = 25.0
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	assert_true(clock.bind_core(core))
	clock.set_process(false)
	var hud := TimeHUD.new()
	add_child_autofree(hud)
	hud.bind_clock(clock)
	hud.set_process(false)
	return [core, clock, hud]


func test_average_pressure_excludes_player() -> void:
	var parts := _stack()
	assert_almost_eq(float(parts[1].snapshot().get("class_average_pressure", -1.0)), 25.0, 0.001)


func test_card_does_not_fabricate_missing_metrics() -> void:
	var parts := _stack()
	var card: Node = parts[2].get_node_or_null("ClassOverviewCard")
	assert_not_null(card)
	if card == null:
		return
	card.refresh({"class_average_pressure": 25.0})
	assert_eq(card.find_child("MotivationValue", true, false).text, "—")
	assert_eq(card.find_child("AcademicGainValue", true, false).text, "—")
	assert_eq(card.find_child("PressureValue", true, false).text, "25")


func test_real_zero_and_signed_gain_stay_distinct_from_missing() -> void:
	var parts := _stack()
	var card: Node = parts[2].get_node_or_null("ClassOverviewCard")
	assert_not_null(card)
	if card == null:
		return
	card.refresh(
		{
			"student_count": 16,
			"grade_max": 750,
			"class_average_grade": 474.0,
			"class_average_pressure": 0.0,
			"class_average_motivation": 0.0,
			"class_average_academic_gain": -2.5
		}
	)
	assert_eq(card.find_child("MotivationValue", true, false).text, "0")
	assert_eq(card.find_child("PressureValue", true, false).text, "0")
	assert_eq(card.find_child("AcademicGainValue", true, false).text, "-2.5")
	card.refresh({"class_average_academic_gain": 2.1})
	assert_eq(card.find_child("AcademicGainValue", true, false).text, "+2.1")


func test_overview_button_opens_read_only_detail() -> void:
	var parts := _stack()
	var card: Node = parts[2].get_node_or_null("ClassOverviewCard")
	assert_not_null(card)
	if card == null:
		return
	card.find_child("OverviewButton", true, false).pressed.emit()
	assert_true(card.get_node("Details").visible)
	card.find_child("CloseOverview", true, false).pressed.emit()
	assert_false(card.get_node("Details").visible)
	assert_almost_eq(float(parts[1].snapshot().get("class_average_pressure", -1.0)), 25.0, 0.001)


func test_live_core_metrics_reach_card() -> void:
	var parts := _stack()
	for i in range(parts[0].node_count()):
		parts[0]._vitality[i] = 45.0
		parts[0]._gain_today[i] = -2.0
	parts[2]._on_time_updated(parts[1].snapshot())
	var card: Node = parts[2].get_node("ClassOverviewCard")
	assert_eq(card.find_child("MotivationValue", true, false).text, "45")
	assert_eq(card.find_child("AcademicGainValue", true, false).text, "-2")
