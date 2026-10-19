extends CanvasLayer
## 保留教室与时钟的视图协调器，不承担老师行为规则。

const OFFICE := preload("res://scenes/game/office.tscn")
const TEACHER_UI := preload("res://scenes/ui/teacher_classroom.tscn")
const TEACHER_PRESENCE := preload("res://scenes/components/teacher_presence.tscn")
const PROFILE_DATA := preload("res://scripts/ui/npc_profile_data.gd")
const VOICE_INPUT := preload("res://scripts/game/voice_input.gd")
const VOICE_ACTIONS := ["comfort", "praise", "scold", "encourage"]

var _view: Control
var _room: Node
# ⚠️ 初值必须不是 "classroom"：bind_classroom() 末尾以 classroom 开局，而 set_mode 只在
#    `_mode != "classroom"` 时才调用 enter_classroom（D03 的首次进场全班 +5 压力）。
var _mode := ""
var _return: Button
var _teacher: Control
var _teacher_presence: Node3D
var _touch_pick := -1
var _touch_start := Vector2.ZERO
var _picker_layer: CanvasLayer
var _picker: Control
var _picker_kind := ""
var _pair_first := -1
var _saved_visible: Dictionary = {}
var _ask_seen := 0
var _interlude: Control
# 进入办公室前的页面（classroom / monitor）。办公室是子页面，返回时回这里，
# 不写死回办公室或监控；空串表示没有来路（开局直接进场等）。
var _office_origin := ""
# 打开当前这份名单时要记住的「上一界面」：只有进办公室顺带弹名单时才填（教室／监控）。
# 空串 = 办公室内部自己打开的名单，取消后不切页面。
var _picker_back_target := ""
# 声量窗口（可选挑战模式）：开启时谈话前 2.5 秒采样；关闭时整段旁路。
var _voice: Node
var _voice_window_active := false
var _duck_active := false
var _music_db := 0.0
var _sfx_db := 0.0


func bind_classroom(room: Node) -> void:
	_room = room
	layer = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = OFFICE.instantiate()
	add_child(_view)
	_view.hide()
	_view.bind_sources(room.get_node("Clock"))
	_view.action_requested.connect(_on_action)
	_view.voice_hold_started.connect(_on_voice_hold_started)
	_view.voice_hold_ended.connect(_on_voice_hold_ended)
	_voice = VOICE_INPUT.new()
	add_child(_voice)
	_voice.tier_locked.connect(_on_voice_tier_locked)
	_voice.mic_failed.connect(_on_voice_mic_failed)
	for path in ["UI/EncyclopediaEntry", "UI/NpcProfile", "UI/PauseMenu"]:
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
	_interlude = preload("res://scripts/ui/teacher_interlude.gd").new()
	var modal_layer := CanvasLayer.new()
	modal_layer.name = "TeacherInterludeLayer"
	var modal_config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/teacher_interlude.json")
	)
	modal_layer.layer = int(modal_config.layer)
	add_child(modal_layer)
	modal_layer.add_child(_interlude)
	_interlude.cancel_requested.connect(_cancel_intervention)
	_capture_classroom_state()
	# 2026-10-18 裁定：开局老师直接进教室，不再以监控视角开场；
	# 走真实 enter_classroom，含 D03「每个课间首次进入 → 全班压力 +5」。
	set_mode("classroom")


func mode_name() -> String:
	return _mode


func office_view() -> Control:
	return _view


func teacher_view() -> Control:
	return _teacher


func set_mode(next: String) -> bool:
	if next not in ["office", "monitor", "classroom"] or _room == null:
		return false
	var core: Variant = _room.get_node("Actors").current_core()
	var commands = core.teacher_commands()
	if _mode == "office" and next != "office" and _voice_window_active:
		_voice.finish_now()
	if next == "classroom" and _mode != "classroom":
		if commands.current_command() != "" or commands.called_index() >= 0:
			return false
		commands.enter_classroom(core)
	# Office thumbnail keeps the last teacher-free monitor frame.
	# Hiding a sprite cannot change the viewport image already rendered this frame.
	if _mode == "monitor" and next != "monitor":
		_view.capture_preview()
	if next == "office" and _mode != "office":
		# 记下来路：办公室里的「返回」（名单返回 / ESC）要回到进入前的页面。
		_office_origin = _mode if _mode in ["classroom", "monitor"] else ""
		_capture_classroom_state()
		_room.get_node("ActionBar").backpack.close()
	elif next != "office":
		_office_origin = ""
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
	return true


## 离开办公室：回到进入前的页面（教室 → 教室，监控 → 监控）；没有来路才回监控。
## 命令进行中／学生还在等时 set_mode 会拒绝切教室，退回监控（与旧行为一致）。
func _leave_office() -> void:
	var destination := _office_origin if _office_origin != "" else "monitor"
	if not set_mode(destination):
		set_mode("monitor")


## 选人名单的「‹ 返回」= 玩家自己取消，回到「打开这份名单之前的界面」。
## 教室／监控点私聊（或档案「叫来办公室」）是先进办公室再弹名单，所以打开时要显式传回进入前的页面；
## 办公室内部自己打开的名单（叫同学来、同学档案、调座位…）没传目标，取消后就留在办公室。
func _on_picker_closed() -> void:
	var target := _picker_back_target
	_picker_back_target = ""
	close_picker()
	if target == "" or target == _mode:
		return
	# 学生已叫来 / 谈话进行中：不把人丢在办公室，留在当前页面。
	var commands = _room.get_node("Actors").current_core().teacher_commands()
	if commands.current_command() != "" or commands.called_index() >= 0:
		return
	set_mode(target)


func _process(_delta: float) -> void:
	if _room == null or _view == null or _teacher == null:
		return
	var core: Variant = _room.get_node("Actors").current_core()
	var snapshot: Dictionary = core.teacher_commands().snapshot()
	if _interlude != null:
		_interlude.refresh(core, snapshot)
	if _voice_window_active:
		if not VoiceSettings.is_enabled():
			_voice.finish_now()
		elif str(snapshot.get("command", "")) != "office_chat":
			_voice.abort_window()
			_voice_window_active = false
			_unduck_audio()
		elif bool(snapshot.get("held_by_class", false)):
			_voice.finish_now()
		else:
			_view.set_voice_live(true, _voice.current_intensity(), _voice.live_tier())
	else:
		_view.set_voice_live(false, 0.0, 2)
	_view.update_commands(core, snapshot)
	# 声量条并入演出弹窗：弹窗盖住办公室面板后仍能看到实时档位与预计效果。
	if _interlude != null:
		_interlude.set_voice_state(_view.voice_state(core, snapshot))
	_teacher.update_commands(snapshot, _view.command_status(snapshot))
	_apply_talk_fast_forward(snapshot)
	var ask_id := int(snapshot.get("ask_id", 0))
	if ask_id != _ask_seen:
		_ask_seen = ask_id
		var lines: Array = snapshot.get("ask_lines", [])
		if not lines.is_empty():
			_view.present_ask(lines)
		_write_ask_records(snapshot.get("ask_records", []))


## 谈话（office_chat）进行中自动快进：老师版没有「快进」按钮，改成「谈话期间临时加速到 fast_forward_scale」，
## 谈话结束（命令清空）自动还原到玩家自选档。逐帧按 owner 请求/释放，TimeFlow 的 owner-hold 幂等，重复调用安全。
func _apply_talk_fast_forward(snapshot: Dictionary) -> void:
	var clock: Node = _room.get_node("Clock")
	# 声量采样必须是真实 5 秒：强制 1×，不受玩家自选 2×/3× 影响。
	if _voice_window_active:
		clock.request_normal_speed(&"voice_window")
		clock.release_fast_forward(&"office_chat")
		return
	clock.release_normal_speed(&"voice_window")
	var talking := str(snapshot.get("command", "")) == "office_chat"
	if talking:
		clock.request_fast_forward(&"office_chat")
	else:
		clock.release_fast_forward(&"office_chat")


## D10：打听获知的有向单轴关系真值写入档案笔记（NpcProfileData 只读笔记，不碰真实矩阵）。
func _write_ask_records(records: Array) -> void:
	if records.is_empty():
		return
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return
	var model: RefCounted = PROFILE_DATA.new()
	model.state = state.profile_notebook
	model.record_ask(records)


func _capture_classroom_state() -> void:
	if not _saved_visible.is_empty():
		return
	for path in [
		"TimeHUD",
		"ActionBar",
		"ActionBar/BackpackEntry/BackpackButton",
		"ChatHUD",
		"UI/EncyclopediaEntry/EncyclopediaButton"
	]:
		var node: Node = _room.get_node_or_null(path)
		if node != null:
			_saved_visible[path] = node.visible


func _on_profile_summon(index: int) -> void:
	var origin := _mode
	set_mode("office")
	_show_picker("summon", origin)
	select_student(index)


func _refresh_profile_binding() -> void:
	_room.get_node("UI/NpcProfile").bind_sources(
		_room.get_node("Actors").current_core(), _room.get_node("Actors"), null
	)


func _cancel_intervention() -> void:
	var core: Variant = _room.get_node("Actors").current_core()
	core.teacher_commands().cancel_intervention()
	_process(0.0)


func _on_action(action: String) -> void:
	if action in VOICE_ACTIONS and VoiceSettings.is_enabled():
		if VoiceSettings.input_mode() == "hold":
			return  # 按住模式由 button_down / button_up 驱动
		_start_voice_action(action)
		return
	if action in ["comfort", "scold", "praise", "ask", "encourage", "send_back"]:
		# 点击反馈：安慰 → comfort_voice，表扬 → teacher_praise，训斥 → teacher_scold
		if action == "comfort":
			SFX.play_one_shot("ComfortVoice")
		elif action == "praise":
			SFX.play_one_shot("TeacherPraise")
		elif action == "scold":
			SFX.play_one_shot("TeacherScold")
		var core: Variant = _room.get_node("Actors").current_core()
		var commands = core.teacher_commands()
		if action == "send_back":
			commands.send_back(core)
		else:
			commands.office_chat(core, action)
		_process(0.0)
	elif action == "cancel_chat":
		_voice.abort_window()
		_voice_window_active = false
		_unduck_audio()
		var core: Variant = _room.get_node("Actors").current_core()
		core.teacher_commands().cancel_office_chat()
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
		# 教室／监控点「私聊」= 进办公室并选人；取消这份名单就回到进入前的页面。
		var origin := _mode
		set_mode("office")
		_show_picker("summon", origin)
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


# ------------------------------------------------------------------ 声量窗口
func _start_voice_action(action: String) -> bool:
	var core: Variant = _room.get_node("Actors").current_core()
	var commands = core.teacher_commands()
	if not commands.office_chat(core, action, true):
		return false
	_voice.configure(commands.voice_rules())
	_duck_audio(true, commands.voice_rules().duck_db)
	if not _voice.begin_window(VoiceSettings.input_mode() == "hold"):
		_voice_window_active = false
		_unduck_audio()
		_process(0.0)
		return true
	_voice_window_active = true
	_process(0.0)
	return true


func _on_voice_hold_started(action: String) -> void:
	if not VoiceSettings.is_enabled() or VoiceSettings.input_mode() != "hold":
		return
	if action in VOICE_ACTIONS:
		_start_voice_action(action)


func _on_voice_hold_ended(_action: String) -> void:
	if _voice_window_active:
		_voice.end_hold()


func _on_voice_tier_locked(tier: int) -> void:
	if _room == null:
		return
	var core: Variant = _room.get_node("Actors").current_core()
	core.teacher_commands().set_office_voice(tier)
	_voice_window_active = false
	_unduck_audio()
	_process(0.0)


func _on_voice_mic_failed(reason: String) -> void:
	_voice_window_active = false
	_unduck_audio()
	push_warning("声量：%s；本次按平常档结算。" % reason)


func _duck_audio(on: bool, db: float = -12.0) -> void:
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	if on and not _duck_active:
		_music_db = AudioServer.get_bus_volume_db(music) if music >= 0 else 0.0
		_sfx_db = AudioServer.get_bus_volume_db(sfx) if sfx >= 0 else 0.0
		if music >= 0:
			AudioServer.set_bus_volume_db(music, _music_db + db)
		if sfx >= 0:
			AudioServer.set_bus_volume_db(sfx, _sfx_db + db)
		_duck_active = true
	elif not on and _duck_active:
		if music >= 0:
			AudioServer.set_bus_volume_db(music, _music_db)
		if sfx >= 0:
			AudioServer.set_bus_volume_db(sfx, _sfx_db)
		_duck_active = false


func _unduck_audio() -> void:
	_duck_audio(false)


func select_observed_student(index: int) -> void:
	var core: Variant = _room.get_node("Actors").current_core()
	if index < 0 or index >= core.node_count():
		return
	_teacher.select_student(index, str(core.alias(index)))


func open_tool(action: String) -> void:
	if action == "encyclopedia":
		_room.get_node("UI/EncyclopediaEntry").open()
	elif action in ["profile", "summon"]:
		_show_picker(action)


func _build_picker() -> void:
	_picker_layer = CanvasLayer.new()
	_picker_layer.name = "StudentPicker"
	_picker_layer.layer = 6
	add_child(_picker_layer)
	_picker = preload("res://scripts/ui/student_roster.gd").new()
	_picker_layer.add_child(_picker)
	_picker.student_selected.connect(select_student)
	_picker.seat_requested.connect(_confirm_seats)
	_picker.closed.connect(_on_picker_closed)


func _show_picker(kind: String, back_target := "") -> void:
	_picker_kind = kind
	_pair_first = -1
	# 空串 = 办公室内部打开的名单：取消后留在原页面（不切视图）。
	_picker_back_target = back_target
	var core: Variant = _room.get_node("Actors").current_core()
	_picker.open(core, kind)


func _confirm_seats(first: int, second: int) -> void:
	var core: Variant = _room.get_node("Actors").current_core()
	if core.teacher_commands().start_seat_change(core, first, second):
		# 2026-10-19 裁定：换座即时生效、不耗课间时间，换完**留在选座页**，
		# 卡片按新座位重排并清空已选，老师可以直接接着换下一组。
		_picker.refresh_after_seat_change(first, second)
	else:
		_picker.show_message(str(_view.config.meeting.rejected))
	_process(0.0)


func picker_visible() -> bool:
	return _picker != null and _picker.visible


func select_student(index: int) -> void:
	var core: Variant = _room.get_node("Actors").current_core()
	if index < 0 or index >= core.node_count():
		return
	if _picker.get("_mode") == "profile":
		close_picker()
		_room.get_node("UI/NpcProfile").open_profile(index)
	elif _picker.get("_mode") == "seats":
		_picker.select_student(index)
	elif _picker_kind == "mediate":
		if _pair_first < 0:
			_pair_first = index
			_picker.show_message(_view.config.meeting.pair_second % str(core.alias(index)))
			return
		var commands = core.teacher_commands()
		var accepted: bool = commands.mediate(core, _pair_first, index)
		if accepted:
			close_picker()
		else:
			_picker.show_message(
				(
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
			)
	else:
		if core.teacher_commands().summon(core, index):
			close_picker()
		else:
			_picker.show_message(str(_view.config.meeting.rejected))
	_process(0.0)


func close_picker() -> void:
	_picker.hide()


func _unhandled_input(event: InputEvent) -> void:
	if _interlude != null and _interlude.visible:
		if event.is_action_pressed("ui_cancel"):
			_interlude.collapse()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		# 暂停菜单自己收 ESC（本节点 PROCESS_MODE_ALWAYS 会早于它收到）；暂停中不切页面。
		if get_tree().paused:
			return
		if picker_visible():
			_on_picker_closed()
			get_viewport().set_input_as_handled()
			return
		if _mode == "office":
			# 办公室是教室的子页面：返回键回到进入前的页面（教室／监控），不写死回监控。
			_leave_office()
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
