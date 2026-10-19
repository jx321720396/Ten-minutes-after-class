extends CanvasLayer
## 纸面考试／辞退／本局回顾。所有展示数据来自已结算结果。

signal continue_requested

const MODEL := preload("res://scripts/game/outcome_snapshot.gd")
const FONTS := preload("res://scripts/ui/game_fonts.gd")
const ARCHIVE := preload("res://scripts/game/term_archive.gd")
const LAYOUT := preload("res://scripts/ui/outcome_layout.gd")
const TOUCH_SCROLL := preload("res://scripts/ui/touch_scroll_container.gd")
const SETTINGS := "res://data/ui/outcome_screen.json"
const HOLD := &"outcome_screen"

var _cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
var _core: Variant
var _clock: SimulationClock
var _report: CanvasLayer
var _data: Dictionary = {}
var _record: Dictionary = {}
var _root: Control
var _canvas: Control
var _background: TextureRect
var _page: Control
var _details: Control


func _ready() -> void:
	layer = int(_cfg.layer)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_root.add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(_cfg.shade)
	_root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas = Control.new()
	_canvas.size = Vector2(_cfg.design_size[0], _cfg.design_size[1])
	_root.add_child(_canvas)
	_root.resized.connect(_layout)
	_layout()
	hide()


func bind_sources(core: Variant, clock: SimulationClock, report: CanvasLayer = null) -> void:
	if is_instance_valid(_clock):
		_clock.report_ready.disconnect(_on_boundary)
		_clock.term_finished.disconnect(_on_boundary)
		_clock.release(HOLD)
	_core = core
	_clock = clock
	_report = report
	_clock.report_ready.connect(_on_boundary)
	_clock.term_finished.connect(_on_boundary)
	_on_boundary(int(_clock.snapshot().ended_day))


func _exit_tree() -> void:
	if is_instance_valid(_clock):
		_clock.release(HOLD)


func _layout() -> void:
	if _canvas == null:
		return
	var design := Vector2(_cfg.design_size[0], _cfg.design_size[1])
	var factor := minf(_root.size.x / design.x, _root.size.y / design.y)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (_root.size - design * factor) / 2.0


func _on_boundary(_day: int) -> void:
	var data: Dictionary = MODEL.new().build(_core, _clock.snapshot())
	if data.is_empty():
		return
	if visible and data == _data:
		return
	_data = data
	_clock.hold(HOLD)
	if bool(data.finished):
		_record = MODEL.new().archive_record(_core, data)
		var error := ARCHIVE.write(_record)
		if error != OK:
			push_warning("本局回顾归档失败：%s" % error_string(error))
	_render(str(data.kind))
	show()


func continue_exam() -> void:
	if not visible or not bool(_data.get("can_continue", false)):
		return
	_data.can_continue = false
	hide()
	_clock.release(HOLD)
	continue_requested.emit()


func show_overview() -> void:
	_render("end")


func _render(kind: String) -> void:
	for child in _canvas.get_children():
		_canvas.remove_child(child)
		child.queue_free()
	_details = null
	_background.texture = load(str(_cfg.backgrounds[kind]))
	_page = Control.new()
	_page.size = _canvas.size
	_canvas.add_child(_page)
	LAYOUT.new().build(
		_page,
		kind,
		_data,
		_core,
		_cfg,
		{
			"scores": show_scores,
			"events": show_dropout_records,
			"relations": _open_relations,
			"review": show_overview,
			"continue": continue_exam,
			"restart": _restart,
			"menu": _menu
		}
	)
	TouchBind.bind_tree(_page)


func show_scores() -> void:
	var rows := _open_details("班级成绩明细")
	var ordered: Array = _data.students.duplicate(true)
	ordered.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score)
	)
	for entry in ordered:
		_text(
			rows,
			"%s                         %d 分" % [entry.name, int(round(float(entry.score)))],
			int(_cfg.body_font)
		)


func show_dropout_records() -> void:
	var rows := _open_details("学生退学 · 已结算记录")
	for entry in _data.dropouts:
		_text(rows, str(entry.name), int(_cfg.stat_font))
		_text(rows, "累计崩溃 %d 次" % int(entry.breakdowns), int(_cfg.body_font), "orange")
		var risk_name := {"bully": "霸凌", "isolate": "孤立"}
		if not str(entry.risk).is_empty():
			_text(rows, "已正式触发 " + str(risk_name.get(entry.risk, entry.risk)), int(_cfg.body_font))
	var limits := {}
	for row in ConfigLoader.new().load_all().get("rules/risk", {}).get("rows", []):
		limits[str(row.param)] = float(row.value)
	_text(rows, "退学判据", int(_cfg.body_font))
	_text(
		rows,
		(
			"累计崩溃超过 %d 次；或正式触发霸凌／孤立后再崩溃 %d 次。"
			% [
				int(limits.get("dropout_breakdown_limit", 0)),
				int(limits.get("dropout_after_risk_breakdowns", 0))
			]
		),
		int(_cfg.small_font),
		"muted"
	)


func _open_details(title: String) -> VBoxContainer:
	_page.hide()
	_details = Control.new()
	_details.size = _canvas.size
	_canvas.add_child(_details)
	var paper := PanelContainer.new()
	_rect(paper, _cfg.paper_rect)
	paper.add_theme_stylebox_override("panel", LAYOUT.paper_style(_cfg))
	_details.add_child(paper)
	var column := _column(_details)
	_rect(column, _cfg.detail_rect)
	_text(column, title, int(_cfg.stat_font))
	var scroll := ScrollContainer.new()
	scroll.set_script(TOUCH_SCROLL)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := _column(scroll)
	var footer := HBoxContainer.new()
	_rect(footer, _cfg.footer_rect)
	_details.add_child(footer)
	_button(footer, str(_cfg.copy.back), _close_details)
	TouchBind.bind_tree(_details)
	return rows


func _close_details() -> void:
	if is_instance_valid(_details):
		_details.queue_free()
	_page.show()


func _open_relations() -> void:
	if is_instance_valid(_report) and not _record.is_empty():
		_report.open_record(_record)


func _restart() -> void:
	_leave(true)


func _menu() -> void:
	_leave(false)


func _leave(restart: bool) -> void:
	get_tree().paused = false
	_clock.release(HOLD)
	GameState.end_game()
	GameState.new_game_requested = restart
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _column(parent: Node) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(_cfg.gap))
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	return column


func _text(parent: Node, text: String, font_size: int, color: String = "ink") -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONTS.regular())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(_cfg[color]))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _rect(view: Control, values: Array) -> void:
	view.position = Vector2(values[0], values[1])
	view.size = Vector2(values[2], values[3])


func _button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = float(_cfg.button_height)
	button.add_theme_font_override("font", FONTS.demibold())
	button.add_theme_font_size_override("font_size", int(_cfg.button_font))
	LAYOUT.style_button(button, _cfg, primary)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
