extends GutTest
## 周考卡片：真实时钟、学生均分及目标差距；旧玩家不属于班级统计。


func _stack() -> Array:
	var tables := ConfigLoader.new().load_all()
	var core := SimCore.new(20261014, 16, tables)
	for index in range(core.node_count()):
		core._grade[index] = 750.0 if core.is_player(index) else 470.0
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	assert_true(clock.bind_core(core, tables))
	clock.set_process(false)
	var hud: TimeHUD = load("res://scenes/ui/time_hud.tscn").instantiate()
	add_child_autofree(hud)
	hud.bind_clock(clock)
	hud.set_process(false)
	return [core, clock, hud]


func _goal_text(hud: TimeHUD) -> String:
	var label := hud.get_node("Card/Rows/GradeLabel")
	if label is RichTextLabel:
		return label.get_parsed_text()
	return label.text


func test_class_average_excludes_legacy_player() -> void:
	var parts := _stack()
	var snapshot: Dictionary = parts[1].snapshot()
	assert_eq(int(snapshot.get("student_count", -1)), 16)
	assert_almost_eq(float(snapshot.get("class_average_grade", -1.0)), 470.0, 0.001)


func test_goal_gap_tracks_student_grades() -> void:
	var parts := _stack()
	var core: SimCore = parts[0]
	var clock: SimulationClock = parts[1]
	var hud: TimeHUD = parts[2]
	assert_true(_goal_text(hud).contains("还差 55 分"), _goal_text(hud))
	for index in range(core.node_count()):
		if not core.is_player(index):
			core._grade[index] = 500.0
	clock.time_updated.emit(clock.snapshot())
	assert_true(_goal_text(hud).contains("还差 25 分"), _goal_text(hud))


func test_reached_goal_does_not_show_negative_gap() -> void:
	var parts := _stack()
	var clock: SimulationClock = parts[1]
	var hud: TimeHUD = parts[2]
	var snapshot := clock.snapshot()
	snapshot["class_average_grade"] = 550.0
	hud._refresh(snapshot)
	assert_true(_goal_text(hud).contains("已达标"), _goal_text(hud))
	assert_false(_goal_text(hud).contains("还差 -"), _goal_text(hud))


func test_first_weekly_exam_day_has_today_label() -> void:
	var parts := _stack()
	var hud: TimeHUD = parts[2]
	var snapshot: Dictionary = parts[1].snapshot()
	snapshot["day"] = 7
	hud._refresh(snapshot)
	var label := hud.get_node_or_null("Card/Rows/WeeklyExamRow/WeeklyExamLabel") as Label
	assert_not_null(label, "卡片应有独立周考行")
	if label != null:
		assert_eq(label.text, "今天周考")
	snapshot["day"] = 8
	hud._refresh(snapshot)
	if label != null:
		assert_eq(label.text, "首次周考已结束")


func test_missing_grades_are_not_fabricated_as_zero() -> void:
	var parts := _stack()
	var hud: TimeHUD = parts[2]
	var snapshot: Dictionary = parts[1].snapshot()
	snapshot.erase("class_average_grade")
	hud._refresh(snapshot)
	assert_true(_goal_text(hud).contains("均分待获取"), _goal_text(hud))
