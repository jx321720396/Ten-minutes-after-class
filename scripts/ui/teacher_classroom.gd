extends Control
## 老师教室表现界面，选择只读学生索引；不提交旧玩家行为。

signal action_requested(action: String)
signal profile_requested(index: int)

const STYLE := preload("res://scripts/ui/campus_theme.gd")
const FONTS := preload("res://scripts/ui/game_fonts.gd")

var config: Dictionary
var _selected := -1


func _ready() -> void:
	config = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/teacher_classroom.json")
	)
	var paper := STYLE.paper_card()
	paper.content_margin_top = float(config.paper_top)
	%Frame.add_theme_stylebox_override("panel", paper)
	%ModeBadge.add_theme_stylebox_override("panel", STYLE.box("paper", "line"))
	%MonitorHeader.add_theme_stylebox_override("panel", STYLE.box("paper", "line"))
	%Heading.text = config.copy.heading
	%TargetHeading.text = config.copy.target_heading
	%Target.text = config.copy.no_target
	%Hint.text = config.copy.pending_hint
	%StatusCard.add_theme_stylebox_override("panel", STYLE.box("paper", "teal"))
	for label in [%Mode, %Heading, %TargetHeading, %Target, %Hint, %Status]:
		label.add_theme_font_override("font", FONTS.regular())
		label.add_theme_color_override("font_color", Color(STYLE.settings().teal))
		label.add_theme_font_size_override("font_size", int(config.font_size))
	%Heading.add_theme_font_size_override("font_size", int(config.heading_size))
	%Mode.add_theme_font_size_override("font_size", int(config.small_size))
	%Hint.add_theme_font_size_override("font_size", int(config.small_size))
	for key in [
		"private_chat", "seats", "conflict", "profile", "profile_tool", "book_tool"
	]:
		var button := get_node("%" + str(key).to_pascal_case()) as Button
		button.text = str(config.copy[key])
		_style_button(button)
	for button in [%PrivateChat, %Seats, %Conflict]:
		button.custom_minimum_size.y = float(config.button_height)
	%PrivateChat.icon = preload("res://assets/icons/actions/chat.svg")
	%Seats.icon = preload("res://assets/icons/ui/teacher_seat.svg")
	%Conflict.icon = preload("res://assets/icons/ui/teacher_conflict.svg")
	%ProfileTool.icon = preload("res://assets/icons/ui/office_profile.svg")
	%BookTool.icon = preload("res://assets/icons/actions/encyclopedia.svg")
	%Seats.disabled = true
	%Conflict.disabled = true
	%Profile.disabled = true
	%Profile.pressed.connect(func() -> void: profile_requested.emit(_selected))
	%PrivateChat.pressed.connect(func() -> void: action_requested.emit("private_chat"))
	%Seats.pressed.connect(func() -> void: action_requested.emit("seats"))
	%Conflict.pressed.connect(func() -> void: action_requested.emit("mediate"))
	%ProfileTool.pressed.connect(func() -> void: action_requested.emit("profile"))
	%BookTool.pressed.connect(func() -> void: action_requested.emit("encyclopedia"))
	_style_button(%ReturnOffice)
	%ReturnOffice.add_theme_font_size_override("font_size", int(config.return_size))
	%ReturnOffice.pressed.connect(func() -> void: action_requested.emit("office"))
	for row in [%Rows, %Tools, %ModeRow]:
		row.add_theme_constant_override("separation", int(config.gap))
	get_viewport().size_changed.connect(_fit)
	_fit()


func set_mode(mode: String) -> void:
	var monitor := mode == "monitor"
	%Frame.visible = not monitor
	%MonitorHeader.visible = monitor
	var destination: Control = %MonitorHeader if monitor else %Rows
	if %ModeRow.get_parent() != destination:
		%ModeRow.reparent(destination)
		if not monitor:
			%Rows.move_child(%ModeRow, 0)
	%Mode.text = config.copy.monitor_title if monitor else config.copy.classroom_title
	%ReturnOffice.text = config.copy.monitor_return if monitor else config.copy.classroom_return
	%Status.text = config.copy.monitor_status if monitor else config.copy.classroom_status


func select_student(index: int, student_name: String) -> void:
	_selected = index
	%Target.text = config.copy.target % student_name
	%Profile.disabled = index < 0


func selected_student() -> int:
	return _selected


func update_commands(snapshot: Dictionary, status: String) -> void:
	var available := (
		str(snapshot.command).is_empty()
		and int(snapshot.called) < 0
		and not bool(snapshot.held_by_class)
	)
	%Seats.disabled = not available
	%Conflict.disabled = not available
	%PrivateChat.disabled = not available
	%Status.text = status
	%Hint.text = str(config.copy.pending_hint)


func _style_button(button: Button) -> void:
	STYLE.button(button)
	button.add_theme_font_override("font", FONTS.regular())
	button.add_theme_font_size_override("font_size", int(config.font_size))
	button.add_theme_constant_override("icon_max_width", int(config.icon_size))
	button.add_theme_constant_override("h_separation", int(config.gap))
	button.expand_icon = true
	button.add_theme_color_override("icon_normal_color", Color(STYLE.settings().teal))
	button.add_theme_color_override("icon_hover_color", Color(STYLE.settings().paper))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _fit() -> void:
	if config.is_empty():
		return
	var design := Vector2(config.design_size[0], config.design_size[1])
	var factor := minf(size.x / design.x, size.y / design.y)
	%Design.scale = Vector2.ONE * factor
	%Design.position = (size - design * factor) / 2.0
