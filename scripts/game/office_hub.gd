extends CanvasLayer
## 保留教室与时钟的视图协调器，不承担老师行为规则。

const OFFICE := preload("res://scenes/game/office.tscn")
const TEACHER_UI := preload("res://scenes/ui/teacher_classroom.tscn")

var _view: Control
var _room: Node
var _mode := "classroom"
var _return: Button
var _teacher: Control
var _touch_pick := -1
var _touch_start := Vector2.ZERO
var _picker_layer: CanvasLayer
var _picker: Control
var _students: VBoxContainer
var _message: Label
var _picker_title: Label
var _picker_kind := ""
var _owns_pause := false
var _saved_visible: Dictionary = {}


func bind_classroom(room: Node) -> void:
	_room = room
	layer = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = OFFICE.instantiate()
	add_child(_view)
	_view.hide()
	_view.bind_sources(room.get_node("Clock"))
	_view.action_requested.connect(_on_action)
	for path in ["UI/EncyclopediaEntry", "UI/ClueBoardEntry", "UI/NpcProfile", "UI/PauseMenu"]:
		_bind_tool_touch(room.get_node(path))
	var replay: Button = room.get_node("UI/PauseMenu").settings_panel.replay_btn
	replay.disabled = true
	# PauseMenu 属于 UI 层；复用既有层级确保暂停菜单高于办公室。
	room.get_node("UI").layer = 4
	_teacher = TEACHER_UI.instantiate()
	add_child(_teacher)
	var actors: Node = room.get_node("Actors")
	var core: Variant = actors.current_core()
	for index in range(core.node_count()):
		if core.is_player(index):
			var actor: Node3D = actors.actor_for(index)
			actor.hide()
			var pick_body := actor.get_node_or_null("PickBody") as Area3D
			if pick_body != null:
				pick_body.collision_layer = 0
	_teacher.action_requested.connect(_on_teacher_action)
	_teacher.profile_requested.connect(_room.get_node("UI/NpcProfile").open_profile)
	_bind_tool_touch(_teacher)
	_return = _teacher.get_node("%ReturnOffice")
	replay.tooltip_text = _teacher.config.copy.disabled_tutorial
	_build_picker()
	_capture_classroom_state()
	set_mode("monitor")


func mode_name() -> String:
	return _mode


func office_view() -> Control:
	return _view


func teacher_view() -> Control:
	return _teacher


func set_mode(next: String) -> void:
	if next not in ["office", "monitor", "classroom"] or _room == null:
		return
	if next == "office" and _mode != "office":
		_view.capture_preview()
		_capture_classroom_state()
		_room.get_node("ActionBar").backpack.close()
	_mode = next
	_view.visible = next == "office"
	_teacher.visible = next != "office"
	_teacher.set_mode(next)
	_room.get_node("Player").enabled = false
	var interaction: Node = _room.get_node("Interaction")
	interaction.set_process(false)
	interaction.set_process_unhandled_input(false)
	interaction.set_process_input(false)
	_room.get_node("ChatHUD").set_process(false)
	for path in _saved_visible:
		var node: Node = _room.get_node(path)
		node.visible = _saved_visible[path] if path == "TimeHUD" and next != "office" else false
	_refresh_profile_binding()


func _capture_classroom_state() -> void:
	if not _saved_visible.is_empty():
		return
	for path in [
		"TimeHUD",
		"ActionBar",
		"ActionBar/BackpackEntry/BackpackButton",
		"ChatHUD",
		"UI/EncyclopediaEntry/EncyclopediaButton",
		"UI/ClueBoardEntry/BoardButton"
	]:
		var node: Node = _room.get_node_or_null(path)
		if node != null:
			_saved_visible[path] = node.visible


func _refresh_profile_binding() -> void:
	_room.get_node("UI/NpcProfile").bind_sources(
		_room.get_node("Actors").current_core(), _room.get_node("Actors"), null
	)


func _on_action(action: String) -> void:
	if action in ["monitor", "classroom"]:
		set_mode(action)
	elif action in ["pause", "settings"]:
		var menu: Control = _room.get_node("UI/PauseMenu")
		menu.show()
		get_tree().paused = true
		if action == "settings":
			menu.settings_panel.show()
	else:
		open_tool(action)


func _on_teacher_action(action: String) -> void:
	if action in ["office", "classroom"]:
		set_mode(action)
	elif action == "private_chat":
		set_mode("office")
		open_tool("summon")
	else:
		open_tool(action)


func select_observed_student(index: int) -> void:
	var core: Variant = _room.get_node("Actors").current_core()
	if index < 0 or index >= core.node_count() or core.is_player(index):
		return
	_teacher.select_student(index, str(core.alias(index)))


func open_tool(action: String) -> void:
	if action == "board":
		_room.get_node("UI/ClueBoardEntry").open()
	elif action == "encyclopedia":
		_room.get_node("UI/EncyclopediaEntry").open()
	elif action in ["profile", "summon"]:
		_show_picker(action)


func _build_picker() -> void:
	_picker_layer = CanvasLayer.new()
	_picker_layer.name = "StudentPicker"
	_picker_layer.layer = 6
	add_child(_picker_layer)
	_picker = Control.new()
	_picker_layer.add_child(_picker)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	_picker.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	_picker.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "PickerPanel"
	center.add_child(panel)
	panel.add_theme_stylebox_override("panel", _view.paper_style())
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	rows.add_theme_constant_override("separation", int(_view.config.gap))
	_picker_title = Label.new()
	rows.add_child(_picker_title)
	_picker_title.add_theme_font_size_override("font_size", int(_view.config.font_size))
	_picker_title.add_theme_color_override("font_color", Color(_view.config.ink))
	var scroll := ScrollContainer.new()
	scroll.set_script(preload("res://scripts/game/office_student_scroll.gd"))
	scroll.custom_minimum_size.y = float(_view.config.picker_height) / 2.0
	rows.add_child(scroll)
	scroll.set_process_input(false)
	_students = VBoxContainer.new()
	scroll.add_child(_students)
	_students.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", int(_view.config.small_font_size))
	_message.add_theme_color_override("font_color", Color(_view.config.ink))
	rows.add_child(_message)
	var close := Button.new()
	close.text = _view.config.copy.close
	rows.add_child(close)
	_view.style_button(close)
	close.pressed.connect(close_picker)
	_picker.hide()
	get_viewport().size_changed.connect(_fit_picker)
	_fit_picker()


func _fit_picker() -> void:
	if _picker == null:
		return
	var panel: Control = _picker.get_node("CenterContainer/PickerPanel")
	panel.custom_minimum_size.x = minf(
		float(_view.config.picker_width), get_viewport().get_visible_rect().size.x * 0.85
	)


func _show_picker(kind: String) -> void:
	_picker_kind = kind
	_picker_title.text = (
		_view.config.copy.profile_picker if kind == "profile" else _view.config.copy.summon_picker
	)
	_message.text = ""
	for child in _students.get_children():
		_students.remove_child(child)
		child.queue_free()
	var core: Variant = _room.get_node("Actors").current_core()
	for index in range(core.node_count()):
		if core.is_player(index):
			continue
		var button := Button.new()
		button.text = str(core.alias(index))
		_view.style_button(button)
		button.pressed.connect(select_student.bind(index))
		_students.add_child(button)
	_owns_pause = not get_tree().paused
	get_tree().paused = true
	_picker.show()
	_students.get_parent().set_process_input(true)


func picker_visible() -> bool:
	return _picker != null and _picker.visible


func select_student(index: int) -> void:
	var core: Variant = _room.get_node("Actors").current_core()
	if index < 0 or index >= core.node_count() or core.is_player(index):
		return
	if _picker_kind == "profile":
		close_picker()
		_room.get_node("UI/NpcProfile").open_profile(index)
	else:
		_message.text = _view.config.copy.summon_pending % str(core.alias(index))


func close_picker() -> void:
	_picker.hide()
	_students.get_parent().set_process_input(false)
	if _owns_pause:
		get_tree().paused = false
	_owns_pause = false


func _unhandled_input(event: InputEvent) -> void:
	if picker_visible() and event.is_action_pressed("ui_cancel"):
		close_picker()
		get_viewport().set_input_as_handled()
		return
	if _mode == "office" or get_tree().paused:
		return
	var point := Vector2.ZERO
	var pick := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		point = event.position
		pick = true
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touch_pick = event.index
			_touch_start = event.position
		elif event.index == _touch_pick:
			pick = not event.canceled
			point = event.position
			_touch_pick = -1
	elif event is InputEventScreenDrag:
		if event.position.distance_to(_touch_start) > float(_teacher.config.touch_drag_threshold):
			_touch_pick = -1
	if pick:
		var index: int = _room.get_node("Player").pick_actor(point)
		select_observed_student(index)
		get_viewport().set_input_as_handled()


func _bind_tool_touch(node: Node) -> void:
	if node is Button:
		_view.bind_touch(node)
	for child in node.get_children():
		_bind_tool_touch(child)
