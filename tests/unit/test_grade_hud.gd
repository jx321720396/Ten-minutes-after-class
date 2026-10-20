extends GutTest
## 周考卡片：真实时钟、学生均分及目标差距；旧玩家不属于班级统计。


func _stack() -> Array:
	var tables := ConfigLoader.new().load_all()
	var core := SimCore.new(20261014, 16, tables)
	for index in range(core.node_count()):
		core._grade[index] = 470.0
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	assert_true(clock.bind_core(core, tables))
	clock.set_process(false)
	var hud: TimeHUD = load("res://scenes/ui/time_hud.tscn").instantiate()
	add_child_autofree(hud)
	hud.bind_clock(clock)
	hud.set_process(false)
	return [core, clock, hud, tables]


## 目标均分从 `data/rules/exam.csv` 的 `exam_target_mean_1` 读，不在测试里写死数字。
func _exam_target_mean(tables: Dictionary) -> float:
	for row in tables.get("rules/exam", {}).get("rows", []):
		if str(row.get("param", "")) == "exam_target_mean_1":
			return float(row.get("value", "0"))
	return 0.0


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
	# D05：目标均分取自配置（2026-10-20 起 exam_target_mean_1 = 490）。
	var target := _exam_target_mean(parts[3])
	for index in range(core.node_count()):
		core._grade[index] = 300.0
	clock.time_updated.emit(clock.snapshot())
	assert_true(_goal_text(hud).contains("还差 %d 分" % int(target - 300.0)), _goal_text(hud))
	for index in range(core.node_count()):
		core._grade[index] = 355.0
	clock.time_updated.emit(clock.snapshot())
	assert_true(_goal_text(hud).contains("还差 %d 分" % int(target - 355.0)), _goal_text(hud))


func test_reached_goal_does_not_show_negative_gap() -> void:
	var parts := _stack()
	var clock: SimulationClock = parts[1]
	var hud: TimeHUD = parts[2]
	var snapshot := clock.snapshot()
	snapshot["class_average_grade"] = 550.0
	hud._refresh(snapshot)
	assert_true(_goal_text(hud).contains("已达标"), _goal_text(hud))
	assert_false(_goal_text(hud).contains("还差 -"), _goal_text(hud))


func test_weekly_exam_countdown_tracks_next_exam() -> void:
	var parts := _stack()
	var hud: TimeHUD = parts[2]
	var snapshot: Dictionary = parts[1].snapshot()
	var label := hud.get_node_or_null("Card/Rows/WeeklyExamRow/WeeklyExamLabel") as Label
	assert_not_null(label, "卡片应有独立周考行")
	snapshot["day"] = 7
	snapshot["next_exam_day"] = 8
	hud._refresh(snapshot)
	if label != null:
		assert_eq(label.text, "周考还有 1 天", "D05：第 7 天是考前日")
	snapshot["day"] = 8
	snapshot["next_exam_day"] = 8
	hud._refresh(snapshot)
	if label != null:
		assert_eq(label.text, "今天周考", "D05：第 8 天是首次考试日")
	snapshot["day"] = 9
	snapshot["next_exam_day"] = 14
	hud._refresh(snapshot)
	if label != null:
		assert_eq(label.text, "周考还有 5 天", "D05：第 9 天倒计时到第 14 天第二次周考")
	snapshot["day"] = 29
	snapshot["next_exam_day"] = 30
	snapshot["term_days"] = 30
	hud._refresh(snapshot)
	if label != null:
		assert_eq(label.text, "期末考还有 1 天", "D05：第 29 天倒计时到期末考")


func test_missing_grades_are_not_fabricated_as_zero() -> void:
	var parts := _stack()
	var hud: TimeHUD = parts[2]
	var snapshot: Dictionary = parts[1].snapshot()
	snapshot.erase("class_average_grade")
	hud._refresh(snapshot)
	assert_true(_goal_text(hud).contains("均分待获取"), _goal_text(hud))
