class_name TouchBind
extends RefCounted
## 统一触摸绑定：项目关闭了 `emulate_mouse_from_touch`，内置 Button / Slider
## 不会响应 InputEventScreenTouch。这里为没有手写触摸逻辑的界面补上最小实现。
##
## 约定：
##   · 已手写触摸的控件由调用方设置 `touch_bound` 元数据，本工具自动跳过；
##   · 祖先节点带 `handles_native_touch` 的子树整体跳过（与 office_hub 的约定一致）；
##   · 拖动超过 DEADZONE 视为滚动，不触发按钮；
##   · 切换按钮（toggle_mode）按原生行为先翻转 button_pressed，再发 pressed；
##   · 带 meta "emit_hold" 的按钮额外转发 button_down / button_up，供按住蓄力等交互。

const DEADZONE := 12.0
const META_BOUND := "touch_bound"
const META_INDEX := "touch_index"
const META_START := "touch_start"
const META_HOLD := "emit_hold"


static func bind_tree(root: Node) -> void:
	if root is Button:
		bind_button(root as Button)
	elif root is Slider:
		bind_slider(root as Slider)
	for child in root.get_children():
		bind_tree(child)


static func bind_button(button: Button) -> void:
	if button.has_meta(META_BOUND) or _has_native_touch_ancestor(button):
		return
	button.set_meta(META_BOUND, true)
	button.gui_input.connect(_on_button_input.bind(button))


static func bind_slider(slider: Slider) -> void:
	if slider.has_meta(META_BOUND) or _has_native_touch_ancestor(slider):
		return
	slider.set_meta(META_BOUND, true)
	slider.gui_input.connect(_on_slider_input.bind(slider))


static func _has_native_touch_ancestor(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if bool(current.get_meta("handles_native_touch", false)):
			return true
		current = current.get_parent()
	return false


static func _on_button_input(event: InputEvent, button: Button) -> void:
	if Input.emulate_mouse_from_touch:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if button.disabled or not button.is_visible_in_tree():
				return
			if not button.has_meta(META_INDEX):
				button.set_meta(META_INDEX, touch.index)
				button.set_meta(META_START, touch.position)
				if button.has_meta(META_HOLD):
					button.button_down.emit()
		elif int(button.get_meta(META_INDEX, -1)) == touch.index:
			var start: Vector2 = button.get_meta(META_START, touch.position)
			button.remove_meta(META_INDEX)
			button.remove_meta(META_START)
			if button.has_meta(META_HOLD):
				button.button_up.emit()
			if touch.canceled or button.disabled or not button.is_visible_in_tree():
				return
			if start.distance_to(touch.position) > DEADZONE:
				return
			if Rect2(Vector2.ZERO, button.size).has_point(touch.position):
				_activate(button)
		button.accept_event()
	elif event is InputEventScreenDrag and button.has_meta(META_INDEX):
		var start: Vector2 = button.get_meta(META_START, event.position)
		if event.position.distance_to(start) > DEADZONE:
			if button.has_meta(META_HOLD):
				button.button_up.emit()
			button.remove_meta(META_INDEX)
			button.remove_meta(META_START)
		if button.has_meta(META_HOLD):
			button.accept_event()


static func _activate(button: Button) -> void:
	if button.toggle_mode:
		button.button_pressed = not button.button_pressed
	button.pressed.emit()


static func _on_slider_input(event: InputEvent, slider: Slider) -> void:
	if Input.emulate_mouse_from_touch:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if not slider.editable:
				return
			slider.set_meta(META_INDEX, touch.index)
			_set_slider_from_position(slider, touch.position)
		elif int(slider.get_meta(META_INDEX, -1)) == touch.index:
			slider.remove_meta(META_INDEX)
		slider.accept_event()
	elif event is InputEventScreenDrag and int(slider.get_meta(META_INDEX, -1)) == event.index:
		_set_slider_from_position(slider, event.position)
		slider.accept_event()


static func _set_slider_from_position(slider: Slider, position: Vector2) -> void:
	var horizontal := slider is HSlider
	var extent := slider.size.x if horizontal else slider.size.y
	if extent <= 0.0:
		return
	var offset := position.x if horizontal else position.y
	var ratio := clampf(offset / extent, 0.0, 1.0)
	slider.value = lerpf(slider.min_value, slider.max_value, ratio)
