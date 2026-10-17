extends CanvasLayer
## 保留教室与时钟的视图协调器，不承担老师行为规则。

const OFFICE := preload("res://scenes/game/office.tscn")
const TEACHER_UI := preload("res://scenes/ui/teacher_classroom.tscn")
const TEACHER_PRESENCE := preload("res://scenes/components/teacher_presence.tscn")

var _view: Control
var _room: Node
var _mode := "classroom"
var _return: Button
var _teacher: Control
var _teacher_presence: Node3D
var _touch_pick := -1
var _touch_start := Vector2.ZERO
var _picker_layer: CanvasLayer
var _picker: Control
var _students: VBoxContainer
var _message: Label
var _picker_title: Label
var _picker_kind := ""
var _pair_first := -1
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
	_teacher_presence = TEACHER_PRESENCE.instantiate()
	room.add_child(_teacher_presence)
	# 2026-10-16 起本局没有玩家节点：不必再隐藏「玩家自己」的形象与拾取体。
	_teacher.action_requested.connect(_on_teacher_action)
	_teacher.profile_requested.connect(_room.get_node("UI/NpcProfile").open_profile)
	var profile: NpcProfile = _room.get_node("UI/NpcProfile")
	profile.enable_teacher_navigation()
	profile.summon_requested.connect(_on_profile_summon)
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
	var core: Variant = _room.get_node("Actors").current_core()
	var commands = core.teacher_commands()
	if next == "classroom" and _mode != "classroom":
		if commands.current_command() != "" or commands.called_index() >= 0:
			return
		commands.enter_classroom(core)
	# Office thumbnail keeps the last teacher-free monitor frame.
	# Hiding a sprite cannot change the viewport image already rendered this frame.
	if _mode == "monitor" and next != "monitor":
		_view.capture_preview()
	if next == "office" and _mode != "office":
		_capture_classroom_state()
		_room.get_node("ActionBar").backpack.close()
	_mode = next
	_teacher_presence.set_view_mode(next)
	_view.visible = next == "office"
	_teacher.visible = next != "office"
	_teacher.set_mode(next)
	_room.get_node("Player").enabled = false
	_room.get_node("ChatHUD").set_process(false)
	for path in _saved_visible:
		var node: Node = _room.get_node(path)
		node.visible = _saved_visible[path] if path == "TimeHUD" and next != "office" else false
	_refresh_profile_binding()
	_process(0.0)


func _process(_delta: float) -> void:
	if _room == null or _view == null or _teacher == null:
		return
	var core: Variant = _room.get_node("Actors").current_core()
	var snapshot: Dictionary = core.teacher_commands().snapshot()
	_view.update_commands(core, snapshot)
	_teacher.update_commands(snapshot, _view.command_status(snapshot))


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


func _on_profile_summon(index: int) -> void:
	set_mode("office")
	open_tool("summon")
	select_student(index)


func _refresh_profile_binding() -> void:
	_room.get_node("UI/NpcProfile").bind_sources(
		_room.get_node("Actors").current_core(), _room.get_node("Actors"), null
	)


func _on_action(action: String) -> void:
	if action in ["comfort", "scold", "praise", "send_back"]:
		var core: Variant = _room.get_node("Actors").current_core()
		var commands = core.teacher_commands()
		if action == "send_back":
			commands.send_back(core)
		else:
			commands.office_chat(core, action)
		_process(0.0)
	elif action in ["monitor", "classroom"]:
		set_mode(action)
		if action == "classroom":
			_enter_classroom()
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
		if action == "classroom":
			_enter_classroom()
	elif action == "private_chat":
		set_mode("office")
		open_tool("summon")
	elif action in ["seats", "mediate"]:
		_show_picker(action)
	else:
		open_tool(action)


## D03：去教室按实际操作实时进行（无固定耗时）。**每个课间首次**到场 → 全班压力 +5，
## 同一课间重复进入不再生效。此前这里只切视图、没有调用内核命令，入口看着可用却不产生效果。
func _enter_classroom() -> void:
	var core: Variant = _room.get_node("Actors").current_core()
	if core == null:
		return
	core.teacher_commands().enter_classroom(core)
	_process(0.0)


func select_observed_student(index: int) -> void:
	var core: Variant = _room.get_node("Actors").current_core()
	if index < 0 or index >= core.node_count():
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
	_pair_first = -1
	_picker_title.text = (
		_view.config.copy.profile_picker if kind == "profile" else _view.config.copy.summon_picker
	)
	if kind in ["seats", "mediate"]:
		_picker_title.text = _view.config.meeting["pair_" + kind]
	_message.text = ""
	for child in _students.get_children():
		_students.remove_child(child)
		child.queue_free()
	var core: Variant = _room.get_node("Actors").current_core()
	for index in range(core.node_count()):
		var button := Button.new()
		button.text = str(core.alias(index))
		_view.style_button(button)
		button.pressed.connect(select_student.bind(index))
		_students.add_child(button)
	_picker.show()
	_students.get_parent().set_process_input(true)


func picker_visible() -> bool:
	return _picker != null and _picker.visible


func select_student(index: int) -> void:
	var core: Variant = _room.get_node("Actors").current_core()
	if index < 0 or index >= core.node_count():
		return
	if _picker_kind == "profile":
		close_picker()
		_room.get_node("UI/NpcProfile").open_profile(index)
	elif _picker_kind in ["seats", "mediate"]:
		if _pair_first < 0:
			_pair_first = index
			_picker_title.text = _view.config.meeting.pair_second % str(core.alias(index))
			return
		var commands = core.teacher_commands()
		var accepted: bool = (
			commands.start_seat_change(core, _pair_first, index)
			if _picker_kind == "seats"
			else commands.mediate(core, _pair_first, index)
		)
		if accepted:
			close_picker()
		else:
			_message.text = (
				_view.config.meeting.no_conflict
				if (
					_picker_kind == "mediate"
					and _pair_first != index
					and commands.current_command().is_empty()
					and not commands.is_held()
					and commands.called_index() < 0
				)
				else _view.config.meeting.rejected
			)
	else:
		if core.teacher_commands().summon(core, index):
			close_picker()
		else:
			_message.text = _view.config.meeting.rejected
	_process(0.0)


func close_picker() -> void:
	_picker.hide()
	_students.get_parent().set_process_input(false)


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
		if _mode == "monitor" and index >= 0 and _teacher.selected_student() == index:
			_room.get_node("UI/NpcProfile").open_profile(index)
		get_viewport().set_input_as_handled()


func _bind_tool_touch(node: Node) -> void:
	if bool(node.get_meta("handles_native_touch", false)):
		return
	if node is Button:
		_view.bind_touch(node)
	for child in node.get_children():
		_bind_tool_touch(child)
