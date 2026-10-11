extends RefCounted
## 档案专用纸张主题；只设置表现属性，不读取玩法状态。

const INK := Color("284536")
const MUTED := Color("7c8274")
const GOLD := Color("bf8835")
const PAPER := Color("f5f0df")
const LINE := Color("cfc8b0")


static func make_theme() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(
		["Microsoft YaHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"]
	)
	theme.default_font = font
	theme.default_font_size = 28
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", Color("fff9e7"))
	theme.set_color("font_disabled_color", "Button", Color("929487"))
	theme.set_stylebox("normal", "Button", box(Color("f8f4e7"), LINE, 8, 1))
	theme.set_stylebox("hover", "Button", box(Color("e8eedf"), INK, 8, 2))
	theme.set_stylebox("pressed", "Button", box(INK, INK, 8, 2))
	theme.set_stylebox("disabled", "Button", box(Color("e9e5d8"), LINE, 8, 1))
	theme.set_stylebox("focus", "Button", box(Color.TRANSPARENT, GOLD, 8, 2))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var button_box := theme.get_stylebox(state, "Button")
		button_box.content_margin_top = 8
		button_box.content_margin_bottom = 8
	for type in ["OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type, theme.get_stylebox(state, "Button"))
		for state in [
			"font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"
		]:
			theme.set_color(state, type, theme.get_color(state, "Button"))
	theme.set_stylebox("panel", "PopupMenu", box(PAPER, INK, 8, 2))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_stylebox("hover", "PopupMenu", box(INK, INK, 4, 0))
	theme.set_constant("v_separation", "PopupMenu", 12)
	var separator := StyleBoxLine.new()
	separator.color = LINE
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)
	var vertical := separator.duplicate() as StyleBoxLine
	vertical.vertical = true
	theme.set_stylebox("separator", "VSeparator", vertical)
	theme.set_stylebox("scroll", "VScrollBar", box(Color("e8e4d5"), Color.TRANSPARENT, 4, 0))
	for style in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(style, "VScrollBar", box(Color("98a18b"), Color.TRANSPARENT, 4, 0))
	return theme


static func box(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(12)
	return style


static func apply(view: Node) -> void:
	view.get_node("%Design").theme = make_theme()
	var frame := box(PAPER, INK, 18, 3)
	frame.shadow_color = Color(0.05, 0.1, 0.07, 0.3)
	frame.shadow_size = 24
	view.get_node("%Frame").add_theme_stylebox_override("panel", frame)
	for name in ["RelationCard", "HistoryCard"]:
		view.get_node("%" + name).add_theme_stylebox_override(
			"panel", box(Color(1, 0.98, 0.91, 0.4), LINE, 10, 1)
		)
	view.get_node("%PortraitFrame").add_theme_stylebox_override(
		"panel", box(Color("ece5d1"), Color("e4d8bc"), 4, 1)
	)
	view.get_node("%JudgmentCard").add_theme_stylebox_override(
		"panel", box(Color("e6e8db"), Color("c7cfba"), 10, 1)
	)
	for name in [
		"Subtitle", "KnownNote", "Seat", "HistoryNote", "JudgmentNote", "Footer", "UnknownNote"
	]:
		view.get_node("%" + name).add_theme_color_override("font_color", MUTED)
	view.get_node("%StaleNote").add_theme_color_override("font_color", GOLD)
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["SimSun", "Songti SC", "Noto Serif CJK SC", "serif"])
	for name in ["Title", "PersonName", "KnownTitle", "HistoryTitle", "EncountersTitle"]:
		view.get_node("%" + name).add_theme_font_override("font", title_font)
