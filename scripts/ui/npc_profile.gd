class_name NpcProfile
extends CanvasLayer
## 老师版学生档案。公开状态只读，关系为独立观察笔记。

signal closed
signal tool_requested(action: String)
signal summon_requested(index: int)

const PORTRAITS = preload("res://scripts/ui/student_portraits.gd")
const DATA = preload("res://scripts/ui/npc_profile_data.gd")
const STYLE = preload("res://scripts/ui/npc_profile_theme.gd")
const LAYOUT = preload("res://scripts/ui/npc_profile_layout.gd")
const COPY_PATH := "res://data/localization/npc_profile.json"
const PASSIVES_COPY_PATH := "res://data/localization/passives.json"
const CONFIG_PATH := "res://data/ui/npc_profile.json"
const DESIGN_SIZE := Vector2(1920, 1080)
const AXIS_NODES := {"affinity": "Affinity", "hostility": "Hostility"}

var _core: Variant
var _actors: Node3D
var _index := -1
var _subject := -1
var _copy: Dictionary = {}
var _passives_copy: Dictionary = {}
var _config: Dictionary = {}
var _phase_names: Dictionary = {}
var _seats: Dictionary = {}
var _model: RefCounted = DATA.new()
var _grade_max := 0.0
var _reverse := false
var _snapshots: Dictionary = {}
var _roster: Array[int] = []


func _ready() -> void:
	_copy = _read_json(COPY_PATH)
	_passives_copy = _read_json(PASSIVES_COPY_PATH)
	_config = _read_json(CONFIG_PATH)
	var loader := ConfigLoader.new()
	_grade_max = float(_config.grade_max)
	for entry in loader.get_table("rules/kernel_params").get("rows", []):
		if str(entry.get("param", "")) == "grade_max":
			_grade_max = float(entry.value)
	for entry in loader.get_table("rules/time_presentation").get("rows", []):
		_phase_names[str(entry.phase_id)] = str(entry.display_name)
	for entry in loader.get_table("rules/seats").get("rows", []):
		_seats[str(entry.seat_id)] = entry
	LAYOUT.build(self, _config)
	STYLE.apply(self)
	%PassiveHeading.text = str(_passives_copy.get("heading", %PassiveHeading.text))
	%Close.pressed.connect(close)
	%Previous.pressed.connect(_step_person.bind(-1))
	%Next.pressed.connect(_step_person.bind(1))
	%Targets.item_selected.connect(_on_target_selected)
	%Targets.pressed.connect(_open_target_picker)
	%ClosePicker.pressed.connect(func() -> void: %TargetPicker.hide())
	for slot in range(int(_config.target_picker.capacity)):
		get_node("%TargetSlot" + str(slot)).pressed.connect(_choose_target.bind(slot))
	%Reverse.pressed.connect(_on_reverse)
	%RelationsTab.pressed.connect(_show_page.bind(false))
	%StatusTab.pressed.connect(_show_page.bind(true))
	%Chat.pressed.connect(_on_summon)
	%OpenBoard.pressed.connect(_on_tool.bind("board"))
	%OpenEncyclopedia.pressed.connect(_on_tool.bind("encyclopedia"))
	for axis in AXIS_NODES:
		for band in _config.judgment_bands:
			get_node("%" + AXIS_NODES[axis] + str(band).to_pascal_case()).pressed.connect(
				_on_mark.bind(axis, str(band))
			)
	%Chat.disabled = true
	%OpenBoard.disabled = true
	%OpenEncyclopedia.disabled = true
	get_viewport().size_changed.connect(_fit)
	_fit()
	$Root.hide()


func bind_sources(core: Variant, actors: Node3D, _interaction: Node) -> void:
	if core != _core:
		_model = DATA.new()
		_snapshots.clear()
		var state := get_node_or_null("/root/GameState")
		if state != null and state.sim_core == core:
			_model.state = state.profile_notebook
	_core = core
	_actors = actors
	_roster.clear()
	if core != null:
		for index in range(core.node_count()):
			_roster.append(index)


## 老师版状态接口；缺失字段不从旧学习累计或性格推算。
func update_student_snapshot(index: int, snapshot: Dictionary) -> void:
	_snapshots[index] = snapshot.duplicate(true)
	if is_open() and _index == index:
		_refresh_status()


func enable_teacher_navigation() -> void:
	%Chat.disabled = false
	%OpenBoard.disabled = false
	%OpenEncyclopedia.disabled = false


func open_profile(index: int) -> void:
	if _core == null or not _roster.has(index):
		return
	_index = index
	%TargetPicker.hide()
	_reverse = false
	%PersonName.text = str(_core.alias(index))
	var seat: Dictionary = _seats.get(str(_core.seat_of(index)), {})
	%Seat.text = (
		words("desk_side")
		if str(seat.get("kind", "")) == "desk_side"
		else words("seat", {"row": seat.get("row", "—"), "col": seat.get("col", "—")})
	)
	%RosterCount.text = "%d / %d" % [_roster.find(index) + 1, _roster.size()]
	%Portrait.texture = _texture_for(index)
	%MissingPortrait.visible = %Portrait.texture == null
	_rebuild_targets()
	_refresh_status()
	_refresh_records()
	_show_page(false)
	$Root.show()
	%Close.grab_focus()


func close() -> void:
	if not is_open():
		return
	$Root.hide()
	%TargetPicker.hide()
	closed.emit()


func is_open() -> bool:
	return is_inside_tree() and $Root.visible


func selected_index() -> int:
	return _index


func words(key: String, values: Dictionary = {}) -> String:
	return tr(str(_copy.get(key, key))).format(values)


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		if %TargetPicker.visible:
			%TargetPicker.hide()
		else:
			close()
		get_viewport().set_input_as_handled()


## 档案只读实时状态，不持有或释放世界暂停。
func _process(_delta: float) -> void:
	if is_open() and _core != null and _index >= 0:
		_refresh_status()


func _step_person(direction: int) -> void:
	if not _roster.is_empty():
		open_profile(_roster[posmod(_roster.find(_index) + direction, _roster.size())])


func _rebuild_targets() -> void:
	var targets: OptionButton = %Targets
	targets.clear()
	for index in _roster:
		if index != _index:
			targets.add_item(str(_core.alias(index)), index)
	var preferred := targets.get_item_index(_subject)
	if targets.item_count > 0:
		targets.select(maxi(preferred, 0))
		_subject = targets.get_selected_id()
	else:
		_subject = -1
	%Reverse.disabled = _subject < 0
	for slot in range(int(_config.target_picker.capacity)):
		var button: Button = get_node("%TargetSlot" + str(slot))
		button.visible = slot < targets.item_count
		if button.visible:
			button.text = targets.get_item_text(slot)
			button.tooltip_text = button.text


func _open_target_picker() -> void:
	if Input.emulate_mouse_from_touch:
		return
	# 项目关闭触摸鼠标模拟：使用原生按钮网格，避免 PopupMenu 的鼠标选择路径。
	%Targets.get_popup().hide()
	%TargetPicker.show()


func _choose_target(slot: int) -> void:
	%Targets.select(slot)
	_on_target_selected(slot)
	%TargetPicker.hide()


func _on_target_selected(item: int) -> void:
	_subject = %Targets.get_item_id(item)
	_reverse = false
	_refresh_records()


func _on_reverse() -> void:
	_reverse = not _reverse
	_refresh_records()


func _on_mark(axis: String, band: String) -> void:
	if _subject < 0:
		return
	_model.mark(
		_subject if _reverse else _index,
		_index if _reverse else _subject,
		axis,
		band,
		_core.time_snapshot()
	)
	_refresh_records()


func _refresh_records() -> void:
	var source := _subject if _reverse else _index
	var target := _index if _reverse else _subject
	var result: Dictionary = _model.build([], source, target)
	%RelationTitle.text = words(
		"relation",
		{
			"source": _core.alias(source),
			"subject": _core.alias(target) if target >= 0 else words("none")
		}
	)
	%Reverse.text = words("forward" if _reverse else "reverse")
	for axis in AXIS_NODES:
		var base: String = AXIS_NODES[axis]
		var entry: Dictionary = result.latest.get(axis, {})
		var band := "unknown"
		if not entry.is_empty():
			band = (
				_band_key(float(entry.value))
				if str(entry.origin) in ["known", "ask"]
				else str(entry.band)
			)
		get_node("%" + base + "Value").text = words(band)
		get_node("%" + base + "Time").text = (
			words("unknown")
			if entry.is_empty()
			else (
				words(str(entry.origin))
				+ (" · " + words("private_chat") if str(entry.origin) == "known" else "")
				+ " · "
				+ _date(entry)
			)
		)
		get_node("%" + base + "Time").tooltip_text = (
			(
				words("source", {"person": _core.alias(source)})
				if str(entry.origin) == "known"
				else words("ask_source", {"person": _core.alias(source)})
			)
			if not entry.is_empty() and str(entry.origin) in ["known", "ask"]
			else words("guess")
		)
		for option in _config.judgment_bands:
			var button: Button = get_node("%" + base + str(option).to_pascal_case())
			button.set_pressed_no_signal(str(option) == band)
			button.disabled = _subject < 0
	_render_history(result.history)


func _render_history(history: Array) -> void:
	_clear(%HistoryRows)
	if history.is_empty():
		%HistoryRows.add_child(_label(words("history_empty"), 24))
	for entry in history:
		var band := (
			_band_key(float(entry.value))
			if str(entry.origin) in ["known", "ask"]
			else str(entry.band)
		)
		var line := _label(
			(
				_date(entry)
				+ " · "
				+ words(str(entry.origin))
				+ "\n"
				+ words(str(entry.axis))
				+ " · "
				+ words(band)
			),
			23
		)
		%HistoryRows.add_child(line)
	%HistoryScroll.scroll_vertical = 0


func _refresh_status() -> void:
	var snapshot: Dictionary = _snapshots.get(_index, {}).duplicate(true)
	if _core.has_method("teacher_student_snapshot"):
		snapshot.merge(_core.teacher_student_snapshot(_index), true)
	var grade := float(_core.grade(_index))
	var maximum := _grade_max
	%GradeValue.text = (
		"%s / %s"
		% [
			str(roundi(float(snapshot.get("grade", grade)))),
			str(roundi(float(snapshot.get("grade_max", maximum))))
		]
	)
	var pressure: Variant = snapshot.get("pressure", _core.stress(_index))
	%PressureValue.text = "%s / %s" % [_number(pressure), _number(_config.state_max)]
	%PressureBar.value = float(pressure)
	var motivation: Variant = _core.vitality(_index)
	%MotivationValue.text = (
		"—" if motivation == null else "%s / %s" % [_number(motivation), _number(_config.state_max)]
	)
	%MotivationBar.visible = motivation != null
	%MotivationBar.value = float(motivation) if motivation != null else 0.0
	var gain: Variant = _core.gain_today(_index)
	%GainValue.text = "—" if gain == null else _number(gain, true) + " 分"
	%Settlement.text = (
		words("settlement")
		if gain == null
		else words(
			"settlement_known",
			{
				"grade":
				str(roundi(clampf(float(snapshot.get("grade", grade)) + float(gain), 0, maximum)))
			}
		)
	)
	var activity := str(snapshot.get("activity", _core.activity_of(_index)))
	if _core.is_moving(_index):
		activity = "moving"
	elif not _core.is_present(_index):
		activity = "absent"
	%Activity.text = words("activity") + str(_config.activities.get(activity, "活动中"))
	%Passive.text = _passive_text(str(snapshot.get("passive_id", "")))
	%Goal.text = str(snapshot.get("communication_goal", words("goal_missing")))
	%StatusDetails.text = words(
		"status_summary",
		{
			"activity": %Activity.text,
			"pressure": _number(pressure),
			"motivation": _number(motivation),
			"gain": _number(gain, true)
		}
	)
	# 群策群力（主文档 §10.2）：该生可以看到所有其他同学对本人好感 —— 只读展示，不写矩阵。
	# 放在状态摘要之后、明细之前，档案一打开就能看到，不用滚到底。
	if bool(snapshot.get("reveals_incoming_affinity", false)):
		%StatusDetails.text += (
			"\n\n"
			+ str(_passives_copy.get("reveal_heading", ""))
			+ "\n"
			+ _incoming_affinity_text(_index)
		)
	for key in ["gain_details", "trends", "attention", "interventions"]:
		%StatusDetails.text += (
			"\n\n" + words(key) + "\n" + str(snapshot.get(key, words("no_record")))
		)


## 档案里的公开被动：名称 + 效果（文案在 data/localization/passives.json，数值在 data/rules/）。
func _passive_text(passive_id: String) -> String:
	var entry: Dictionary = _passives_copy.get(passive_id, {})
	if passive_id.is_empty() or entry.is_empty():
		return str(_passives_copy.get("missing", words("passive_missing")))
	return "%s\n%s" % [str(entry.get("name", passive_id)), str(entry.get("effect", ""))]


## 群策群力可见性：按 config 的列数分行列出「同学 → 对本人好感」，只读内核真值。
func _incoming_affinity_text(index: int) -> String:
	if _core == null:
		return ""
	var columns := maxi(1, int(_config.get("affinity_reveal_columns", 3)))
	var lines: PackedStringArray = PackedStringArray()
	var row: PackedStringArray = PackedStringArray()
	for other in _roster:
		if other == index:
			continue
		row.append(
			"%s %s" % [str(_core.alias(other)), str(roundi(float(_core.affinity(other, index))))]
		)
		if row.size() >= columns:
			lines.append("、".join(row))
			row = PackedStringArray()
	if row.size() > 0:
		lines.append("、".join(row))
	return "\n".join(lines)


func _show_page(status: bool) -> void:
	%RelationsPage.visible = not status
	%StatusPage.visible = status
	%RelationsTab.set_pressed_no_signal(not status)
	%StatusTab.set_pressed_no_signal(status)


func _on_summon() -> void:
	var index := _index
	close()
	summon_requested.emit(index)


func _on_tool(action: String) -> void:
	close()
	tool_requested.emit(action)


func _texture_for(index: int) -> Texture2D:
	if _core == null:
		return null
	return PORTRAITS.texture_for(str(_core.character_id(index)), _config)


func _date(entry: Dictionary) -> String:
	return words(
		"timestamp",
		{
			"day": entry.get("day", "—"),
			"phase": _phase_names.get(str(entry.get("phase_id", "")), "")
		}
	)


func _band_key(value: float) -> String:
	var key := "unknown"
	for band in _config.bands:
		if value >= float(band.minimum):
			key = str(band.label)
	return key


func _number(value: Variant, signed: bool = false) -> String:
	if value == null:
		return "—"
	var text := (
		str(int(value))
		if is_equal_approx(float(value), roundf(float(value)))
		else "%.1f" % float(value)
	)
	return "+" + text if signed and float(value) > 0 else text


func _fit() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var factor := minf(viewport.x / DESIGN_SIZE.x, viewport.y / DESIGN_SIZE.y)
	%Design.scale = Vector2.ONE * factor
	%Design.position = (viewport - DESIGN_SIZE * factor) * 0.5


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
