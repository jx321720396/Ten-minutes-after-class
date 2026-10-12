extends Control
## 只读展示信念比例；旋转与落点为演出，不产生随机数或回写内核。

var probability := 0.0
var pen: TextureRect
var _cfg: Dictionary
var _font: Font


func configure(config: Dictionary) -> void:
	_cfg = config
	custom_minimum_size = Vector2.ONE * float(_cfg.diameter)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = preload("res://scripts/ui/game_fonts.gd").regular()

	pen = TextureRect.new()
	pen.name = "Pen"
	pen.texture = load("res://assets/textures/ui/interaction/campus_spinning_pen.svg")
	pen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pen)
	resized.connect(_layout_pen)
	_layout_pen()


func set_probability(value: float) -> void:
	probability = clampf(value, 0.0, 1.0)
	queue_redraw()


func _layout_pen() -> void:
	var diameter := minf(size.x, size.y)
	pen.size = Vector2(
		diameter * float(_cfg.pen_width_fraction), diameter * float(_cfg.pen_height_fraction)
	)
	pen.pivot_offset = pen.size / 2.0
	pen.position = size / 2.0 - pen.size / 2.0
	queue_redraw()


func result_angle(accepted: bool) -> float:
	var failure_arc := TAU * (1.0 - probability)
	return (
		-PI / 2.0 + failure_arc + TAU * probability / 2.0
		if accepted
		else -PI / 2.0 + failure_arc / 2.0
	)


func _draw() -> void:
	if _cfg == null or _cfg.is_empty():
		return
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - float(_cfg.rim_padding)
	draw_circle(center, radius, Color(_cfg.success_color))
	var failure_arc := TAU * (1.0 - probability)
	if probability < 1.0:
		var points := PackedVector2Array([center])
		for step in range(int(_cfg.arc_segments) + 1):
			var angle := -PI / 2.0 + failure_arc * float(step) / float(_cfg.arc_segments)
			points.append(center + Vector2.from_angle(angle) * radius)
		draw_colored_polygon(points, Color(_cfg.failure_color))
	if probability > 0.0 and probability < 1.0:
		for angle in [-PI / 2.0, -PI / 2.0 + failure_arc]:
			draw_line(
				center,
				center + Vector2.from_angle(angle) * radius,
				Color(_cfg.line_color),
				float(_cfg.rim_width),
				true
			)
	draw_arc(
		center,
		radius,
		0.0,
		TAU,
		int(_cfg.arc_segments),
		Color(_cfg.line_color),
		float(_cfg.rim_width),
		true
	)
	_draw_sector_label(center, radius, true)
	_draw_sector_label(center, radius, false)


func _draw_sector_label(center: Vector2, radius: float, success: bool) -> void:
	var fraction := probability if success else 1.0 - probability
	if fraction < float(_cfg.label_min_fraction):
		return
	var offset := minf(float(_cfg.label_angle_offset), TAU * fraction / 4.0)
	var label_angle := result_angle(success) + (offset if success else -offset)
	var location := (
		center + Vector2.from_angle(label_angle) * radius * float(_cfg.label_radius_fraction)
	)
	var font_size := int(_cfg.label_font_size)
	var text := "%s %d%%" % ["成功" if success else "失败", roundi(fraction * 100.0)]
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(
		_font,
		location + Vector2(-width / 2.0, font_size / 3.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(_cfg.line_color)
	)
