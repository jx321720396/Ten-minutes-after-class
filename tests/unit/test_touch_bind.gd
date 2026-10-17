extends GutTest


func _touch(position: Vector2, pressed: bool, index: int = 0) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func _drag(position: Vector2, index: int = 0) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	return event


func _make_button() -> Button:
	var button := Button.new()
	button.size = Vector2(100.0, 50.0)
	add_child_autofree(button)
	await wait_process_frames(2)
	TouchBind.bind_button(button)
	return button


func test_tap_inside_emits_pressed() -> void:
	var button: Button = await _make_button()
	var hits := [0]
	button.pressed.connect(func() -> void: hits[0] += 1)
	button.gui_input.emit(_touch(Vector2(20.0, 20.0), true))
	button.gui_input.emit(_touch(Vector2(20.0, 20.0), false))
	assert_eq(hits[0], 1, "按钮内的单次点按应触发一次 pressed")


func test_drag_beyond_deadzone_cancels() -> void:
	var button: Button = await _make_button()
	var hits := [0]
	button.pressed.connect(func() -> void: hits[0] += 1)
	button.gui_input.emit(_touch(Vector2(20.0, 20.0), true))
	button.gui_input.emit(_drag(Vector2(80.0, 20.0)))
	button.gui_input.emit(_touch(Vector2(80.0, 20.0), false))
	assert_eq(hits[0], 0, "拖动超过死区后不应触发按钮")


func test_bind_is_idempotent() -> void:
	var button: Button = await _make_button()
	TouchBind.bind_button(button)
	var hits := [0]
	button.pressed.connect(func() -> void: hits[0] += 1)
	button.gui_input.emit(_touch(Vector2(20.0, 20.0), true))
	button.gui_input.emit(_touch(Vector2(20.0, 20.0), false))
	assert_eq(hits[0], 1, "重复绑定不得造成双触发")


func test_toggle_button_flips_state() -> void:
	var check := CheckButton.new()
	check.size = Vector2(100.0, 50.0)
	add_child_autofree(check)
	await wait_process_frames(2)
	TouchBind.bind_button(check)
	check.gui_input.emit(_touch(Vector2(20.0, 20.0), true))
	check.gui_input.emit(_touch(Vector2(20.0, 20.0), false))
	assert_true(check.button_pressed, "切换按钮应像原生点击一样翻转状态")


func test_slider_touch_sets_value() -> void:
	var root := Control.new()
	root.size = Vector2(200.0, 40.0)
	add_child_autofree(root)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	root.add_child(slider)
	slider.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await wait_process_frames(2)
	TouchBind.bind_slider(slider)
	slider.gui_input.emit(_touch(Vector2(150.0, 20.0), true))
	assert_almost_eq(slider.value, 75.0, 2.0, "触摸位置应换算成对应音量值")


func test_native_touch_subtree_is_skipped() -> void:
	var root := Control.new()
	root.set_meta("handles_native_touch", true)
	add_child_autofree(root)
	var button := Button.new()
	button.size = Vector2(100.0, 50.0)
	root.add_child(button)
	await wait_process_frames(2)
	TouchBind.bind_tree(root)
	assert_false(button.has_meta(TouchBind.META_BOUND), "原生触摸子树不应被重复绑定")
