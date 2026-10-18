extends RefCounted
## 概念图对应的纯表现布局；只读结算快照，不持有或推进模拟。

const FONTS := preload("res://scripts/ui/game_fonts.gd")
const PORTRAITS := preload("res://scripts/ui/student_portraits.gd")

var _cfg: Dictionary
var _design: Dictionary
var _data: Dictionary
var _actions: Dictionary
var _core: Variant
var _page: Control


func build(
	page: Control,
	kind: String,
	data: Dictionary,
	core: Variant,
	config: Dictionary,
	actions: Dictionary
) -> void:
	_page = page
	_cfg = config
	_design = config.concept.layouts[kind]
	_data = data
	_core = core
	_actions = actions
	var paper := Panel.new()
	paper.add_theme_stylebox_override("panel", paper_style(config))
	_place(paper, _design.paper)
	_page.add_child(paper)
	var title := str(config.titles[kind])
	if kind == "exam":
		title = "首次周考" if int(data.day) == int(core._exam._days[0]) else "考试结算"
	_label(title, _design.title, int(config.concept.title_font), "ink", true, true)
	if kind == "exam":
		_label(
			"第 %d 天 · 全班 %d 人" % [int(data.day), int(data.count)],
			_design.subtitle,
			int(config.subtitle_font),
			"ink",
			true
		)
	elif kind == "end":
		_label(str(config.subtitles.end), _design.subtitle, int(config.subtitle_font), "ink", true)
	else:
		_banner(str(config.subtitles[kind]), _design.subtitle)
	match kind:
		"academic", "exam":
			_exam(kind)
		"dropout":
			_dropout()
		"end":
			_overview()
	_footer(kind)


static func paper_style(config: Dictionary) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(str(config.concept.paper_texture))
	return style


static func style_button(button: Button, config: Dictionary, primary: bool = false) -> void:
	var colors := ["normal", "hover", "pressed", "disabled"]
	var base := Color(config.orange if primary else config.paper)
	for i in colors.size():
		var style := StyleBoxFlat.new()
		style.bg_color = base.lightened(float(config.concept.hover_lighten)) if i == 1 else base
		if i == 2:
			style.bg_color = base.darkened(float(config.concept.hover_lighten))
		style.border_color = Color(config.concept.gold)
		style.set_border_width_all(int(config.concept.border_width))
		style.set_corner_radius_all(int(config.concept.button_radius))
		style.set_content_margin_all(float(config.concept.button_padding))
		style.shadow_color = Color(config.concept.shadow)
		style.shadow_size = int(config.concept.shadow_size)
		button.add_theme_stylebox_override(colors[i], style)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color(config.concept.gold)
	focus.set_border_width_all(int(config.concept.focus_width))
	focus.set_corner_radius_all(int(config.concept.button_radius))
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color(config.paper if primary else config.ink))
	button.add_theme_color_override(
		"font_hover_color", Color(config.paper if primary else config.ink)
	)
	button.add_theme_color_override(
		"font_pressed_color", Color(config.paper if primary else config.ink)
	)
	button.add_theme_color_override(
		"icon_normal_color", Color(config.paper if primary else config.ink)
	)
	button.add_theme_font_override("font", FONTS.demibold())
	button.add_theme_font_size_override("font_size", int(config.button_font))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_constant_override("icon_max_width", int(config.concept.button_icon))
	button.add_theme_constant_override("h_separation", int(config.concept.icon_gap))


func _exam(kind: String) -> void:
	_panel(_design.score_panel, "#fff9edb8")
	_label(str(_cfg.copy.mean), _design.mean_caption, int(_cfg.body_font), "ink", false, true)
	var score := _label(
		"%.1f" % float(_data.mean),
		_design.mean,
		int(_cfg.concept.score_font),
		"orange",
		false,
		true
	)
	score.name = "MeanValue"
	_panel(_design.target_panel, "#fff8e5")
	_label("目标均分", _design.target_caption, int(_cfg.small_font), "muted")
	_label(
		("%.1f" % float(_data.target)).trim_suffix(".0"),
		_design.target,
		int(_cfg.concept.stat_font),
		"ink",
		false,
		true
	)
	_panel(_design.gap_panel, "#f4ddca")
	_label("差距", _design.gap_caption, int(_cfg.small_font), "orange")
	_label(
		"%+.1f" % (float(_data.mean) - float(_data.target)),
		_design.gap,
		int(_cfg.concept.stat_font),
		"orange",
		false,
		true
	)
	if kind == "exam":
		var bar := ProgressBar.new()
		_place(bar, _design.bar)
		bar.show_percentage = false
		bar.max_value = maxf(1.0, float(_data.target))
		bar.value = float(_data.mean)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(_cfg.teal)
		fill.set_corner_radius_all(int(_cfg.concept.button_radius))
		bar.add_theme_stylebox_override("fill", fill)
		_page.add_child(bar)
		_label(
			"✓  " + str(_cfg.copy["pass"]),
			_design.stamp,
			int(_cfg.concept.stat_font),
			"teal",
			true,
			true
		)
	var note := str(_cfg.copy.exam_note if kind == "exam" else _cfg.copy.academic_note)
	_label(note, _design.note, int(_cfg.body_font), "ink")
	if kind == "academic":
		_label(str(_cfg.concept.quotes.academic), _design.quote, int(_cfg.small_font), "muted")


func _dropout() -> void:
	var entry: Dictionary = _data.dropouts[0]
	_label(str(_cfg.concept.quotes.dropout), _design.quote, int(_cfg.small_font), "muted")
	var photo := _panel(_design.photo, str(_cfg.paper))
	_photo(
		photo,
		str(_cfg.backgrounds.dropout),
		_cfg.concept.photo_inset,
		_cfg.concept.dropout_photo_region
	)
	var sheet := _panel(_design.record, str(_cfg.paper))
	sheet.rotation = float(_cfg.concept.sheet_rotation)
	var heading := _label("学生离校记录", _design.record_heading, int(_cfg.body_font), "ink", false, true)
	heading.reparent(sheet)
	heading.position = Vector2(_design.record_heading[0], _design.record_heading[1])
	_record_field(sheet, "姓名", str(entry.name), int(_cfg.concept.record_name_y))
	_record_field(sheet, "离校日", "第 %d 天" % int(_data.day), int(_cfg.concept.record_day_y))
	_record_field(
		sheet, "记录", "累计崩溃 %d 次" % int(entry.breakdowns), int(_cfg.concept.record_count_y)
	)
	_label("这个座位，暂时空下来了……", _design.photo_caption, int(_cfg.small_font), "muted")
	_label("本局触发", _design.cause_caption, int(_cfg.body_font), "ink", false, true)
	var cause := "累计崩溃 %d 次" % int(entry.breakdowns)
	if not str(entry.risk).is_empty() and int(entry.breakdowns) <= int(_core._risk._dropout_limit):
		cause = "%s后再次崩溃" % str({"bully": "霸凌", "isolate": "孤立"}.get(entry.risk, entry.risk))
	_label(cause, _design.cause, int(_cfg.concept.stat_font), "orange", false, true)
	var risk_name := {"bully": "霸凌", "isolate": "孤立"}
	var risk := str(risk_name.get(entry.risk, ""))
	var basis := "已达到累计崩溃退学判据"
	if not risk.is_empty():
		basis = "已正式触发%s，退学判据已满足" % risk
	var lines := [
		["已记录的学生状态", str(entry.name) + " · 累计崩溃 %d 次" % int(entry.breakdowns)],
		["本次结算依据", basis],
		["学生退学 · 任职终止", str(_cfg.copy.dropout_note)]
	]
	for i in lines.size():
		var top := float(_design.evidence[1]) + i * float(_cfg.concept.evidence_gap)
		var marker := _panel(
			[_design.evidence[0], top, _cfg.concept.marker_size, _cfg.concept.marker_size],
			"#ead9c5"
		)
		var number := Label.new()
		number.text = str(i + 1)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number.add_theme_font_override("font", FONTS.demibold())
		number.add_theme_font_size_override("font_size", int(_cfg.body_font))
		number.add_theme_color_override("font_color", Color(_cfg.orange if i == 2 else _cfg.ink))
		marker.add_child(number)
		number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var left := float(_design.evidence[0]) + float(_cfg.concept.evidence_text_offset)
		_label(
			lines[i][0],
			[left, top, _design.evidence[2], _cfg.concept.evidence_title_height],
			int(_cfg.body_font),
			"orange" if i == 2 else "ink",
			false,
			true
		)
		_label(
			lines[i][1],
			[
				left,
				top + float(_cfg.concept.evidence_detail_offset),
				_design.evidence[2],
				_cfg.concept.evidence_detail_height
			],
			int(_cfg.small_font),
			"muted"
		)
	_label("风险预警本身不直接导致退学。", _design.warning, int(_cfg.small_font), "muted")


func _record_field(sheet: Control, caption: String, value: String, top: int) -> void:
	var row := Label.new()
	row.add_theme_font_override("font", FONTS.regular())
	row.add_theme_font_size_override("font_size", int(_cfg.small_font))
	row.add_theme_color_override("font_color", Color(_cfg.ink))
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sheet.add_child(row)
	_place(
		row,
		[
			_cfg.concept.record_padding,
			top,
			_cfg.concept.record_width,
			_cfg.concept.record_row_height
		]
	)
	row.text = caption + "   " + value


func _overview() -> void:
	var values := [
		"%d 天" % int(_data.day), "%.1f 分" % float(_data.mean), "%d 人退学" % _data.dropouts.size()
	]
	var labels := ["带班天数", "班级均分", "学生状态"]
	var icons := ["calendar", "report", "students"]
	for i in labels.size():
		var rect: Array = _design.stats[i]
		_panel(rect, str(_cfg.paper))
		_icon(
			icons[i],
			[
				rect[0] + float(_cfg.concept.stat_icon_x),
				rect[1] + float(_cfg.concept.stat_icon_y),
				_cfg.concept.stat_icon_size,
				_cfg.concept.stat_icon_size
			]
		)
		var left := float(rect[0]) + float(_cfg.concept.stat_text_x)
		_label(
			labels[i],
			[
				left,
				rect[1] + float(_cfg.concept.stat_caption_y),
				_cfg.concept.stat_text_width,
				_cfg.concept.stat_caption_height
			],
			int(_cfg.body_font),
			"ink",
			false,
			true
		)
		_label(
			values[i],
			[
				left,
				rect[1] + float(_cfg.concept.stat_value_y),
				_cfg.concept.stat_text_width,
				_cfg.concept.stat_value_height
			],
			int(_cfg.concept.stat_font),
			"ink"
		)
	_banner("班级的变化", _design.memory_title, "ink")
	_label(
		"%d 张不同的面孔，\n在这一段课间里，\n留下各自的选择，\n也有了新的连接。" % int(_data.count),
		_design.memory_note,
		int(_cfg.body_font),
		"ink"
	)
	_memory_photo()
	var scores := _button(
		str(_cfg.concept.score_review), _design.score_link, _actions.scores, false, "report"
	)
	scores.tooltip_text = "查看本局全部学生的成绩"
	_button(str(_cfg.copy.relations), _design.relation_link, _actions.relations, false, "relations")


func _memory_photo() -> void:
	var frame := _panel(_design.memory_photo, str(_cfg.paper))
	frame.clip_contents = true
	_photo(frame, str(_cfg.backgrounds.end), _cfg.concept.photo_inset)
	var profile_cfg: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/npc_profile.json")
	)
	var columns := int(_cfg.concept.portrait_columns)
	var width := float(_design.memory_photo[2]) / columns
	var row_height := float(_cfg.concept.portrait_row_height)
	for i in _data.students.size():
		var entry: Dictionary = _data.students[i]
		var portrait := TextureRect.new()
		portrait.name = "StudentMemory%d" % int(entry.index)
		portrait.texture = PORTRAITS.texture_for(
			str(_core.character_id(int(entry.index))), profile_cfg
		)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(portrait)
		_place(
			portrait,
			[(i % columns) * width, (i / columns) * row_height, width, _cfg.concept.portrait_height]
		)
		var name_label := Label.new()
		name_label.text = str(entry.name)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_override("font", FONTS.demibold())
		name_label.add_theme_font_size_override("font_size", int(_cfg.concept.portrait_name_font))
		name_label.add_theme_color_override("font_color", Color(_cfg.ink))
		var strip := StyleBoxFlat.new()
		strip.bg_color = Color(_cfg.concept.name_strip)
		name_label.add_theme_stylebox_override("normal", strip)
		frame.add_child(name_label)
		_place(
			name_label,
			[
				(i % columns) * width,
				(i / columns) * row_height + float(_cfg.concept.portrait_height),
				width,
				_cfg.concept.portrait_name_height
			]
		)


func _footer(kind: String) -> void:
	var footer := HBoxContainer.new()
	_place(footer, _design.footer)
	footer.add_theme_constant_override("separation", int(_cfg.gap))
	_page.add_child(footer)
	var entries: Array = []
	match kind:
		"exam":
			entries = [
				[_cfg.copy.scores, "scores", false], [_cfg.copy["continue"], "continue", true]
			]
		"academic":
			entries = [[_cfg.copy.review, "review", false], [_cfg.copy.restart, "restart", true]]
		"dropout":
			entries = [
				[_cfg.copy.events, "events", false],
				[_cfg.copy.review, "review", false],
				[_cfg.copy.restart, "restart", true]
			]
		"end":
			entries = [[_cfg.copy.restart, "restart", true], [_cfg.copy.menu, "menu", false]]
	for item in entries:
		var button := Button.new()
		button.text = str(item[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = float(_cfg.button_height)
		button.icon = load(str(_cfg.concept.icons[str(item[1])]))
		style_button(button, _cfg, bool(item[2]))
		button.pressed.connect(_actions[str(item[1])])
		footer.add_child(button)


func _photo(frame: Control, path: String, inset: Array, region: Array = []) -> void:
	var image := TextureRect.new()
	image.texture = load(path)
	if region.size() == 4:
		var crop := AtlasTexture.new()
		crop.atlas = image.texture
		crop.region = Rect2(region[0], region[1], region[2], region[3])
		crop.filter_clip = true
		image.texture = crop
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(image)
	_place(
		image,
		[
			inset[0],
			inset[1],
			frame.size.x - float(inset[0]) * 2.0,
			frame.size.y - float(inset[1]) * 2.0
		]
	)


func _banner(text: String, rect: Array, color: String = "orange") -> void:
	var brush := TextureRect.new()
	brush.texture = load(str(_cfg.concept.brush_texture))
	brush.modulate = Color(_cfg[color])
	brush.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page.add_child(brush)
	_place(brush, rect)
	_label(text, rect, int(_cfg.concept.banner_font), "paper", true, true)


func _panel(rect: Array, color: String) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color)
	style.border_color = Color(_cfg.line)
	style.set_border_width_all(int(_cfg.concept.border_width))
	style.set_corner_radius_all(int(_cfg.concept.card_radius))
	style.shadow_color = Color(_cfg.concept.shadow)
	style.shadow_size = int(_cfg.concept.shadow_size)
	panel.add_theme_stylebox_override("panel", style)
	_page.add_child(panel)
	_place(panel, rect)
	return panel


func _icon(key: String, rect: Array) -> void:
	var icon := TextureRect.new()
	icon.texture = load(str(_cfg.concept.icons[key]))
	icon.modulate = Color(_cfg.ink)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_page.add_child(icon)
	_place(icon, rect)


func _button(text: String, rect: Array, action: Callable, primary: bool, icon: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = load(str(_cfg.concept.icons[icon]))
	style_button(button, _cfg, primary)
	button.pressed.connect(action)
	_page.add_child(button)
	_place(button, rect)
	return button


func _label(
	text: String,
	rect: Array,
	font_size: int,
	color: String = "ink",
	center: bool = false,
	bold: bool = false
) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", FONTS.demibold() if bold else FONTS.regular())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(_cfg[color]))
	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page.add_child(label)
	_place(label, rect)
	label.text = text
	return label


func _place(view: Control, rect: Array) -> void:
	view.position = Vector2(rect[0], rect[1])
	view.size = Vector2(rect[2], rect[3])
