extends PanelContainer
## 只读关注纸卡：预警按真实压力汇总；争吵必须有记录，不由敌对值推断。

signal student_requested(index: int)

const CampusTheme := preload("res://scripts/ui/campus_theme.gd")
const GameFonts := preload("res://scripts/ui/game_fonts.gd")

var _cfg: Dictionary = JSON.parse_string(
	FileAccess.get_file_as_string("res://data/ui/attention_card.json")
)
var _snapshot: Dictionary = {}
var _pressure: Button
var _conflict: Button
var _footer: Label
var _details: CanvasLayer
var _detail_heading: Label
var _detail_rows: VBoxContainer
var _detail_nodes: Dictionary = {}
var _detail_kind := ""


func _ready() -> void:
	custom_minimum_size = Vector2(float(_cfg.width), float(_cfg.height))
	var paper := CampusTheme.paper_card()
	paper.content_margin_left = float(_cfg.margins[0])
	paper.content_margin_top = float(_cfg.margins[1])
	paper.content_margin_right = float(_cfg.margins[2])
	paper.content_margin_bottom = float(_cfg.margins[3])
	add_theme_stylebox_override("panel", paper)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(_cfg.row_gap))
	add_child(rows)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", int(_cfg.icon_gap))
	rows.add_child(heading)
	var warning := TextureRect.new()
	warning.texture = load(str(_cfg.pressure_icon))
	warning.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	warning.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	warning.custom_minimum_size = Vector2.ONE * float(_cfg.icon_size)
	heading.add_child(warning)
	heading.add_child(_label(str(_cfg.title), int(_cfg.title_size)))
	_pressure = _row_button(
		"PressureButton", str(_cfg.pressure_icon), _open_details.bind("pressure")
	)
	rows.add_child(_pressure)
	_conflict = _row_button(
		"ConflictButton", str(_cfg.conflict_icon), _open_details.bind("conflicts")
	)
	rows.add_child(_conflict)
	_footer = _label("", int(_cfg.footer_size))
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_footer)
	_build_details()
	refresh({})


func refresh(snapshot_data: Dictionary) -> void:
	_snapshot = snapshot_data.duplicate()
	var pressures = _snapshot.get("high_pressure_students")
	var pressure_count := str(pressures.size()) if pressures is Array else str(_cfg.unknown)
	_pressure.text = "%s  %s 人  ›" % [_cfg.pressure_label, pressure_count]
	_pressure.tooltip_text = str(_cfg.pressure_details) % str(_cfg.warning_pressure)
	var theme := CampusTheme.settings()
	var pressure_active: bool = pressures is Array and not pressures.is_empty()
	_pressure.add_theme_color_override(
		"font_color", Color(str(theme.warning if pressure_active else theme.teal))
	)
	var records = _conflicts()
	var conflict_count := str(records.size()) if records is Array else str(_cfg.unknown)
	_conflict.text = "%s  %s 起  ›" % [_cfg.conflict_label, conflict_count]
	var conflict_active: bool = records is Array and not records.is_empty()
	_conflict.add_theme_color_override(
		"font_color", Color(str(theme.gold if conflict_active else theme.teal))
	)
	var counts: Dictionary = _snapshot.get("activity_counts", {})
	_footer.text = (
		str(_cfg.footer)
		% [
			str(counts.get("study", _cfg.unknown)),
			str(counts.get("entertainment", _cfg.unknown)),
			str(counts.get("other", _cfg.unknown))
		]
	)
	if _details.visible:
		_refresh_details()


func _conflicts() -> Variant:
	var records = _snapshot.get("ordinary_conflicts")
	if not records is Array:
		return null
	var latest := {}
	for index in range(records.size()):
		var record = records[index]
		if not record is Dictionary:
			continue
		var key := str(record.get("event_id", "record_%d" % index))
		latest[key] = record
	var result: Array = []
	for record in latest.values():
		if bool(record.get("active", true)):
			result.append(record)
	return result


func _open_details(kind: String) -> void:
	_detail_kind = kind
	_refresh_details()
	_details.show()


func _refresh_details() -> void:
	var desired := {}
	if _detail_kind == "pressure":
		_detail_heading.text = str(_cfg.pressure_details) % str(_cfg.warning_pressure)
		var entries = _snapshot.get("high_pressure_students")
		if entries is Array:
			for entry in entries:
				var index := int(entry.index)
				desired["Student_%d" % index] = {
					"text": str(_cfg.profile_row) % [entry.name, entry.pressure], "index": index
				}
		if desired.is_empty():
			desired["Empty"] = {
				"text": str(_cfg.empty_pressure if entries is Array else _cfg.unknown_pressure)
			}
	else:
		_detail_heading.text = str(_cfg.conflict_label)
		var records = _conflicts()
		if records is Array:
			for index in range(records.size()):
				var record: Dictionary = records[index]
				desired["Conflict_%s" % str(record.get("event_id", index))] = {
					"text": str(record.get("description", _cfg.conflict_label))
				}
		if desired.is_empty():
			desired["Empty"] = {"text": str(_cfg.empty_conflicts)}
	_sync_rows(desired)


## 保留现有按钮，仅更新文本，避免快照刷新中途打断点击。
func _sync_rows(desired: Dictionary) -> void:
	for key in _detail_nodes.keys():
		if not desired.has(key):
			var old: Node = _detail_nodes[key]
			_detail_rows.remove_child(old)
			old.queue_free()
			_detail_nodes.erase(key)
	for key in desired:
		var entry: Dictionary = desired[key]
		if not _detail_nodes.has(key):
			var row: Control
			if entry.has("index"):
				var button := _row_button(key, "", _request_student.bind(int(entry.index)))
				row = button
			else:
				var label := _label("", int(_cfg.detail_font_size))
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				row = label
			row.name = key
			_detail_rows.add_child(row)
			_detail_nodes[key] = row
		_detail_nodes[key].text = str(entry.text)


func _request_student(index: int) -> void:
	_details.hide()
	student_requested.emit(index)


func _row_button(node_name: String, icon: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size.y = float(_cfg.row_height)
	CampusTheme.button(button)
	button.add_theme_font_override("font", GameFonts.regular())
	button.add_theme_font_size_override("font_size", int(_cfg.row_font_size))
	if not icon.is_empty():
		button.icon = load(icon)
		button.add_theme_constant_override("icon_max_width", int(_cfg.icon_size))
		button.add_theme_constant_override("h_separation", int(_cfg.icon_gap))
	button.pressed.connect(action)
	return button


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", GameFonts.regular())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(CampusTheme.settings().teal))
	return label


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
	_detail_heading = _label("", int(_cfg.detail_title_size))
	rows.add_child(_detail_heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = float(_cfg.detail_scroll_height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	_detail_rows = VBoxContainer.new()
	_detail_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail_rows)
	var close := _row_button("CloseAttention", "", func() -> void: _details.hide())
	close.text = str(_cfg.close)
	rows.add_child(close)
	_details.hide()


func _unhandled_input(event: InputEvent) -> void:
	if _details.visible and event.is_action_pressed("ui_cancel"):
		_details.hide()
		get_viewport().set_input_as_handled()
