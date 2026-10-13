extends GutTest

const BACKPACK_SCENE := preload("res://scenes/ui/backpack_panel.tscn")


func test_empty_inventory_and_phase_gate() -> void:
	var bag = BACKPACK_SCENE.instantiate()
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
	var bag = BACKPACK_SCENE.instantiate()
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
	var bag = BACKPACK_SCENE.instantiate()
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
	var CampusTheme := preload("res://scripts/ui/campus_theme.gd")
	var buttons: Array[Button] = []
	for slot in range(3):
		var button := Button.new()
		add_child_autofree(button)
		CampusTheme.utility_button(button, slot)
		buttons.append(button)
		var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
		assert_eq(normal.bg_color, Color(CampusTheme.settings().paper))
		assert_eq(normal.border_color, Color(CampusTheme.settings().teal))
		assert_not_null(button.icon)
		assert_eq(button.get_theme_color("font_color"), Color(CampusTheme.settings().teal))
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


func _item_fixture() -> Dictionary:
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
	var bar := PlayerActionBar.new()
	add_child_autofree(bar)
	var hud := ChatFeedbackHUD.new()
	add_child_autofree(hud)
	var controller := PlayerInteractionController.new()
	add_child_autofree(controller)
	controller._core = core
	controller._bar = bar
	controller._hud = hud
	controller.set_process(false)
	controller._connect_sources()
	GameState.wire_events(core)
	var events: Array = []
	var listener := func(payload: Dictionary) -> void:
		if int(payload.get("i", -1)) == core.node_count() - 1:
			events.append(
				{
					"payload": payload.duplicate(true),
					"activity": core.activity_of(core.node_count() - 1)
				}
			)
	EventBus.event_happened.connect(listener)
	return {
		"core": core,
		"bar": bar,
		"hud": hud,
		"controller": controller,
		"events": events,
		"listener": listener
	}


func _close_item_fixture(f: Dictionary) -> void:
	f.controller._disconnect_sources()
	EventBus.event_happened.disconnect(f.listener)
	f.core.event_sink = Callable()


func test_all_items_complete_through_bus_and_refresh_open_backpack() -> void:
	for kind in SimCore.LEISURE_KINDS:
		var f := _item_fixture()
		var c: SimCore = f.core
		var me := c.node_count() - 1
		c._book[me] = 1
		c._stress[me] = 20.0
		f.controller._refresh_bar()
		var snacks := int(c.inventory_of(me).snacks)
		f.bar.open_backpack(StringName(kind))
		f.bar.backpack.take_selected()
		f.bar.backpack.take_selected()
		assert_eq(c.activity_of(me), kind)
		assert_eq(c.stress(me), 20.0, "拿取时不提前减压")
		assert_eq(int(c.inventory_of(me).snacks), snacks - (1 if kind == "eat_snack" else 0))
		f.bar.open_backpack(StringName(kind))
		assert_true(f.bar.backpack.take_button.disabled)
		var prefix := str(SimCore.LEISURE_KINDS[kind])
		assert_eq(int(c._busy_until[me]) - c._global_tick, int(c._leisure[prefix + "_duration"]))
		c._global_tick = int(c._busy_until[me])
		c._settle_finished_actions()
		c._settle_finished_actions()
		assert_eq(c.stress(me), 20.0 - float(c._leisure[prefix + "_relief"]))
		assert_eq(f.events.size(), 1, "完成事件恰好一次")
		assert_eq(f.events[0].payload.kind, "leisure_finished")
		assert_eq(f.events[0].payload.activity, kind)
		assert_eq(f.events[0].activity, "", "事件消费者读到已清理的动作")
		assert_false(f.bar.backpack.take_button.disabled, "完成事件立即刷新书包")
		assert_false(f.hud._toast.text.is_empty())
		_close_item_fixture(f)


func test_all_items_bell_interrupt_through_bus_without_refund_or_relief() -> void:
	for kind in SimCore.LEISURE_KINDS:
		var f := _item_fixture()
		var c: SimCore = f.core
		var me := c.node_count() - 1
		c._book[me] = 1
		c._stress[me] = 20.0
		f.controller._refresh_bar()
		f.bar.open_backpack(StringName(kind))
		f.bar.backpack.take_selected()
		var snacks := int(c.inventory_of(me).snacks)
		f.bar.open_backpack(StringName(kind))
		c._end_phase()
		c._end_phase()
		assert_eq(c.stress(me), 20.0 + float(c._leisure.interrupted_stress))
		assert_eq(int(c.inventory_of(me).snacks), snacks, "中断不退还已吃的零食")
		assert_eq(f.events.size(), 1)
		assert_eq(f.events[0].payload.kind, "leisure_interrupted")
		assert_eq(f.events[0].activity, "", "中断通知前清理动作")
		assert_false(f.bar.backpack.take_button.disabled, "中断事件立即刷新书包")
		assert_true(f.hud._toast.text.contains("铃声"))
		_close_item_fixture(f)


func test_stale_snack_snapshot_is_revalidated_and_refreshed() -> void:
	var f := _item_fixture()
	var c: SimCore = f.core
	var me := c.node_count() - 1
	f.controller._refresh_bar()
	f.bar.open_backpack(&"eat_snack")
	c._snacks_remaining = 0
	f.bar.backpack.take_selected()
	assert_eq(int(c.inventory_of(me).snacks), 0)
	assert_false(c.is_busy(me))
	assert_eq(f.events.size(), 0, "拒绝使用不产生完成事件")
	f.bar.open_backpack(&"eat_snack")
	assert_true(f.bar.backpack.take_button.disabled)
	assert_true(f.bar.backpack.reason_label.text.contains("零食吃完"))
	_close_item_fixture(f)


func test_book_confiscation_updates_backpack_and_never_completes() -> void:
	var f := _item_fixture()
	var c: SimCore = f.core
	var me := c.node_count() - 1
	c._book[me] = 1
	c._stress[me] = 20.0
	f.controller._refresh_bar()
	f.bar.open_backpack(&"read_book")
	f.bar.backpack.take_selected()
	var finish := int(c._busy_until[me])
	f.bar.open_backpack(&"read_book")
	c._teacher.present = true
	assert_true(c._teacher.catch_reader(c, me))
	assert_eq(int(c.inventory_of(me).books), 0)
	assert_eq(
		int(c.inventory_of(me).confiscated_books), int(c._teacher.params.confiscate_books_per_catch)
	)
	assert_true(f.bar.backpack.take_button.disabled)
	assert_true(f.bar.backpack.reason_label.text.contains("老师保管"))
	assert_eq(f.hud._toast.text, "老师把书收走了。")
	c._global_tick = finish
	c._settle_finished_actions()
	c._end_phase()
	assert_eq(c.stress(me), 20.0)
	assert_eq(f.events.size(), 1)
	assert_eq(f.events[0].payload.kind, "book_confiscated")
	_close_item_fixture(f)


func test_last_snack_completion_keeps_empty_item_disabled() -> void:
	var f := _item_fixture()
	var c: SimCore = f.core
	var me := c.node_count() - 1
	c._snacks_remaining = 1
	f.controller._refresh_bar()
	f.bar.open_backpack(&"eat_snack")
	f.bar.backpack.take_selected()
	f.bar.open_backpack(&"eat_snack")
	c._global_tick = int(c._busy_until[me])
	c._settle_finished_actions()
	assert_eq(int(c.inventory_of(me).snacks), 0)
	assert_true(f.bar.backpack.take_button.disabled)
	assert_true(f.bar.backpack.reason_label.text.contains("零食吃完"))
	assert_false(f.bar.backpack._pictures[&"eat_snack"].visible)
	assert_eq(f.events.size(), 1)
	assert_eq(int(f.events[0].payload.snacks_remaining), 0)
	assert_eq(f.hud._toast.text, "最后一包了，你把它吃完了。")
	_close_item_fixture(f)


func test_all_items_finishing_exactly_at_bell_only_emit_completion() -> void:
	for kind in SimCore.LEISURE_KINDS:
		var f := _item_fixture()
		var c: SimCore = f.core
		var me := c.node_count() - 1
		c._book[me] = 1
		c._stress[me] = 20.0
		var prefix := str(SimCore.LEISURE_KINDS[kind])
		var boundary := int(c.time_snapshot().tick_count)
		c._global_tick = boundary - int(c._leisure[prefix + "_duration"])
		f.controller._refresh_bar()
		f.bar.open_backpack(StringName(kind))
		f.bar.backpack.take_selected()
		c._global_tick = boundary
		c._end_phase()
		assert_eq(c.stress(me), 20.0 - float(c._leisure[prefix + "_relief"]))
		assert_eq(f.events.size(), 1)
		assert_eq(f.events[0].payload.kind, "leisure_finished")
		assert_eq(f.events[0].activity, "")
		_close_item_fixture(f)
