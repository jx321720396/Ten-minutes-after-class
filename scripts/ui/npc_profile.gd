class_name NpcProfile
extends CanvasLayer
## 同学档案：原生UI + 已获知历史快照。未知不等于中立，不读NPC实时关系。

signal closed

const DATA = preload("res://scripts/ui/npc_profile_data.gd")
const STYLE = preload("res://scripts/ui/npc_profile_theme.gd")
const COPY_PATH := "res://data/localization/npc_profile.json"
const CONFIG_PATH := "res://data/ui/npc_profile.json"
const DESIGN_SIZE := Vector2(1920, 1080)
const AXIS_NODES := {"affinity": "Affinity", "hostility": "Hostility", "trust": "Trust"}

@onready var _root: Control = $Root
@onready var _design: Control = %Design
@onready var _targets: OptionButton = %Targets
@onready var _portrait: TextureRect = %Portrait
@onready var _history_rows: VBoxContainer = %HistoryRows
@onready var _encounters: VBoxContainer = %Encounters
@onready var _chat: Button = %Chat

var _core: Variant
var _actors: Node3D
var _interaction: Node
var _index := -1
var _subject := -1
var _copy: Dictionary = {}
var _config: Dictionary = {}
var _phase_names: Dictionary = {}
var _history: Array = []
var _model: RefCounted = DATA.new()
var _owns_pause := false
var _can_chat := false


func _ready() -> void:
	_copy = _read_json(COPY_PATH)
	_config = _read_json(CONFIG_PATH)
	for row in ConfigLoader.new().get_table("rules/time_presentation").get("rows", []):
		_phase_names[str(row.phase_id)] = str(row.display_name)
	STYLE.apply(self)
	_set_static_text()
	%Close.pressed.connect(close)
	%Previous.pressed.connect(_step_person.bind(-1))
	%Next.pressed.connect(_step_person.bind(1))
	_targets.item_selected.connect(_on_target_selected)
	_chat.pressed.connect(_on_chat)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_root.hide()


func bind_sources(core: Variant, actors: Node3D, interaction: Node) -> void:
	_core = core
	_actors = actors
	_interaction = interaction


func open_profile(index: int) -> void:
	if _core == null or index < 0 or index >= int(_core.node_count()) or _core.is_player(index):
		return
	if not is_open():
		_owns_pause = not get_tree().paused
		get_tree().paused = true
	_index = index
	_history = _core.get_player_intel()
	%PersonName.text = str(_core.alias(index))
	%Seat.text = words("seat", {"seat": _core.seat_of(index)})
	%RosterCount.text = "%02d / %02d" % [index + 1, int(_core.node_count()) - 1]
	_portrait.texture = _texture_for(index)
	%MissingPortrait.visible = _portrait.texture == null
	_rebuild_targets()
	_refresh_records()
	_refresh_chat()
	_root.show()
	%Close.grab_focus()


func close() -> void:
	if not is_open():
		return
	_root.hide()
	_release_pause()
	closed.emit()


func is_open() -> bool:
	return is_instance_valid(_root) and _root.visible


func selected_index() -> int:
	return _index


func words(key: String, values: Dictionary = {}) -> String:
	return tr(str(_copy.get(key, key))).format(values)


func _input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_release_pause()


func _release_pause() -> void:
	if not _owns_pause:
		return
	_owns_pause = false
	# 与同一UI下的百科/黑板/暂停菜单协作，不关闭仍然打开的其他窗口。
	var parent := get_parent()
	if parent != null:
		for sibling in parent.get_children():
			if sibling == self:
				continue
			if sibling.has_method("is_open") and sibling.is_open():
				return
			if sibling.name == "PauseMenu" and sibling is Control and sibling.visible:
				return
	if is_inside_tree():
		get_tree().paused = false


func _step_person(direction: int) -> void:
	open_profile(posmod(_index + direction, int(_core.node_count()) - 1))


func _rebuild_targets() -> void:
	_targets.clear()
	var preferred := -1
	for clue in _history:
		if int(clue.get("source", -1)) == _index:
			preferred = int(clue.get("subject", -1))
	for i in range(int(_core.node_count())):
		if i == _index or _core.is_player(i):
			continue
		_targets.add_item(str(_core.alias(i)), i)
	if _targets.item_count == 0:
		_subject = -1
		return
	var item := _targets.get_item_index(preferred)
	_targets.select(maxi(item, 0))
	_subject = _targets.get_selected_id()


func _on_target_selected(item: int) -> void:
	_subject = _targets.get_item_id(item)
	_refresh_records()


func _refresh_records() -> void:
	var result: Dictionary = _model.build(_history, _index, _subject)
	%RelationTitle.text = words(
		"relation", {"source": _core.alias(_index), "subject": _subject_name()}
	)
	for axis in AXIS_NODES:
		var base: String = AXIS_NODES[axis]
		var value: Label = get_node("%" + base + "Value")
		var stamp: Label = get_node("%" + base + "Time")
		var clue: Dictionary = result.latest.get(axis, {})
		value.text = words("unknown") if clue.is_empty() else _band(float(clue.value))
		value.add_theme_color_override("font_color", STYLE.MUTED if clue.is_empty() else STYLE.INK)
		stamp.text = words("not_obtained") if clue.is_empty() else _date(clue)
		stamp.tooltip_text = "" if clue.is_empty() else _date(clue) + " · " + _age(clue)
	var newest: Dictionary = {} if result.history.is_empty() else result.history[0]
	%Source.text = (
		words("not_obtained")
		if newest.is_empty()
		else words("source", {"person": _core.alias(_index)})
	)
	%RecordTime.text = words("empty_time") if newest.is_empty() else _date(newest)
	%Age.text = "" if newest.is_empty() else _age(newest)
	%StaleNote.visible = not newest.is_empty()
	_render_history(result.history)
	_render_encounters(result.encounters)


func _render_history(history: Array) -> void:
	_clear(_history_rows)
	if history.is_empty():
		_history_rows.add_child(_label(words("history_empty"), 28, STYLE.MUTED))
	for clue in history:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", STYLE.box(Color(1, 1, 1, 0.2), STYLE.LINE, 6, 1))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 22)
		row.add_child(line)
		var date := _label(_date(clue), 24, STYLE.MUTED)
		date.custom_minimum_size.x = 265
		line.add_child(date)
		var text := _label(
			words("history_row", {"axis": words(clue.axis), "band": _band(clue.value)}),
			28,
			STYLE.INK
		)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		var age := _label(_age(clue), 22, STYLE.MUTED)
		age.custom_minimum_size.x = 145
		line.add_child(age)
		_history_rows.add_child(row)
	%HistoryScroll.scroll_vertical = 0


func _render_encounters(encounters: Array) -> void:
	_clear(_encounters)
	if encounters.is_empty():
		_encounters.add_child(_label(words("encounters_empty"), 26, STYLE.MUTED))
	for clue in encounters.slice(0, int(_config.get("encounter_limit", 3))):
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 5)
		column.add_child(_label(_date(clue), 24, STYLE.INK))
		column.add_child(_label(words("encounter", {"count": clue.count}), 22, STYLE.MUTED))
		_encounters.add_child(column)


func _refresh_chat() -> void:
	var preview: Dictionary = _core.preview_player_interaction("chat", _index)
	_can_chat = bool(preview.get("ok", false)) and bool(preview.get("eligible", false))
	if _interaction == null:
		_can_chat = false
	else:
		_can_chat = _can_chat and _interaction.current_state() in [&"idle", &"selected"]
	_chat.text = words("join" if str(preview.get("mode", "")) == "join" else "chat")
	_chat.disabled = not _can_chat
	_chat.tooltip_text = words("chat_hint" if _can_chat else "chat_locked")


func _on_chat() -> void:
	if not _can_chat or _interaction == null:
		return
	var target := _index
	close()
	# 再经原控制器预览与校验；不从档案直接调用内核提交。
	if not get_tree().paused:
		_interaction.select_actor(target)
		_interaction.request_behavior_chat()


func _texture_for(index: int) -> Texture2D:
	if _actors == null:
		return null
	var actor: Node3D = _actors.actor_for(index)
	if actor == null:
		return null
	var sprite := actor.get_node_or_null("Sprite") as Sprite3D
	return sprite.texture if sprite != null else null


func _subject_name() -> String:
	return str(_core.alias(_subject)) if _subject >= 0 else words("none")


func _date(clue: Dictionary) -> String:
	return words(
		"timestamp",
		{"day": int(clue.day), "phase": _phase_names.get(str(clue.phase_id), clue.phase_id)}
	)


func _age(clue: Dictionary) -> String:
	var days := maxi(0, int(_core.day()) - int(clue.day))
	return words("today") if days == 0 else words("age", {"days": days})


func _band(value: float) -> String:
	var key := "unknown"
	for band in _config.get("bands", []):
		if value >= float(band.minimum):
			key = str(band.label)
	return words(key)


func _fit() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var factor := minf(viewport.x / DESIGN_SIZE.x, viewport.y / DESIGN_SIZE.y)
	_design.scale = Vector2.ONE * factor
	_design.position = (viewport - DESIGN_SIZE * factor) * 0.5


func _set_static_text() -> void:
	var mapping := {
		"Title": "title",
		"Subtitle": "subtitle",
		"KnownTitle": "known_title",
		"KnownNote": "known_note",
		"HistoryTitle": "history_title",
		"HistoryNote": "history_note",
		"EncountersTitle": "encounters_title",
		"JudgmentTitle": "judgment_title",
		"JudgmentValue": "judgment_empty",
		"JudgmentNote": "judgment_note",
		"UnknownNote": "unknown_note",
		"Footer": "footer",
		"SourceHeading": "source_label",
		"TimeHeading": "record_label",
		"StaleNote": "stale_note",
		"MissingPortrait": "no_portrait",
		"TargetHeading": "relationship_target",
		"AffinityHeading": "affinity",
		"HostilityHeading": "hostility",
		"TrustHeading": "trust",
	}
	for node in mapping:
		get_node("%" + node).text = words(mapping[node])
	%Close.tooltip_text = words("close")
	%Previous.tooltip_text = words("previous")
	%Next.tooltip_text = words("next")


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
