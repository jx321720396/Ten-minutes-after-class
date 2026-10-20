extends GutTest


func test_office_shows_remaining_bar_instead_of_seconds() -> void:
	var office = load("res://scenes/game/office.tscn").instantiate()
	add_child_autofree(office)
	var snapshot := {
		"mode": "running",
		"day": 1,
		"next_exam_day": 8,
		"phase_id": "morning_break",
		"kind": "break",
		"remaining_seconds": 65.0,
		"progress": 0.25,
		"paused": false
	}
	office._update_time(snapshot)
	var label: Label = office.get_node("%Countdown")
	var bar: ProgressBar = office.get_node("%RemainingBar")
	assert_eq(label.text, "周考还有 7 天")
	assert_false(label.text.contains("01:05"))
	assert_true(bar.visible)
	assert_eq(bar.value, 75.0)
	snapshot.progress = 0.9
	office._update_time(snapshot)
	assert_almost_eq(bar.value, 10.0, 0.001)
	assert_true(office.get_node("%Time").text.contains("即将上课"))
	snapshot.paused = true
	office._update_time(snapshot)
	assert_true(office.get_node("%Time").text.contains("已暂停"))
	assert_almost_eq(bar.value, 10.0, 0.001)
	snapshot.mode = "report"
	office._update_time(snapshot)
	assert_false(bar.visible)
	assert_eq(label.text, "每日简报")
	snapshot.mode = "finished"
	office._update_time(snapshot)
	assert_false(bar.visible)
	assert_eq(label.text, "学期结束")
