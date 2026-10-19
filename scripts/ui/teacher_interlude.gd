extends Control
## 演出只读命令；不暂停、不结算效果，收起与取消分别处理。

signal cancel_requested

const FONTS = preload("res://scripts/ui/game_fonts.gd")

var config: Dictionary
var _panel: PanelContainer
var _title: Label
var _beat: Label
var _status: Label
var _cast: HBoxContainer
var _progress: ProgressBar
var _elapsed := 0.0
var _key := ""
var _hidden := false
var _held := false
var _duration := 1.0
var _action: Dictionary = {}
var _teacher_pose: TextureRect
var _pose_atlas: Texture2D


func _ready() -> void:
	config = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/teacher_interlude.json")
	)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(config.backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	_panel = PanelContainer.new()
	add_child(_panel)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(config.paper)
	paper.set_corner_radius_all(18)
	paper.content_margin_left = 24
	paper.content_margin_right = 24
	paper.content_margin_top = 16
	paper.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", paper)
	var rows := VBoxContainer.new()
	_panel.add_child(rows)
	_title = _label(rows, int(config.title_size))
	_cast = HBoxContainer.new()
	_cast.alignment = BoxContainer.ALIGNMENT_CENTER
	_cast.custom_minimum_size.y = 115
	rows.add_child(_cast)
	_beat = _label(rows, int(config.font_size))
	_status = _label(rows, int(config.font_size))
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	rows.add_child(_progress)
	var buttons := HBoxContainer.new()
	rows.add_child(buttons)
	for key in ["hide", "cancel"]:
		var button := Button.new()
		button.text = config[key]
		button.custom_minimum_size.y = config.button_height
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_override("font", FONTS.regular())
		button.add_theme_font_size_override("font_size", int(config.font_size))
		buttons.add_child(button)
		if key == "cancel":
			button.pressed.connect(func() -> void: cancel_requested.emit())
		else:
			button.pressed.connect(collapse)
	hide()


func _label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONTS.regular())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(config.ink))
	parent.add_child(label)
	return label


func refresh(core: Variant, snapshot: Dictionary) -> void:
	var command := str(snapshot.get("command", ""))
	var kind := str(snapshot.get("chat_kind", "")) if command == "office_chat" else command
	if not config.actions.has(kind):
		_key = ""
		hide()
		return
	var key := kind + str(snapshot.get("called", -1))
	if key != _key:
		_key = key
		_hidden = false
		_elapsed = 0.0
		_duration = maxf(1.0, float(snapshot.remaining_seconds))
		_action = config.actions[kind]
		_title.text = _action.title
		for child in _cast.get_children():
			_cast.remove_child(child)
			child.queue_free()
		var indices: Array = [int(snapshot.get("called", -1))]
		if kind == "mediate":
			var pair: Dictionary = snapshot.get("mediate_pair", {})
			indices = [int(pair.get("a", -1)), int(pair.get("b", -1))]
		_teacher_pose = TextureRect.new()
		_teacher_pose.custom_minimum_size = Vector2(config.pose_width, config.pose_height)
		_teacher_pose.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_teacher_pose.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_teacher_pose.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _pose_atlas == null:
			_pose_atlas = load(str(config.pose_atlas)) as Texture2D
		var pose := AtlasTexture.new()
		pose.atlas = _pose_atlas
		var cell_size := _pose_atlas.get_size() / Vector2(config.pose_columns, config.pose_rows)
		var cell := int(_action.pose)
		pose.region = Rect2(
			Vector2(cell % int(config.pose_columns), cell / int(config.pose_columns)) * cell_size,
			cell_size
		)
		pose.filter_clip = true
		_teacher_pose.texture = pose
		_cast.add_child(_teacher_pose)
		for index in indices:
			if index >= 0:
				var portrait := TextureRect.new()
				var profiles: Dictionary = JSON.parse_string(
					FileAccess.get_file_as_string("res://data/ui/npc_profile.json")
				)
				portrait.texture = preload("res://scripts/ui/student_portraits.gd").texture_for(
					str(core.character_id(index)), profiles
				)
				portrait.custom_minimum_size = Vector2(100, 115)
				portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				_cast.add_child(portrait)
			var actor := _label(_cast, int(config.title_size))
			actor.text = (str(core.alias(index)) if index >= 0 else str(config.student)) + "  "
			actor.add_theme_color_override("font_color", Color(_action.color))
	_held = bool(snapshot.get("held_by_class", false))
	_status.text = str(config.held) if _held else config.remaining % int(snapshot.remaining_seconds)
	_progress.value = 100.0 * (1.0 - float(snapshot.remaining_seconds) / _duration)
	visible = not _hidden


func _process(delta: float) -> void:
	if not visible or _action.is_empty():
		return
	if not _held:
		_elapsed += delta
	var cycle := float(config.cycle_seconds)
	var beat: int = int(_elapsed / cycle) % _action.beats.size()
	_beat.text = str(_action.symbol) + "  " + str(_action.beats[beat])
	var viewport := get_viewport_rect().size
	var factor := minf(
		1.0,
		minf(
			viewport.x / (float(config.width) + float(config.margin)),
			viewport.y / (float(config.height) + float(config.margin))
		)
	)
	_panel.scale = Vector2.ONE * factor
	_panel.size = Vector2(config.width, config.height)
	_panel.position = Vector2(
		(viewport.x - _panel.size.x * factor) * 0.5, (viewport.y - _panel.size.y * factor) * 0.5
	)
	_panel.modulate.a = minf(1.0, _elapsed / float(config.enter_seconds)) if not _held else 1.0
	for index in range(_cast.get_child_count()):
		var actor := _cast.get_child(index) as Control
		actor.pivot_offset = actor.size * 0.5
		actor.rotation = (
			0.0 if _held else sin(_elapsed * TAU / cycle + index) * float(config.sway) / 180.0
		)
	if _teacher_pose != null:
		var emphasis := maxf(0.0, sin(_elapsed * TAU / cycle)) if not _held else 0.0
		_teacher_pose.pivot_offset = Vector2(_teacher_pose.size.x * 0.5, _teacher_pose.size.y)
		_teacher_pose.rotation_degrees = float(_action.lean) * emphasis
		_teacher_pose.scale = Vector2.ONE * (1.0 + float(config.pose_emphasis) * emphasis)


func teacher_pose() -> Texture2D:
	return _teacher_pose.texture if _teacher_pose != null else null


func collapse() -> void:
	_hidden = true
	hide()
