extends GutTest

const BACKPACK = preload("res://scenes/ui/backpack_panel.tscn")


func _touch_button(button: Button, pressed: bool, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = button.get_global_rect().get_center()
	event.index = index
	event.pressed = pressed
	button.get_viewport().push_input(event, true)


func test_touch_opens_selects_takes_once_and_closes() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child_autofree(viewport)
	var bar := PlayerActionBar.new()
	viewport.add_child(bar)
	bar.refresh({&"listen_music": {"ok": true}})
	await get_tree().process_frame
	var launch := bar.get_node("BackpackEntry/BackpackButton") as Button
	_touch_button(launch, true)
	_touch_button(launch, false)
	assert_true(bar.backpack.is_open(), "真实触屏事件打开书包")
	await get_tree().process_frame
	var tag: Button = bar.backpack._tags[&"listen_music"]
	_touch_button(tag, true)
	_touch_button(tag, false)
	assert_eq(bar.backpack._selected, &"listen_music")
	await get_tree().process_frame
	watch_signals(bar.backpack)
	_touch_button(bar.backpack.take_button, true)
	_touch_button(bar.backpack.take_button, false)
	assert_signal_emit_count(bar.backpack, "action_requested", 1)
	assert_false(bar.backpack.is_open())
	_touch_button(launch, true)
	_touch_button(launch, false)
	assert_true(bar.backpack.is_open())
	_touch_button(launch, true)
	_touch_button(launch, false)
	assert_false(bar.backpack.is_open(), "再点入口关闭")


func test_empty_inventory_and_phase_gate() -> void:
	var bag = BACKPACK.instantiate()
	add_child_autofree(bag)
	bag.refresh(
		{
			&"eat_snack": {"ok": false, "reason": "零食吃完了", "snacks": 0},
			&"read_book": {"ok": false, "reason": "你还没有课外书。", "books": 0},
			&"listen_music": {"ok": true}
		}
	)
	bag.open_item(&"read_book")
	assert_true(bag.is_open())
	assert_true(bag.take_button.disabled)
	assert_eq(bag.reason_label.text, "你还没有课外书。")
	bag.select_item(&"listen_music")
	assert_false(bag.take_button.disabled)
	bag.refresh({&"listen_music": {"ok": false, "reason": "上课呢，下课再说"}})
	assert_true(bag.take_button.disabled)
	assert_eq(bag.reason_label.text, "上课呢，下课再说")


func test_touch_drag_cancel_disabled_and_second_finger_do_not_take() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child_autofree(viewport)
	var bag = BACKPACK.instantiate()
	viewport.add_child(bag)
	bag.refresh({&"eat_snack": {"ok": true, "snacks": 5}})
	bag.open_item()
	await get_tree().process_frame
	watch_signals(bag)
	var button: Button = bag.take_button
	_touch_button(button, true)
	_touch_button(button, false, 1)
	assert_signal_emit_count(bag, "action_requested", 0)
	var drag := InputEventScreenDrag.new()
	drag.position = button.get_global_rect().get_center()
	drag.index = 0
	drag.relative = Vector2(20, 0)
	viewport.push_input(drag, true)
	_touch_button(button, false)
	assert_true(bag.is_open(), "拖动不会拿取")
	_touch_button(button, true)
	var cancel := InputEventScreenTouch.new()
	cancel.position = button.get_global_rect().get_center()
	cancel.canceled = true
	viewport.push_input(cancel, true)
	assert_true(bag.is_open(), "系统取消触摸不会拿取")
	bag.refresh({&"eat_snack": {"ok": false, "snacks": 0}})
	_touch_button(button, true)
	_touch_button(button, false)
	assert_signal_emit_count(bag, "action_requested", 0)
	assert_true(bag.is_open(), "禁用按钮不会关闭书包")


func test_take_emits_once_and_closes_without_changing_snapshot() -> void:
	var bag = BACKPACK.instantiate()
	add_child_autofree(bag)
	var states := {&"eat_snack": {"ok": true, "snacks": 5}}
	bag.refresh(states)
	watch_signals(bag)
	bag.open_item(&"eat_snack")
	bag.take_selected()
	bag.take_selected()
	assert_signal_emit_count(bag, "action_requested", 1)
	assert_signal_emitted_with_parameters(bag, "action_requested", [&"eat_snack"])
	assert_false(bag.is_open())
	assert_eq(states[&"eat_snack"]["snacks"], 5)


func test_escape_closes_without_pausing() -> void:
	var bag = BACKPACK.instantiate()
	add_child_autofree(bag)
	bag.open_item()
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	bag._input(event)
	assert_false(bag.is_open())
	assert_false(get_tree().paused)


func test_bar_inventory_action_reaches_existing_controller_once() -> void:
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
	var bar := PlayerActionBar.new()
	add_child_autofree(bar)
	var controller := PlayerInteractionController.new()
	add_child_autofree(controller)
	controller._core = core
	controller._bar = bar
	controller._connect_sources()
	controller._refresh_bar()
	var me := core.node_count() - 1
	var before := int(core.inventory_of(me).snacks)
	bar.open_backpack(&"eat_snack")
	assert_false(bar.get_node("ActionBar").visible)
	assert_false(core.is_busy(me))
	bar.backpack.take_selected()
	assert_eq(int(core.inventory_of(me).snacks), before - 1)
	assert_eq(core.activity_of(me), "eat_snack")
	assert_true(bar.get_node("ActionBar").visible)
	assert_false(bar.backpack.is_open())


func test_standalone_button_opens_and_toggles_backpack() -> void:
	var bar := PlayerActionBar.new()
	add_child_autofree(bar)
	var launch := bar.get_node_or_null("BackpackEntry/BackpackButton") as Button
	assert_not_null(launch, "书包入口应为右下角独立 UI 按键")
	if launch == null:
		return
	assert_eq(launch.text, "书包")
	assert_null(bar.get_node("ActionBar").get_node_or_null("Padding/Column/OpenBackpack"))
	assert_false(bar.backpack.is_open())
	launch.pressed.emit()
	assert_true(bar.backpack.is_open())
	launch.pressed.emit()
	assert_false(bar.backpack.is_open())
	assert_true(bar.get_node("ActionBar").visible)


func test_utility_buttons_share_style_and_do_not_overlap() -> void:
	var Theme := preload("res://scripts/ui/campus_theme.gd")
	var buttons: Array[Button] = []
	for slot in range(3):
		var button := Button.new()
		add_child_autofree(button)
		Theme.utility_button(button, slot)
		buttons.append(button)
		var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
		assert_eq(normal.bg_color, Color(Theme.settings().paper))
		assert_eq(normal.border_color, Color(Theme.settings().teal))
		assert_not_null(button.icon)
		assert_eq(button.get_theme_color("font_color"), Color(Theme.settings().teal))
	assert_eq(buttons[0].custom_minimum_size, buttons[2].custom_minimum_size)
	assert_lt(buttons[2].offset_right, buttons[1].offset_left)
	assert_lt(buttons[1].offset_right, buttons[0].offset_left)


func test_opening_other_utility_closes_backpack() -> void:
	var bar := PlayerActionBar.new()
	add_child_autofree(bar)
	var book: CanvasLayer = load("res://scenes/ui/encyclopedia_entry.tscn").instantiate()
	add_child_autofree(book)
	bar.open_backpack()
	book.get_node("EncyclopediaButton").pressed.emit()
	assert_false(bar.backpack.is_open())
	assert_true(book.is_open())
	book.close()
	get_tree().paused = false
