extends ScrollContainer
## 为关闭触摸模拟鼠标的移动端提供单指拖动滚动。

const TOUCH_SCROLL_DEADZONE := 12.0

var _touch_active := false
var _touch_last := Vector2.ZERO
var _touch_distance := 0.0


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_touch_active = false
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index != 0:
			return
		if touch.pressed and get_global_rect().has_point(touch.position):
			_touch_active = true
			_touch_last = touch.position
			_touch_distance = 0.0
		elif not touch.pressed:
			_touch_active = false
			_touch_last = Vector2.ZERO
			_touch_distance = 0.0
		return
	if event is InputEventScreenDrag and _touch_active:
		var drag := event as InputEventScreenDrag
		var delta := drag.position - _touch_last
		_touch_last = drag.position
		_touch_distance += delta.length()
		if _touch_distance < TOUCH_SCROLL_DEADZONE:
			return
		if vertical_scroll_mode != SCROLL_MODE_DISABLED:
			var max_vertical := int(get_v_scroll_bar().max_value)
			scroll_vertical = clampi(scroll_vertical - int(delta.y), 0, max_vertical)
		if horizontal_scroll_mode != SCROLL_MODE_DISABLED:
			var max_horizontal := int(get_h_scroll_bar().max_value)
			scroll_horizontal = clampi(scroll_horizontal - int(delta.x), 0, max_horizontal)
		get_viewport().set_input_as_handled()
