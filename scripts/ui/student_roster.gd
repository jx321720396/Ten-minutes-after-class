extends Control
## 全屏座位档案；只发出操作意图，命令仍由 OfficeHub 提交内核。

signal student_selected(index: int)
signal seat_requested(first: int, second: int)
signal closed

const STYLE = preload("res://scripts/ui/npc_profile_theme.gd")
const PORTRAITS = preload("res://scripts/ui/student_portraits.gd")

var cards: Array[Button] = []
var grid: GridContainer
var confirm: Button
var _design: Control
var _title: Label
var _hint: Label
var _message: Label
var _profile_tab: Button
var _seats_tab: Button
var _cancel: Button
var _core: Variant
var _mode := "profile"
var _first := -1
var _second := -1
var _config: Dictionary
var _portraits: Dictionary
var _seats: Dictionary = {}


func _ready() -> void:
	_config = (
		JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/office_hub.json")).roster
	)
	_portraits = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/npc_profile.json"))
	for entry in ConfigLoader.new().get_table("rules/seats").get("rows", []):
		_seats[str(entry.seat_id)] = entry
	theme = STYLE.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_design = Control.new()
	add_child(_design)
	var paper := Panel.new()
	_design.add_child(paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.add_theme_stylebox_override("panel", STYLE.box(STYLE.PAPER, STYLE.PAPER, 0, 0))
	var grain := ColorRect.new()
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/shaders/ui_paper.gdshader")
	grain.material = material
	paper.add_child(grain)
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	_design.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, int(_config.margin))
	var rows := VBoxContainer.new()
	margin.add_child(rows)
	rows.add_theme_constant_override("separation", int(_config.gap))
	var header := HBoxContainer.new()
	rows.add_child(header)
	_button(header, _config.copy.back).pressed.connect(func() -> void: closed.emit())
	_title = _label(header, _config.copy.title, int(_config.title_size))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_tab = _button(header, _config.copy.profile)
	_profile_tab.toggle_mode = true
	_profile_tab.pressed.connect(set_mode.bind("profile"))
	_seats_tab = _button(header, _config.copy.seats)
	_seats_tab.toggle_mode = true
	_seats_tab.pressed.connect(set_mode.bind("seats"))
	_hint = _label(rows, "", int(_config.small_size))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid = GridContainer.new()
	grid.columns = int(_config.columns)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", int(_config.gap))
	grid.add_theme_constant_override("v_separation", int(_config.gap))
	rows.add_child(grid)
	var footer := HBoxContainer.new()
	rows.add_child(footer)
	_message = _label(footer, "", int(_config.small_size))
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cancel = _button(footer, _config.copy.cancel)
	_cancel.pressed.connect(clear_selection)
	confirm = _button(footer, _config.copy.confirm)
	confirm.add_theme_stylebox_override(
		"normal", STYLE.box(STYLE.INK, STYLE.INK, int(_config.radius), int(_config.border))
	)
	confirm.add_theme_color_override("font_color", STYLE.PAPER)
	confirm.pressed.connect(_confirm)
	get_viewport().size_changed.connect(_fit)
	_fit()
	hide()
	TouchBind.bind_tree(self)


func open(core: Variant, mode: String) -> void:
	_core = core
	set_mode(mode)
	show()
	_fit()


func set_mode(mode: String) -> void:
	_mode = mode
	clear_selection()
	_title.text = str(_config.copy.title if mode in ["profile", "seats"] else _config.copy[mode])
	_hint.text = str(_config.copy.seat_hint if mode == "seats" else _config.copy.profile_hint)
	_profile_tab.visible = mode in ["profile", "seats"]
	_seats_tab.visible = _profile_tab.visible
	_cancel.visible = mode == "seats"
	confirm.visible = mode == "seats"
	_profile_tab.set_pressed_no_signal(mode == "profile")
	_seats_tab.set_pressed_no_signal(mode == "seats")
	_rebuild_cards()


func clear_selection() -> void:
	_first = -1
	_second = -1
	_refresh_selection()


func select_student(index: int) -> void:
	if _mode != "seats":
		student_selected.emit(index)
		return
	if index == _first:
		_first = _second
		_second = -1
	elif index == _second:
		_second = -1
	elif _first < 0:
		_first = index
	else:
		_second = index
	_refresh_selection()


func show_message(message: String) -> void:
	_message.text = message


## 换座完成后的留页刷新（2026-10-19 裁定：换座不耗时，老师可以接着换下一组）。
## 按新座位重排卡片、清空已选，并给出这一组的换座结果。
func refresh_after_seat_change(first: int, second: int) -> void:
	_first = -1
	_second = -1
	_rebuild_cards()
	if _core == null or first < 0 or second < 0:
		return
	show_message(str(_config.copy.seat_done) % [str(_core.alias(first)), str(_core.alias(second))])


func _confirm() -> void:
	if _first >= 0 and _second >= 0:
		seat_requested.emit(_first, _second)


func _rebuild_cards() -> void:
	for card in cards:
		grid.remove_child(card)
		card.queue_free()
	cards.clear()
	if _core == null:
		return
	var ordered: Array[int] = []
	for index in range(_core.node_count()):
		ordered.append(index)
	ordered.sort_custom(
		func(a: int, b: int) -> bool:
			var left: Dictionary = _seats[str(_core.seat_of(a))]
			var right: Dictionary = _seats[str(_core.seat_of(b))]
			return (
				int(left.row) < int(right.row)
				or (int(left.row) == int(right.row) and int(left.col) < int(right.col))
			)
	)
	for index in ordered:
		_add_card(index)
	_refresh_selection()
	_fit()


func _add_card(index: int) -> void:
	var card := Button.new()
	card.clip_contents = true
	card.set_meta("student_index", index)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	grid.add_child(card)
	cards.append(card)
	card.pressed.connect(select_student.bind(index))
	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.texture = PORTRAITS.texture_for(str(_core.character_id(index)), _portraits)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.add_child(portrait)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.anchor_right = float(_config.portrait_fraction)
	portrait.offset_left = float(_config.card_padding)
	portrait.offset_top = float(_config.card_padding)
	portrait.offset_bottom = -float(_config.card_padding)
	var details := VBoxContainer.new()
	card.add_child(details)
	details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	details.anchor_left = float(_config.portrait_fraction)
	details.offset_right = -float(_config.card_padding)
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	_label(details, str(_core.alias(index)), int(_config.name_size))
	var seat: Dictionary = _seats[str(_core.seat_of(index))]
	_label(
		details,
		str(_config.copy.seat) % [int(seat.row), int(seat.col) + 1],
		int(_config.small_size)
	)
	var badge := _label(details, "", int(_config.small_size))
	badge.name = "Badge"
	_ignore_pointer(card)
	TouchBind.bind_button(card)


func _ignore_pointer(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_pointer(child)


func _refresh_selection() -> void:
	if confirm == null:
		return
	confirm.disabled = _first < 0 or _second < 0
	_message.text = str(_config.copy.idle)
	if _core != null and _first >= 0:
		_message.text = str(_core.alias(_first))
		if _second >= 0:
			_message.text += "  ↔  " + str(_core.alias(_second))
	for card in cards:
		var index := int(card.get_meta("student_index"))
		var selected := index == _first or index == _second
		var color := STYLE.GOLD if index == _second else STYLE.INK
		card.add_theme_stylebox_override(
			"normal",
			STYLE.box(
				STYLE.PAPER,
				color if selected else STYLE.LINE,
				int(_config.radius),
				int(_config.selected_border) if selected else int(_config.border)
			)
		)
		var badge: Label = card.get_child(1).get_node("Badge")
		badge.text = (
			str(_config.copy.selected if index == _first else _config.copy.target)
			if selected
			else ""
		)


func _fit() -> void:
	if _design == null:
		return
	var view := get_viewport_rect().size
	var base := Vector2(_config.design_size[0], _config.design_size[1])
	var factor := minf(view.x / base.x, view.y / base.y)
	_design.scale = Vector2.ONE * factor
	_design.size = view / factor


func _button(parent: Node, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = float(_config.button_height)
	button.add_theme_font_size_override("font_size", int(_config.button_size))
	parent.add_child(button)
	return button


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
