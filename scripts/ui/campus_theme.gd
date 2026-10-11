class_name CampusTheme
extends RefCounted
## 校园纸面主题（表现层）。颜色与邀请卡尺寸来自 data/ui/campus_theme.json。
## 只改控件外观，不读玩法状态。

const _PATH := "res://data/ui/campus_theme.json"

static var _cached: Settings


class Settings extends RefCounted:
	var event_card_width := 320.0
	var event_card_height := 112.0
	var event_stack_gap := 12.0
	var paper := Color(0.980392, 0.960784, 0.901961, 0.941176)
	var ink := Color(0.129412, 0.160784, 0.156863)
	var accent := Color(0.160784, 0.380392, 0.258824)
	var gold := Color(0.749020, 0.533333, 0.207843)
	var muted := Color(0.341176, 0.376471, 0.352941)
	var corner_radius := 8
	var border_width := 2
	var content_margin := 12.0
	var font_size := 16


static func settings() -> Settings:
	if _cached == null:
		_cached = _load()
	return _cached


static func apply_tree(root: Node) -> void:
	var theme := _make_theme()
	for child in root.get_children():
		if child is Control:
			(child as Control).theme = theme


static func paper_card() -> StyleBoxFlat:
	var look := settings()
	return _box(look.paper, look.ink, look.corner_radius, look.border_width, look.content_margin)


static func _load() -> Settings:
	var look := Settings.new()
	if not FileAccess.file_exists(_PATH):
		return look
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return look
	var data: Dictionary = parsed
	look.event_card_width = float(data.get("event_card_width", look.event_card_width))
	look.event_card_height = float(data.get("event_card_height", look.event_card_height))
	look.event_stack_gap = float(data.get("event_stack_gap", look.event_stack_gap))
	look.paper = _color(data.get("paper", ""), look.paper)
	look.ink = _color(data.get("ink", ""), look.ink)
	look.accent = _color(data.get("accent", ""), look.accent)
	look.gold = _color(data.get("gold", ""), look.gold)
	look.muted = _color(data.get("muted", ""), look.muted)
	look.corner_radius = int(data.get("corner_radius", look.corner_radius))
	look.border_width = int(data.get("border_width", look.border_width))
	look.content_margin = float(data.get("content_margin", look.content_margin))
	look.font_size = int(data.get("font_size", look.font_size))
	return look


static func _color(value: Variant, fallback: Color) -> Color:
	return Color.from_string(str(value), fallback)


static func _make_theme() -> Theme:
	var look := settings()
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(
		["Microsoft YaHei", "微软雅黑", "SimHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"]
	)
	theme.default_font = font
	theme.default_font_size = look.font_size
	theme.set_color("font_color", "Label", look.ink)
	theme.set_color("font_color", "Button", look.ink)
	theme.set_color("font_hover_color", "Button", look.ink)
	theme.set_color("font_focus_color", "Button", look.ink)
	theme.set_color("font_pressed_color", "Button", Color(1, 0.976, 0.906))
	theme.set_color("font_disabled_color", "Button", look.muted)
	theme.set_stylebox("normal", "Button", _box(look.paper, look.accent, look.corner_radius, 1, 8.0))
	theme.set_stylebox("hover", "Button", _box(Color(0.910, 0.933, 0.875), look.ink, look.corner_radius, 2, 8.0))
	theme.set_stylebox("pressed", "Button", _box(look.accent, look.accent, look.corner_radius, 2, 8.0))
	theme.set_stylebox("disabled", "Button", _box(Color(0.914, 0.898, 0.847), look.muted, look.corner_radius, 1, 8.0))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), look.gold, look.corner_radius, 2, 8.0))
	return theme


static func _box(fill: Color, border: Color, radius: int, width: int, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style
