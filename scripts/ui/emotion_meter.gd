class_name EmotionMeter
extends Control
## 五格图形，填充裁剪在图标内部；不以文字显示隐藏数值。

const SETTINGS := "res://data/ui/term_report.json"
const AXES := ["affinity", "hostility"]

var _cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
var _axis := "affinity"
var _value := 0.0
var _display_value := 0.0
var _direction := 0
var _arrow_left := 0.0
var _tween: Tween


func _ready() -> void:
	custom_minimum_size = Vector2(_cfg.meter_size[0], _cfg.meter_size[1])
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_emotion(axis: String, value: float, direction: int = 0, animate: bool = false) -> void:
	_axis = axis
	_value = clampf(value, 0.0, float(_cfg.axis_max))
	_direction = direction
	_arrow_left = float(_cfg.arrow_seconds) if direction != 0 else 0.0
	if _tween != null:
		_tween.kill()
	if animate and is_inside_tree():
		_tween = create_tween()
		_tween.tween_method(_set_display_value, _display_value, _value, float(_cfg.fill_seconds))
	else:
		_set_display_value(_value)
	queue_redraw()


func _set_display_value(value: float) -> void:
	_display_value = value
	queue_redraw()


func fills() -> Array:
	return _fractions(_value)


func change_direction() -> int:
	return _direction if _arrow_left > 0.0 else 0


func _fractions(value: float) -> Array:
	var result: Array = []
	var count := int(_cfg.icon_count)
	var units := value / float(_cfg.axis_max) * float(count)
	for i in count:
		result.append(clampf(units - float(i), 0.0, 1.0))
	return result


func _process(delta: float) -> void:
	if _arrow_left > 0.0:
		_arrow_left = maxf(0.0, _arrow_left - delta)
		queue_redraw()


func _draw() -> void:
	var index := AXES.find(_axis)
	var color := Color(str(_cfg.axis_colors[maxi(0, index)]))
	var empty := Color(str(_cfg.empty_color))
	var values := _fractions(_display_value)
	var slot := size.x / float(int(_cfg.icon_count) + 1)
	var edge := minf(size.y * 0.85, slot * 0.85)
	for i in values.size():
		var origin := Vector2(float(i) * slot + (slot - edge) / 2.0, (size.y - edge) / 2.0)
		var polygon := _shape()
		for p in polygon.size():
			polygon[p] = polygon[p] * edge + origin
		draw_colored_polygon(polygon, Color(empty, 0.12))
		var clipped := _clip_bottom(polygon, origin.y + edge * (1.0 - float(values[i])))
		if clipped.size() >= 3 and float(values[i]) > 0.0:
			draw_colored_polygon(clipped, color)
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline, color if float(values[i]) > 0.0 else empty, 1.2, true)
	if change_direction() != 0:
		var x := slot * float(values.size()) + slot / 2.0
		var top := size.y * 0.23
		var bottom := size.y * 0.77
		draw_line(Vector2(x, top), Vector2(x, bottom), color, 2.5, true)
		var tip := top if _direction > 0 else bottom
		var tail := tip + (size.y * 0.2 if _direction > 0 else -size.y * 0.2)
		draw_polyline(
			PackedVector2Array(
				[Vector2(x - edge * 0.22, tail), Vector2(x, tip), Vector2(x + edge * 0.22, tail)]
			),
			color,
			2.5,
			true
		)


func _shape() -> PackedVector2Array:
	if _axis == "hostility":
		return PackedVector2Array(
			[
				Vector2(0.63, 0.0),
				Vector2(0.13, 0.58),
				Vector2(0.47, 0.58),
				Vector2(0.32, 1.0),
				Vector2(0.87, 0.38),
				Vector2(0.55, 0.38)
			]
		)
	var points := PackedVector2Array()
	for i in int(_cfg.icon_samples):
		var angle := TAU * float(i) / float(_cfg.icon_samples)
		var x := 16.0 * pow(sin(angle), 3.0)
		var y := (
			13.0 * cos(angle) - 5.0 * cos(2.0 * angle) - 2.0 * cos(3.0 * angle) - cos(4.0 * angle)
		)
		points.append(Vector2((x + 16.0) / 32.0, (12.0 - y) / 29.0))
	return points


func _clip_bottom(points: PackedVector2Array, cut: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var previous := points[-1]
	for current in points:
		var prev_inside := previous.y >= cut
		var inside := current.y >= cut
		if inside != prev_inside:
			result.append(previous.lerp(current, (cut - previous.y) / (current.y - previous.y)))
		if inside:
			result.append(current)
		previous = current
	return result
