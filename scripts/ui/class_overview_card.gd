extends PanelContainer
## 班级概况：只读时钟快照；没有的数据保留为空，不用旧压力推导新动力。

const CampusTheme := preload("res://scripts/ui/campus_theme.gd")
const GameFonts := preload("res://scripts/ui/game_fonts.gd")

var _cfg: Dictionary = JSON.parse_string(
	FileAccess.get_file_as_string("res://data/ui/class_overview_card.json")
)
var _values: Dictionary = {}
var _maximum: Label
var _footer: Label
var _details: CanvasLayer
var _detail_text: Label
var _snapshot: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(float(_cfg.width), float(_cfg.height))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", int(_cfg.row_gap))
	add_child(content)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", int(_cfg.icon_gap))
	content.add_child(heading)
	heading.add_child(_icon("board", float(_cfg.heading_icon_size)))
	heading.add_child(_label(str(_cfg.title), int(_cfg.title_size)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	content.add_child(grid)
	for metric in _cfg.metrics:
		grid.add_child(_cell(metric))
	_footer = _label("", int(_cfg.footer_size))
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_footer)
	var button := Button.new()
	button.name = "OverviewButton"
	button.text = str(_cfg.button)
	button.custom_minimum_size.y = float(_cfg.button_height)
	button.pressed.connect(_open_details)
	content.add_child(button)
	CampusTheme.button(button)
	button.add_theme_font_override("font", GameFonts.regular())
	button.add_theme_font_size_override("font_size", int(_cfg.button_size))
	var paper := CampusTheme.paper_card()
	paper.content_margin_left = float(_cfg.margins[0])
	paper.content_margin_top = float(_cfg.margins[1])
	paper.content_margin_right = float(_cfg.margins[2])
	paper.content_margin_bottom = float(_cfg.margins[3])
	add_theme_stylebox_override("panel", paper)
	_build_details()
	refresh({})


func refresh(snapshot_data: Dictionary) -> void:
	_snapshot = snapshot_data.duplicate()
	var lines := PackedStringArray()
	for metric in _cfg.metrics:
		var value = _snapshot.get(str(metric.key))
		var number := _number(value, str(metric.key) == "class_average_academic_gain")
		var label: Label = _values[str(metric.key)]
		label.text = number
		label.tooltip_text = str(_cfg.unknown_hint) if value == null else str(metric.label)
		lines.append("%s：%s" % [metric.label, number])
	var maximum := float(_snapshot.get("grade_max", 0.0))
	_maximum.text = "/%d" % int(maximum) if maximum > 0.0 else ""
	var count := int(_snapshot.get("student_count", 0))
	_footer.text = str(_cfg.footer) % (str(count) if count > 0 else str(_cfg.unknown))
	_detail_text.text = "\n\n".join(lines) + "\n\n" + _footer.text


func _number(value: Variant, signed: bool) -> String:
	if value == null:
		return str(_cfg.unknown)
	var number := float(value)
	var text := ("%.1f" % number).trim_suffix(".0")
	return "+" + text if signed and number > 0.0 else text


func _cell(metric: Dictionary) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var theme := CampusTheme.settings()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(str(theme.paper))
	style.border_color = Color(str(theme.line))
	style.set_border_width_all(int(_cfg.cell_border))
	style.set_corner_radius_all(int(_cfg.cell_radius))
	style.set_content_margin_all(float(_cfg.cell_padding))
	cell.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(_cfg.icon_gap))
	cell.add_child(rows)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", int(_cfg.icon_gap))
	rows.add_child(heading)
	heading.add_child(_icon(str(metric.icon), float(_cfg.icon_size)))
	heading.add_child(_label(str(metric.label), int(_cfg.label_size)))
	var numbers := HBoxContainer.new()
	numbers.add_theme_constant_override("separation", int(_cfg.icon_gap))
	rows.add_child(numbers)
	var value := _label("", int(_cfg.value_size))
	value.name = str(metric.name) + "Value"
	numbers.add_child(value)
	_values[str(metric.key)] = value
	if str(metric.key) == "class_average_grade":
		_maximum = _label("", int(_cfg.maximum_size))
		_maximum.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		numbers.add_child(_maximum)
	return cell


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", GameFonts.regular())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(CampusTheme.settings().teal))
	return label


func _icon(key: String, diameter: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load("res://assets/icons/actions/%s.svg" % key)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2.ONE * diameter
	return icon


func _build_details() -> void:
	_details = CanvasLayer.new()
	_details.name = "Details"
	_details.layer = int(_cfg.detail_layer)
	add_child(_details)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, float(_cfg.backdrop_alpha))
	_details.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_details.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = float(_cfg.detail_width)
	center.add_child(panel)
	var paper := CampusTheme.paper_card()
	paper.content_margin_left = float(_cfg.detail_margins[0])
	paper.content_margin_top = float(_cfg.detail_margins[1])
	paper.content_margin_right = float(_cfg.detail_margins[2])
	paper.content_margin_bottom = float(_cfg.detail_margins[3])
	panel.add_theme_stylebox_override("panel", paper)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(_cfg.row_gap))
	panel.add_child(rows)
	rows.add_child(_label("全班概况", int(_cfg.detail_title_size)))
	_detail_text = _label("", int(_cfg.detail_font_size))
	rows.add_child(_detail_text)
	var close := Button.new()
	close.name = "CloseOverview"
	close.text = str(_cfg.close)
	close.custom_minimum_size.y = float(_cfg.detail_button_height)
	close.pressed.connect(func() -> void: _details.hide())
	rows.add_child(close)
	CampusTheme.button(close)
	close.add_theme_font_override("font", GameFonts.regular())
	close.add_theme_font_size_override("font_size", int(_cfg.button_size))
	_details.hide()


func _open_details() -> void:
	_details.show()


func _unhandled_input(event: InputEvent) -> void:
	if _details.visible and event.is_action_pressed("ui_cancel"):
		_details.hide()
		get_viewport().set_input_as_handled()
