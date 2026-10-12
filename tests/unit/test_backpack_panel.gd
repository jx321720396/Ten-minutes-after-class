extends GutTest


func test_empty_inventory_and_phase_gate() -> void:
	var bag = load("res://scenes/ui/backpack_panel.tscn").instantiate()
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


func test_take_emits_once_and_closes_without_changing_snapshot() -> void:
	var bag = load("res://scenes/ui/backpack_panel.tscn").instantiate()
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
	var bag = load("res://scenes/ui/backpack_panel.tscn").instantiate()
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
	var theme := preload("res://scripts/ui/campus_theme.gd")
	var buttons: Array[Button] = []
	for slot in range(3):
		var button := Button.new()
		add_child_autofree(button)
		theme.utility_button(button, slot)
		buttons.append(button)
		var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
		assert_eq(normal.bg_color, Color(theme.settings().paper))
		assert_eq(normal.border_color, Color(theme.settings().teal))
		assert_not_null(button.icon)
		assert_eq(button.get_theme_color("font_color"), Color(theme.settings().teal))
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
