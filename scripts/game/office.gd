extends Control
## 办公室纯表现视图；可单独运行预览，不创建或修改模拟。

signal action_requested(action: String)

const FONTS := preload("res://scripts/ui/game_fonts.gd")
const CONFIG_PATH := "res://data/ui/office_hub.json"

var config: Dictionary
var _buttons: Dictionary = {}
var _clock: Node
var _preview: TextureRect
var _phase_names: Dictionary
var _weekly_copy: Dictionary
var _meeting: Control


func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	var time_card: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/time_card.json")
	)
	_weekly_copy = time_card.get("messages", {})
	_phase_names = (
		JSON
		. parse_string(FileAccess.get_file_as_string("res://data/ui/time_card.json"))
		. get("phase_names", {})
	)
	%Title.text = config.copy.title
	%Pause.text = config.copy.pause
	%Settings.text = config.copy.settings
	%Time.text = config.copy.no_clock
	%Countdown.text = config.copy.no_exam
	for key in config.actions:
		var button := get_node("%" + str(key).capitalize()) as Button
		_buttons[key] = button
		var entry: Dictionary = config.actions[key]
		button.text = entry.text
		button.icon = load("res://assets/icons/actions/%s.svg" % entry.icon)
		style_button(button, key == "summon")
		button.custom_minimum_size.y = float(config.button_height)
		button.pressed.connect(func() -> void: action_requested.emit(key))
	%Monitor.custom_minimum_size.y = float(config.monitor_height)
	%Profile.icon = preload("res://assets/icons/ui/office_profile.svg")
	_build_preview()
	for key in ["profile", "board", "encyclopedia"]:
		action_button(key).custom_minimum_size.y = float(config.footer_height)
	for button in [%Pause, %Settings]:
		style_button(button)
		button.custom_minimum_size.y = float(config.header_height)
	%Pause.icon = preload("res://assets/icons/ui/office_pause.svg")
	%Settings.icon = preload("res://assets/icons/actions/settings.svg")
	%Pause.pressed.connect(func() -> void: action_requested.emit("pause"))
	%Settings.pressed.connect(func() -> void: action_requested.emit("settings"))
	for card in [%TitleCard, %TimeCard, %CountdownCard]:
		card.add_theme_stylebox_override("panel", paper_style())
	for label in [%Title, %Time, %Countdown]:
		label.add_theme_font_override("font", FONTS.regular())
		label.add_theme_color_override("font_color", Color(config.ink))
		label.add_theme_font_size_override("font_size", int(config.font_size))
	%Title.add_theme_font_size_override("font_size", int(config.title_font_size))
	for row in [%Header, %Footer, %Navigation]:
		row.add_theme_constant_override("separation", int(config.gap))
	get_viewport().size_changed.connect(_fit)
	_fit()
	_meeting = preload("res://scripts/game/office_meeting.gd").new()
	%Design.add_child(_meeting)
	%Design.move_child(_meeting, 0)
	_meeting.setup(self)
	_fit()
	_meeting.action_requested.connect(func(action: String) -> void: action_requested.emit(action))


func update_commands(core: Variant, snapshot: Dictionary) -> void:
	_meeting.refresh(core, snapshot)
	_buttons.summon.disabled = (
		int(snapshot.called) >= 0 or str(snapshot.command) != "" or bool(snapshot.held_by_class)
	)
	_buttons.classroom.disabled = int(snapshot.called) >= 0 or str(snapshot.command) != ""


func meeting_visible() -> bool:
	return _meeting.meeting_visible()


func command_status(snapshot: Dictionary) -> String:
	return _meeting.status_text(snapshot)


func meeting_texture() -> Texture2D:
	return _meeting.meeting_texture()


func show_student(core: Variant, index: int) -> void:
	_meeting.show_student(core, index)


func bind_sources(clock: Node) -> void:
	_clock = clock
	_clock.time_updated.connect(_update_time)
	_update_time(_clock.snapshot())


func action_button(key: String) -> Button:
	return _buttons.get(key)


func _update_time(snapshot: Dictionary) -> void:
	var phase: String = str(snapshot.get("phase_id", ""))
	%Time.text = (
		"第%d天 · %s"
		% [
			int(snapshot.get("day", 0)),
			str(_phase_names.get(phase, snapshot.get("display_name", "")))
		]
	)
	var mode := str(snapshot.get("mode", ""))
	if mode == "report" or mode == "finished":
		%Countdown.text = config.copy.report if mode == "report" else config.copy.finished
		return
	var seconds := int(ceil(float(snapshot.get("remaining_seconds", 0.0))))
	%Countdown.text = config.copy.remaining % [seconds / 60, seconds % 60]
	var exam_day := int(snapshot.get("first_exam_day", 0))
	var day := int(snapshot.get("day", 0))
	if exam_day > day:
		%Countdown.text = str(_weekly_copy.week_future) % (exam_day - day) + "\n" + %Countdown.text
	elif exam_day == day and day > 0:
		%Countdown.text = str(_weekly_copy.week_today) + "\n" + %Countdown.text
	%Countdown.add_theme_font_size_override("font_size", int(config.small_font_size))


func _build_preview() -> void:
	%Monitor.text = ""
	%Monitor.icon = null
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Monitor.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(config.padding))
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", int(config.gap))
	margin.add_child(rows)
	var title := Label.new()
	title.text = config.actions.monitor.text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(config.ink))
	title.add_theme_font_size_override("font_size", int(config.font_size))
	rows.add_child(title)
	_preview = TextureRect.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.texture = preload("res://assets/icons/ui/office_monitor.svg")
	_preview.self_modulate = Color(config.ink)
	rows.add_child(_preview)
	%Monitor.tooltip_text = "上次现场画面预览；点击打开实时教室监控"


func capture_preview() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var picture := get_viewport().get_texture().get_image()
	if picture == null or picture.is_empty():
		return
	_preview.texture = ImageTexture.create_from_image(picture)
	_preview.self_modulate = Color.WHITE


func _fit() -> void:
	if config.is_empty():
		return
	var design := Vector2(config.design_size[0], config.design_size[1])
	var factor := minf(size.x / design.x, size.y / design.y)
	%Design.scale = Vector2.ONE * factor
	%Design.position = (size - design * factor) / 2.0
	if _meeting != null:
		_meeting.fit_background(size, factor, %Design.position, design)


func paper_style(primary: bool = false, hovered: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(config.accent if primary else config.hover if hovered else config.paper)
	box.border_color = Color(config.paper if primary else config.ink)
	box.set_border_width_all(int(config.border_width))
	box.set_corner_radius_all(int(config.radius))
	box.set_content_margin_all(float(config.padding))
	return box


func style_button(button: Button, primary: bool = false) -> void:
	bind_touch(button)
	button.add_theme_font_override("font", FONTS.regular())
	button.add_theme_font_size_override("font_size", int(config.font_size))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, paper_style(primary, state == "hover"))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color(config.paper if primary else config.ink))
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_color_override(
			"icon_" + state + "_color", Color(config.paper if primary else config.ink)
		)
	button.add_theme_constant_override("icon_max_width", int(config.icon_size))
	button.add_theme_constant_override("h_separation", int(config.gap))
	button.expand_icon = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func bind_touch(button: Button) -> void:
	if not button.gui_input.is_connected(_button_touch.bind(button)):
		button.gui_input.connect(_button_touch.bind(button))


func _button_touch(event: InputEvent, button: Button) -> void:
	if Input.emulate_mouse_from_touch:
		return
	if event is InputEventScreenDrag:
		button.remove_meta("office_touch")
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if not button.disabled and not button.has_meta("office_touch"):
				button.set_meta("office_touch", touch.index)
		elif int(button.get_meta("office_touch", -1)) == touch.index:
			button.remove_meta("office_touch")
			if not touch.canceled and not button.disabled and button.is_visible_in_tree():
				if Rect2(Vector2.ZERO, button.size).has_point(touch.position):
					button.pressed.emit()
		button.accept_event()
