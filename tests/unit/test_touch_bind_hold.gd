extends GutTest
## 按住蓄力的触摸转发（2026-10-19）：项目关闭了 emulate_mouse_from_touch，
## 带 emit_hold 元数据的按钮必须在触摸按下/抬起时补发 button_down / button_up。

func _button_with_root() -> Button:
	var root := Control.new()
	root.size = Vector2(200, 100)
	add_child_autofree(root)
	var button := Button.new()
	root.add_child(button)
	button.size = Vector2(100, 40)
	button.set_meta("emit_hold", true)
	TouchBind.bind_button(button)
	return button


func _touch(pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	event.position = position
	return event


func test_emit_hold_forwards_touch_down_and_up() -> void:
	var button := _button_with_root()
	var counts := {"down": 0, "up": 0}
	button.button_down.connect(func() -> void: counts["down"] += 1)
	button.button_up.connect(func() -> void: counts["up"] += 1)
	button.gui_input.emit(_touch(true, Vector2(10, 10)))
	assert_eq(int(counts["down"]), 1, "触摸按下 → button_down")
	button.gui_input.emit(_touch(false, Vector2(10, 10)))
	assert_eq(int(counts["up"]), 1, "触摸抬起 → button_up")


func test_drag_ends_hold_without_click() -> void:
	var button := _button_with_root()
	var counts := {"down": 0, "up": 0, "click": 0}
	button.button_down.connect(func() -> void: counts["down"] += 1)
	button.button_up.connect(func() -> void: counts["up"] += 1)
	button.pressed.connect(func() -> void: counts["click"] += 1)
	button.gui_input.emit(_touch(true, Vector2(10, 10)))
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(40, 10)
	button.gui_input.emit(drag)
	assert_eq(int(counts["down"]), 1)
	assert_eq(int(counts["up"]), 1, "拖动超过死区 → 结束按住，不触发点击")
	assert_eq(int(counts["click"]), 0)
