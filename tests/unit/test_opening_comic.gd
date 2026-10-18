extends GutTest

const MODEL = preload("res://scripts/ui/opening_comic_state.gd")


func test_auto_reveal_waits_two_seconds_and_never_turns_page() -> void:
	var model = MODEL.new()
	model.start(4, 4, 2.0)
	assert_eq(model.revealed, 1)
	model.advance_time(1.9)
	assert_eq(model.revealed, 1)
	model.advance_time(0.1)
	assert_eq(model.revealed, 2)
	model.advance_time(20.0)
	assert_eq(model.revealed, 4)
	assert_eq(model.page, 0, "整页自动展示后必须等点击")


func test_click_reveals_one_panel_before_complete_page_can_turn() -> void:
	var model = MODEL.new()
	model.start(4, 4, 2.0)
	model.tap()
	assert_eq(model.revealed, 2)
	assert_eq(model.page, 0)
	model.advance_time(1.9)
	assert_eq(model.revealed, 2)
	model.tap()
	assert_eq(model.revealed, 3)
	model.tap()
	assert_eq(model.revealed, 4)
	assert_eq(model.page, 0)
	model.tap()
	assert_eq(model.page, 1)
	assert_eq(model.revealed, 1)
	model.advance_time(1.0)
	assert_eq(model.revealed, 1, "翻页重置计时")


func test_last_page_closes_once_and_skip_stops_time() -> void:
	var model = MODEL.new()
	model.start(1, 4, 2.0)
	model.advance_time(20.0)
	assert_false(model.finished)
	model.tap()
	assert_true(model.finished)
	model.tap()
	assert_eq(model.page, 0)
	model.start(4, 4, 2.0)
	model.skip()
	model.advance_time(20.0)
	assert_true(model.finished)
	assert_eq(model.page, 0)
