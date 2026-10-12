extends Control
## 只读环境音量纸卡；数值与阈值由时钟快照提供。

const CampusTheme := preload("res://scripts/ui/campus_theme.gd")
const GameFonts := preload("res://scripts/ui/game_fonts.gd")

var value := 0.0
var _maximum := 0.0
var _threshold := 0.0
var _cfg: Dictionary = CampusTheme.settings().volume_card
var _paper := CampusTheme.paper_card()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(_cfg.width, _cfg.height)
	size = custom_minimum_size
	hide()


func refresh(snapshot_data: Dictionary) -> void:
	_maximum = float(snapshot_data.get("volume_max", 0.0))
	_threshold = float(snapshot_data.get("volume_threshold", 0.0))
	visible = _maximum > 0.0
	value = clampf(float(snapshot_data.get("volume", 0.0)), 0.0, _maximum)
	queue_redraw()


func _draw() -> void:
	if _maximum <= 0.0:
		return
	var theme := CampusTheme.settings()
	var ink := Color(theme.teal)
	var fill := ink
	if value > _threshold:
		fill = Color(theme.warning) if value / _maximum >= _cfg.high_fraction else Color(theme.gold)
	draw_style_box(_paper, Rect2(Vector2.ZERO, size))
	var font := GameFonts.regular()
	var left := float(_cfg.left)
	# 声波图标与标题，沿用纸面主题。
	for index in _cfg.wave_heights.size():
		var height := float(_cfg.wave_heights[index])
		var x: float = left + index * float(_cfg.wave_gap)
		draw_line(
			Vector2(x, _cfg.heading_y - height),
			Vector2(x, _cfg.heading_y),
			ink,
			_cfg.wave_width,
			true
		)
	draw_string(
		font,
		Vector2(left + _cfg.heading_indent, _cfg.heading_y),
		"教室音量",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		_cfg.heading_size,
		ink
	)
	var number := str(roundi(value))
	draw_string(
		font,
		Vector2(left, _cfg.number_y),
		number,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		_cfg.number_size,
		fill
	)
	var width := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, _cfg.number_size).x
	draw_string(
		font,
		Vector2(left + width + _cfg.number_gap, _cfg.number_y),
		"/ %d" % roundi(_maximum),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		_cfg.maximum_size,
		Color(theme.muted)
	)
	var bar := Rect2(left, _cfg.bar_y, size.x - left - _cfg.right, _cfg.bar_height)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(theme.disabled)
	background.set_corner_radius_all(_cfg.bar_radius)
	draw_style_box(background, bar)
	var filled := background.duplicate() as StyleBoxFlat
	filled.bg_color = fill
	draw_style_box(filled, Rect2(bar.position, Vector2(bar.size.x * value / _maximum, bar.size.y)))
	var marker: float = bar.position.x + bar.size.x * _threshold / _maximum
	draw_line(
		Vector2(marker, bar.position.y - _cfg.marker_extra),
		Vector2(marker, bar.end.y + _cfg.marker_extra),
		ink,
		_cfg.marker_width,
		true
	)
	draw_string(
		font,
		Vector2(marker - _cfg.marker_label_half_width, _cfg.threshold_y),
		str(roundi(_threshold)),
		HORIZONTAL_ALIGNMENT_CENTER,
		_cfg.marker_label_half_width * 2,
		_cfg.hint_size,
		ink
	)
	var hint := "声音开始影响同学" if value > _threshold else "教室声音平稳"
	draw_string(
		font,
		Vector2(left, _cfg.hint_y),
		hint,
		HORIZONTAL_ALIGNMENT_RIGHT,
		bar.size.x,
		_cfg.hint_size,
		fill
	)
