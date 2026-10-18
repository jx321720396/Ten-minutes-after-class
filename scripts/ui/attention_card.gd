extends PanelContainer
## 只读风险关注纸卡：霸凌／孤立读取日末判定，崩溃读取当前状态。

signal student_requested(index: int)

const CampusTheme := preload("res://scripts/ui/campus_theme.gd")
const GameFonts := preload("res://scripts/ui/game_fonts.gd")

var _cfg: Dictionary = JSON.parse_string(
	FileAccess.get_file_as_string("res://data/ui/attention_card.json")
)
var _snapshot: Dictionary = {}
var _risk_rows: Dictionary = {}
var _risk_data: Dictionary = {}
var _details: CanvasLayer
var _detail_heading: Label
var _detail_panel: PanelContainer
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
	# 文字居中：图标 + 标题整体居中
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_theme_constant_override("separation", int(_cfg.icon_gap))
	rows.add_child(heading)
	var warning := TextureRect.new()
	warning.texture = load(str(_cfg.pressure_icon))
	warning.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	warning.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	warning.custom_minimum_size = Vector2.ONE * float(_cfg.icon_size)
	heading.add_child(warning)
	heading.add_child(_label(str(_cfg.title), int(_cfg.title_size)))
	for kind in ["bully", "isolate", "broken", "crash"]:
		rows.add_child(_risk_button(kind))
	var details := _row_button("RiskDetailsButton", "", _open_details.bind("all"))
	details.text = str(_cfg.details_label)
	details.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	rows.add_child(details)
	_build_details()
	TouchBind.bind_tree(self)
	refresh({})


func refresh(snapshot_data: Dictionary) -> void:
	_snapshot = snapshot_data.duplicate(true)
	_risk_data = _snapshot.get("risk_attention", {})
	for kind in _risk_rows:
		var view: Dictionary = _risk_rows[kind]
		var entries = _risk_data.get(kind)
		var known: bool = entries is Array
		var active: bool = known and not entries.is_empty()
		view.count.text = "%s人" % [str(entries.size()) if known else str(_cfg.unknown)]
		var subtitle := str(_cfg.empty_subtitle if known else _cfg.unknown_subtitle)
		if kind == "broken":
			subtitle = str(_cfg.broken_subtitle if active else _cfg.empty_broken_subtitle)
			if not known:
				subtitle = str(_cfg.unknown_subtitle)
		elif kind == "crash":
			if active:
				subtitle = (
					str(_cfg.crash_subtitle)
					% [int(_cfg.crash_pressure_min), int(_cfg.crash_pressure_max)]
				)
			else:
				subtitle = str(_cfg.empty_crash_subtitle)
			if not known:
				subtitle = str(_cfg.unknown_subtitle)
		elif active:
			var formal := false
			var streak := 0
			for entry in entries:
				formal = formal or bool(entry.formal)
				streak = maxi(streak, int(entry.streak))
			subtitle = (
				str(_cfg.formal_subtitle)
				if formal
				else str(_cfg.warning_subtitle) % [streak, _window()]
			)
		view.subtitle.text = subtitle
		_style_risk_row(view, kind == "broken", active)
	if _details.visible:
		_refresh_details()


func _window() -> int:
	return int(_risk_data.get("rules", {}).get("window_days", 0))


func _risk_button(kind: String) -> Button:
	var prefix := kind.capitalize()
	var button := _row_button(prefix + "Button", "", _open_details.bind(kind))
	button.custom_minimum_size.y = float(_cfg.row_height)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(_cfg.row_padding))
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", int(_cfg.icon_gap))
	margin.add_child(content)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2.ONE * float(_cfg.badge_size)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(badge)
	var exclamation := _label("!", int(_cfg.row_font_size))
	exclamation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exclamation.add_theme_color_override("font_color", Color.WHITE)
	badge.add_child(exclamation)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	content.add_child(texts)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 行内文字居中：标题 + 人数作为一组居中（不再把人数推到右侧）
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_child(line)
	var title := _label(str(_cfg[kind + "_label"]), int(_cfg.row_font_size))
	title.add_theme_font_override("font", GameFonts.demibold())
	line.add_child(title)
	var count := _label("", int(_cfg.row_font_size))
	count.name = prefix + "Count"
	count.custom_minimum_size.x = float(_cfg.count_width)
	line.add_child(count)
	var subtitle := _label("", int(_cfg.subtitle_size))
	subtitle.name = prefix + "Subtitle"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_child(subtitle)
	var arrow := _label("›", int(_cfg.row_font_size))
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(arrow)
	_risk_rows[kind] = {
		"button": button,
		"badge": badge,
		"title": title,
		"count": count,
		"subtitle": subtitle,
		"arrow": arrow
	}
	return button


func _style_risk_row(view: Dictionary, critical: bool, active: bool) -> void:
	var prefix := "critical" if critical else "warning"
	var ink := Color(str(_cfg[prefix + "_ink"] if active else _cfg.empty_ink))
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(str(_cfg[prefix + "_fill"] if active else _cfg.empty_fill))
		if state != "normal":
			style.bg_color = style.bg_color.darkened(float(_cfg.hover_darken))
		style.border_color = Color(str(_cfg[prefix + "_border"]))
		style.set_border_width_all(int(_cfg.row_border))
		style.set_corner_radius_all(int(_cfg.row_radius))
		view.button.add_theme_stylebox_override(state, style)
	var circle := StyleBoxFlat.new()
	circle.bg_color = Color(str(_cfg[prefix + "_badge"] if active else _cfg.empty_ink))
	circle.set_corner_radius_all(int(_cfg.badge_size))
	view.badge.add_theme_stylebox_override("panel", circle)
	for key in ["title", "count", "subtitle", "arrow"]:
		view[key].add_theme_color_override("font_color", ink)


func _open_details(kind: String) -> void:
	_detail_kind = kind
	_refresh_details()
	_details.show()


## 日末由 TimeHUD 转调：强制收起风险详情弹层，避免 layer 31 盖在推理板（layer 6）之上。
func close_details() -> void:
	if _details != null:
		_details.hide()


func _refresh_details() -> void:
	_detail_heading.text = str(_cfg.risk_heading)
	var desired := {}
	var kinds: Array = (
		["broken", "bully", "isolate", "crash"] if _detail_kind == "all" else [_detail_kind]
	)
	for kind in kinds:
		var entries = _risk_data.get(kind)
		if not entries is Array or entries.is_empty():
			continue
		desired["Heading_" + kind] = {"text": str(_cfg[kind + "_label"])}
		for entry in entries:
			var index := int(entry.index)
			var key := "%s_%d" % [kind, index]
			var status := (
				str(_cfg.formal_subtitle) if bool(entry.formal) else str(_cfg[kind + "_label"])
			)
			desired["Student_%d_%s" % [index, kind]] = {
				"text": str(_cfg.detail_student) % [entry.name, status], "index": index
			}
			desired[key + "_Evidence"] = {"text": _evidence(kind, entry)}
			desired[key + "_Next"] = {"text": _next_text(kind, entry)}
			desired[key + "_Actions"] = {"text": str(_cfg["actions_" + kind])}
	if desired.is_empty():
		desired["Empty"] = {
			"text": str(_cfg.unknown_risks if _risk_data.is_empty() else _cfg.no_risks)
		}
	desired["Note"] = {"text": str(_cfg.risk_note)}
	_sync_rows(desired)


func _next_text(kind: String, entry: Dictionary) -> String:
	if kind == "broken":
		return str(_cfg.broken_next)
	if kind == "crash":
		return str(_cfg.crash_next) % int(_cfg.crash_pressure_min)
	return str(_cfg.formal_next if bool(entry.formal) else _cfg.warning_next)


func _evidence(kind: String, entry: Dictionary) -> String:
	if kind == "broken" or kind == "crash":
		return (
			str(_cfg.detail_breakdowns) % [snappedf(float(entry.pressure), 0.1), entry.breakdowns]
		)
	var rules: Dictionary = _risk_data.get("rules", {})
	var evidence: String
	if kind == "bully":
		evidence = (
			str(_cfg.bully_evidence)
			% [
				int(rules.get("bully_min_enemies", 0)),
				int(rules.get("bully_hostility_threshold", 0)),
				int(rules.get("bully_daily_harm_min", 0))
			]
		)
	else:
		evidence = (
			str(_cfg.isolate_evidence)
			% [
				int(rules.get("isolate_affinity_threshold", 0)),
				int(rules.get("isolate_daily_rejects", 0))
			]
		)
	var source := (
		str(_cfg.detail_day) % entry.day if int(entry.day) > 0 else str(_cfg.detail_unknown_day)
	)
	return (
		"%s\n%s\n%s\n%s"
		% [
			source,
			evidence,
			str(_cfg.detail_streak) % [entry.streak, _window()],
			str(_cfg.detail_window) % _window()
		]
	)


## 保留现有按钮，仅更新文本，避免快照刷新中途打断点击。
func _sync_rows(desired: Dictionary) -> void:
	for key in _detail_nodes.keys():
		if not desired.has(key):
			var old: Node = _detail_nodes[key]
			_detail_rows.remove_child(old)
			old.queue_free()
			_detail_nodes.erase(key)
	var position := 0
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
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				row = label
			row.name = key
			_detail_rows.add_child(row)
			_detail_nodes[key] = row
		_detail_nodes[key].text = str(entry.text)
		_detail_rows.move_child(_detail_nodes[key], position)
		position += 1


func _request_student(index: int) -> void:
	_details.hide()
	student_requested.emit(index)


func _row_button(node_name: String, icon: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size.y = float(_cfg.detail_button_height)
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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_detail_panel = panel
	panel.custom_minimum_size.x = float(_cfg.detail_width)
	center.add_child(panel)
	var paper := preload("res://scripts/ui/npc_profile_theme.gd").box(
		Color(CampusTheme.settings().paper), Color(CampusTheme.settings().paper), 0, 0
	)
	paper.content_margin_left = float(_cfg.detail_margins[0])
	paper.content_margin_top = float(_cfg.detail_margins[1])
	paper.content_margin_right = float(_cfg.detail_margins[2])
	paper.content_margin_bottom = float(_cfg.detail_margins[3])
	panel.add_theme_stylebox_override("panel", paper)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(_cfg.row_gap))
	panel.add_child(rows)
	_detail_heading = _label("", int(_cfg.detail_title_size))
	_detail_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_detail_heading)
	var scroll := ScrollContainer.new()
	scroll.name = "RiskScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)
	_detail_rows = VBoxContainer.new()
	_detail_rows.add_theme_constant_override("separation", int(_cfg.row_gap))
	_detail_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail_rows)
	var close := _row_button("CloseAttention", "", func() -> void: _details.hide())
	close.text = str(_cfg.close)
	rows.add_child(close)
	_details.hide()


func _process(_delta: float) -> void:
	if is_instance_valid(_details):
		preload("res://scripts/ui/fullscreen_panel.gd").fit(
			_detail_panel.get_parent(), _detail_panel, Vector2(1280, 720)
		)


func _unhandled_input(event: InputEvent) -> void:
	if _details.visible and event.is_action_pressed("ui_cancel"):
		_details.hide()
		get_viewport().set_input_as_handled()
