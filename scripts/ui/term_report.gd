class_name TermReport
extends CanvasLayer
## 期末纸面报告。只读归档；回放使用展示副本，永不推进内核。

const CampusTheme := preload("res://scripts/ui/campus_theme.gd")
const METER := preload("res://scripts/ui/emotion_meter.gd")
const REPLAY := preload("res://scripts/game/term_replay.gd")
const ARCHIVE := preload("res://scripts/game/term_archive.gd")
const SETTINGS := "res://data/ui/term_report.json"
const AXES := ["affinity", "hostility"]

var _cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
var _record: Dictionary = {}
var _core: Variant
var _clock: SimulationClock
var _actors: Node
var _replay: RefCounted = REPLAY.new()
var _root: Control
var _sidebar: VBoxContainer
var _content: VBoxContainer
var _relations: VBoxContainer
var _stats: ScrollContainer
var _stats_rows: VBoxContainer
var _summary: VBoxContainer
var _detail: VBoxContainer
var _matrix: ScrollContainer
var _grid: GridContainer
var _meters: Array = []
var _matrix_meters: Array = []
var _from: OptionButton
var _to: OptionButton
var _axis_select: OptionButton
var _slider: HSlider
var _position_label: Label
var _event_label: Label
var _play_button: Button
var _source := 0
var _target := 0
var _matrix_axis := 0
var _playing := false
var _elapsed := 0.0
var _speed := 1.0


func _ready() -> void:
	layer = int(_cfg.layer)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	TouchBind.bind_tree(self)
	hide()


func bind_sources(
	core: Variant, clock: SimulationClock, actors: Node = null, auto_open: bool = true
) -> void:
	if _clock != null and _clock.term_finished.is_connected(_on_term_finished):
		_clock.term_finished.disconnect(_on_term_finished)
	_core = core
	_clock = clock
	_actors = actors
	if auto_open:
		_clock.term_finished.connect(_on_term_finished)
	if auto_open and str(_clock.snapshot().mode) == SimulationClock.MODE_FINISHED:
		_on_term_finished(int(_clock.snapshot().ended_day))


func _on_term_finished(_ended_day: int) -> void:
	var history: Dictionary = _core.term_record()
	if not open_record(history):
		push_error("TermReport：期末记录不完整，不能补造关系回放。")
		return
	var error := ARCHIVE.write(history)
	if error != OK:
		push_warning("学期报告归档失败：%s；本次仍可查看。" % error_string(error))


func open_record(history: Dictionary) -> bool:
	if not ARCHIVE.valid(history):
		return false
	_record = history.duplicate(true)
	_replay.configure(_record)
	_source = 0 if _record.has("teacher_outcome") else int(_record.player)
	_target = 1 if _record.has("teacher_outcome") else 0
	_from.clear()
	_to.clear()
	for i in int(_record.count):
		_from.add_item(str(_record.names[i]), i)
		_to.add_item(str(_record.names[i]), i)
	_from.select(_source)
	_to.select(_target)
	_slider.max_value = maxf(1.0, float(_replay.last_tick()))
	_fill_sidebar()
	_fill_stats()
	_fill_summary()
	_build_details()
	_clear(_grid)
	_matrix_meters.clear()
	_show_page("relations")
	show()
	_playing = not _record.frames.is_empty()
	_elapsed = 0.0
	_refresh(false)
	return true


func record() -> Dictionary:
	return _record.duplicate(true)


func seek_tick(tick: int) -> void:
	_replay.seek_tick(tick)
	_elapsed = 0.0
	_refresh(false)


func advance_replay() -> void:
	while _replay.step():
		if _matrix.visible or _replay.affects_pair(_source, _target):
			_refresh(true)
			return
	_playing = false
	_refresh(false)


func _process(delta: float) -> void:
	if not visible or not _playing or not _relations.visible:
		return
	_elapsed += delta * _speed
	if _elapsed >= float(_cfg.frame_seconds):
		_elapsed = 0.0
		advance_replay()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		if event.is_action_pressed("ui_accept"):
			_toggle_play()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var theme := Theme.new()
	theme.default_font = preload("res://scripts/ui/game_fonts.gd").regular()
	theme.default_font_size = int(_cfg.font_size)
	_root.theme = theme
	var shade := ColorRect.new()
	shade.color = Color(str(_cfg.backdrop))
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var margin := MarginContainer.new()
	_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(_cfg.margin))
	var paper := PanelContainer.new()
	margin.add_child(paper)
	paper.add_theme_stylebox_override("panel", CampusTheme.box("paper", "accent"))
	var layout := _column(paper)
	_label(layout, "下课十分钟 · 本局档案", int(_cfg.small_font_size))
	_label(layout, "本局回顾", int(_cfg.title_font_size))
	_label(layout, "每一段课间，关系在小事里慢慢改变。", int(_cfg.font_size))
	var tabs := _row(layout)
	for item in [["学期概览", "summary"], ["行为统计", "stats"], ["关系演变", "relations"]]:
		var tab := _button(tabs, str(item[0]), _show_page.bind(str(item[1])))
		tab.name = str(item[1]) + "Tab"
	layout.add_child(HSeparator.new())
	var body := _row(layout)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar = _column(body)
	_sidebar.custom_minimum_size.x = float(_cfg.sidebar_width)
	_content = _column(body)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_relations()
	_stats = ScrollContainer.new()
	_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_stats)
	_stats_rows = _column(_stats)
	_stats_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary = _column(_content)
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var footer := _row(layout)
	var note := _label(footer, "学期已结束，回放展示双方的真实情感。", int(_cfg.small_font_size))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(footer, "回主菜单", _return_to_menu)
	_button(footer, "返回结算", _close_report)
	_button(footer, "再玩一局 →", _new_game, true)


func _close_report() -> void:
	_playing = false
	hide()


func _build_relations() -> void:
	_relations = _column(_content)
	_relations.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var heading := _row(_relations)
	var title := _label(heading, "关系演变 · 真实情感回放", int(_cfg.heading_font_size))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(heading, "双向详情", _show_details)
	_button(heading, "全班矩阵", _show_matrix_clicked)
	var controls := _row(_relations)
	_play_button = _button(controls, "暂停", _toggle_play)
	_button(controls, "重播", _restart)
	for speed in _cfg.speeds:
		_button(controls, "%s×" % str(speed), _set_speed.bind(float(speed)))
	_position_label = _label(controls, "开局", int(_cfg.font_size))
	_position_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_slider = HSlider.new()
	_slider.step = 1.0
	_relations.add_child(_slider)
	_slider.value_changed.connect(_on_seek)
	var ends := _row(_relations)
	_label(ends, "开局", int(_cfg.small_font_size)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(ends, "学期末", int(_cfg.small_font_size))
	var selectors := _row(_relations)
	_label(selectors, "人物", int(_cfg.font_size))
	_from = OptionButton.new()
	selectors.add_child(_from)
	CampusTheme.button(_from)
	_label(selectors, "↔", int(_cfg.font_size))
	_to = OptionButton.new()
	selectors.add_child(_to)
	CampusTheme.button(_to)
	_from.item_selected.connect(_select_source)
	_to.item_selected.connect(_select_target)
	_axis_select = OptionButton.new()
	for axis in AXES:
		_axis_select.add_item(str(_cfg.axes[axis]))
	selectors.add_child(_axis_select)
	CampusTheme.button(_axis_select)
	_axis_select.item_selected.connect(show_matrix)
	_axis_select.hide()
	_detail = _column(_relations)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_matrix = ScrollContainer.new()
	_matrix.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_relations.add_child(_matrix)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", int(_cfg.gap))
	_grid.add_theme_constant_override("v_separation", int(_cfg.gap))
	_matrix.add_child(_grid)
	_matrix.hide()
	_event_label = _label(_relations, "开局关系", int(_cfg.font_size))
	_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(_relations, "关系有方向。箭头表示本次增减，不表示好坏；敌对上升也是 ↑。", int(_cfg.small_font_size))


func _fill_sidebar() -> void:
	_clear(_sidebar)
	_root.find_child("statsTab", true, false).visible = not _record.has("teacher_outcome")
	if _record.has("teacher_outcome"):
		var data: Dictionary = _record.teacher_outcome
		var card := _card(_sidebar, "带班记录")
		_label(card, "共 %d 天" % int(data.day), int(_cfg.heading_font_size))
		_label(card, "班级均分 %.1f" % float(data.mean), int(_cfg.heading_font_size))
		_label(
			card, "学生 %d 人 · 退学 %d 人" % [int(data.count), data.dropouts.size()], int(_cfg.font_size)
		)
		_label(card, "关系回放只读历史，不改变本局结果。", int(_cfg.small_font_size))
		return
	var summary := _card(_sidebar, "学期概览")
	_label(summary, "学习时长\n%s" % _study_time(), int(_cfg.heading_font_size))
	_label(
		summary,
		"成绩净增\n%+d" % int(round(float(_record.grade_end) - float(_record.grade_start))),
		int(_cfg.heading_font_size)
	)
	_label(summary, "交流完成\n%d次" % _communication_count(), int(_cfg.heading_font_size))
	var behavior := _card(_sidebar, "你做过的事")
	var kinds: Array = _record.actions.keys()
	kinds.sort_custom(
		func(a: String, b: String) -> bool:
			return int(_record.actions[a].completed) > int(_record.actions[b].completed)
	)
	var shown := 0
	for kind in kinds:
		if int(_record.actions[kind].completed) > 0:
			_label(
				behavior,
				"%s　%d次" % [_action_name(kind), int(_record.actions[kind].completed)],
				int(_cfg.font_size)
			)
			shown += 1
			if shown >= int(_cfg.sidebar_actions):
				break
	_button(behavior, "查看全部行为 →", _show_page.bind("stats"))
	_label(behavior, "完成、拒绝与中断分别记录。\n学习、睡觉和出门按结束段计次。", int(_cfg.small_font_size))


func _fill_stats() -> void:
	_clear(_stats_rows)
	_label(_stats_rows, "全学期行为记录", int(_cfg.heading_font_size))
	_label(_stats_rows, "只统计玩家实际参与；多人闲聊按一场计数。", int(_cfg.small_font_size))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", int(_cfg.gap) * 2)
	grid.add_theme_constant_override("v_separation", int(_cfg.gap))
	_stats_rows.add_child(grid)
	for text in ["行为", "完成", "主动完成", "应邀完成", "被拒绝", "中断", "拒绝邀请"]:
		_label(grid, text, int(_cfg.font_size))
	for kind in _cfg.actions:
		var row: Dictionary = _record.actions.get(kind, {})
		_label(grid, _action_name(kind), int(_cfg.font_size))
		for key in [
			"completed", "initiated", "invited", "rejected", "interrupted", "invite_declined"
		]:
			_label(grid, "%d次" % int(row.get(key, 0)), int(_cfg.font_size))


func _fill_summary() -> void:
	_clear(_summary)
	if _record.has("teacher_outcome"):
		var data: Dictionary = _record.teacher_outcome
		_label(_summary, "这一段课间，留下了什么", int(_cfg.heading_font_size))
		_label(
			_summary,
			"带班 %d 天 · 班级均分 %.1f" % [int(data.day), float(data.mean)],
			int(_cfg.title_font_size)
		)
		var reason := _label(_summary, str(data.reason), int(_cfg.font_size))
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_button(_summary, "看看关系如何变化 →", _show_page.bind("relations"), true)
		return
	_label(_summary, "属于你的这个学期", int(_cfg.heading_font_size))
	_label(_summary, "你完成了 %d 次交流。" % _communication_count(), int(_cfg.title_font_size))
	_label(
		_summary,
		(
			"学习 %s，成绩净变化 %+d。"
			% [_study_time(), int(round(float(_record.grade_end) - float(_record.grade_start)))]
		),
		int(_cfg.font_size)
	)
	var exam := _label(_summary, str(_record.get("exam_report", "")), int(_cfg.font_size))
	exam.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(_summary, "看看关系如何变化 →", _show_page.bind("relations"), true)
	_label(_summary, "回放保留开局、逐事件变化和日末衰减；人物之间的两种方向分别显示。", int(_cfg.small_font_size))


func _build_details() -> void:
	_clear(_detail)
	_meters.clear()
	for pair in [[_source, _target], [_target, _source]]:
		var card := _card(_detail, "%s → %s" % [_record.names[pair[0]], _record.names[pair[1]]])
		var row := _row(card)
		_portrait(row, int(pair[0]))
		_label(row, "→", int(_cfg.title_font_size))
		_portrait(row, int(pair[1]))
		var emotions := _column(row)
		emotions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for axis_index in AXES.size():
			var meter_row := _row(emotions)
			meter_row.alignment = BoxContainer.ALIGNMENT_CENTER
			_label(meter_row, str(_cfg.axes[AXES[axis_index]]), int(_cfg.font_size))
			var meter: Control = METER.new()
			meter_row.add_child(meter)
			meter.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			_meters.append(
				{"view": meter, "axis": axis_index, "source": int(pair[0]), "target": int(pair[1])}
			)


func _portrait(parent: Node, index: int) -> void:
	var column := _column(parent)
	column.custom_minimum_size.x = float(_cfg.sidebar_width) / 3.0
	var actor: Variant = _actors.actor_for(index) if is_instance_valid(_actors) else null
	var sprite: Variant = actor.get_node_or_null("Sprite") if actor != null else null
	if sprite != null:
		var portrait := TextureRect.new()
		portrait.texture = sprite.texture
		portrait.custom_minimum_size = Vector2(
			float(_cfg.sidebar_width) / 3.0, float(_cfg.sidebar_width) / 2.5
		)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		column.add_child(portrait)
	var label := _label(column, str(_record.names[index]), int(_cfg.font_size))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func show_matrix(axis: int = 0) -> void:
	_matrix_axis = axis
	_axis_select.select(axis)
	_detail.hide()
	_matrix.show()
	_axis_select.show()
	if _matrix_meters.is_empty():
		_build_matrix()
	_refresh(false)


func _show_matrix_clicked() -> void:
	show_matrix(_matrix_axis)


func _build_matrix() -> void:
	_clear(_grid)
	var count := int(_record.count)
	_grid.columns = count + 1
	_label(_grid, "行 → 列", int(_cfg.small_font_size))
	for name in _record.names:
		var label := _label(_grid, str(name), int(_cfg.small_font_size))
		label.custom_minimum_size.x = float(_cfg.matrix_name_width)
	for i in count:
		_label(_grid, str(_record.names[i]), int(_cfg.small_font_size))
		for j in count:
			if i == j:
				_label(_grid, "—", int(_cfg.small_font_size))
				continue
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(
				float(_cfg.matrix_meter_size[0]), float(_cfg.matrix_meter_size[1])
			)
			cell.tooltip_text = "%s → %s · 点击查看双向详情" % [_record.names[i], _record.names[j]]
			_grid.add_child(cell)
			cell.add_theme_stylebox_override("normal", CampusTheme.box("paper", "line"))
			cell.pressed.connect(_select_pair.bind(i, j))
			var meter: Control = METER.new()
			cell.add_child(meter)
			meter.custom_minimum_size = cell.custom_minimum_size
			meter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_matrix_meters.append({"view": meter, "source": i, "target": j})


func matrix_cell_count() -> int:
	return _matrix_meters.size()


func _refresh(animate: bool) -> void:
	var frame: Dictionary = _replay.frame()
	var phase := str(_record.get("phase_names", {}).get(frame.get("phase", ""), ""))
	_position_label.text = "第%d天 · %s · %s×" % [int(frame.day), phase, str(_speed)]
	if _replay.finished():
		_position_label.text += " · 回放结束"
	_play_button.text = "暂停" if _playing else "播放"
	_slider.set_value_no_signal(float(frame.tick))
	var cause := str(frame.cause)
	var words := str(_cfg.causes.get(cause, "一次关系变化"))
	_event_label.text = "第%d天 · %s" % [int(frame.day), words]
	for item in _meters:
		item.view.set_emotion(
			AXES[item.axis],
			_replay.value(item.axis, item.source, item.target),
			_replay.direction(item.axis, item.source, item.target) if animate else 0,
			animate
		)
	if _matrix.visible:
		for item in _matrix_meters:
			item.view.set_emotion(
				AXES[_matrix_axis],
				_replay.value(_matrix_axis, item.source, item.target),
				_replay.direction(_matrix_axis, item.source, item.target) if animate else 0,
				animate
			)


func _show_page(page: String) -> void:
	_relations.visible = page == "relations"
	_stats.visible = page == "stats"
	_summary.visible = page == "summary"


func _show_details() -> void:
	_detail.show()
	_matrix.hide()
	_axis_select.hide()
	_refresh(false)


func _select_pair(source: int, target: int) -> void:
	_source = source
	_target = target
	_from.select(source)
	_to.select(target)
	_build_details()
	_show_details()


func _select_source(index: int) -> void:
	_select_pair(index, _target if index != _target else (_target + 1) % int(_record.count))


func _select_target(index: int) -> void:
	_select_pair(_source if index != _source else (_source + 1) % int(_record.count), index)


func _on_seek(value: float) -> void:
	seek_tick(int(value))


func _toggle_play() -> void:
	if _replay.finished():
		_replay.restart()
	_playing = not _playing
	_refresh(false)


func _restart() -> void:
	_replay.restart()
	_playing = true
	_elapsed = 0.0
	_refresh(false)


func _set_speed(value: float) -> void:
	_speed = value
	_refresh(false)


func _study_time() -> String:
	var minutes := int(float(_record.study_seconds) / 60.0)
	return "%d小时%d分" % [minutes / 60, minutes % 60]


func _communication_count() -> int:
	var total := 0
	for kind in _cfg.communication:
		total += int(_record.actions.get(kind, {}).get("completed", 0))
	return total


func _action_name(kind: String) -> String:
	return str(_cfg.actions.get(kind, kind))


func _return_to_menu() -> void:
	get_tree().paused = false
	GameState.new_game_requested = false
	GameState.end_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _new_game() -> void:
	get_tree().paused = false
	GameState.end_game()
	GameState.new_game_requested = true
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _column(parent: Node) -> VBoxContainer:
	var view := VBoxContainer.new()
	view.add_theme_constant_override("separation", int(_cfg.gap))
	parent.add_child(view)
	return view


func _row(parent: Node) -> HBoxContainer:
	var view := HBoxContainer.new()
	view.add_theme_constant_override("separation", int(_cfg.gap))
	parent.add_child(view)
	return view


func _card(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CampusTheme.box("paper", "accent"))
	parent.add_child(panel)
	var column := _column(panel)
	_label(column, title, int(_cfg.heading_font_size))
	return column


func _label(parent: Node, text: String, font_size: int) -> Label:
	var view := Label.new()
	view.text = text
	view.add_theme_color_override("font_color", Color(str(_cfg.ink)))
	view.add_theme_font_size_override("font_size", font_size)
	parent.add_child(view)
	return view


func _button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var view := Button.new()
	view.text = text
	view.pressed.connect(action)
	CampusTheme.button(view, primary)
	parent.add_child(view)
	return view


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
