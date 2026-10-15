extends SceneTree
## 真实教室往返与只读工具集成校验；独立进程，不修改正式存档。

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var state: Node = root.get_node("GameState")
	state.start_game(20261014, 16)
	var core: Variant = state.sim_core
	var scene: Node = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.get_node("Player").enabled = false
	scene.get_node("Interaction").set_process(false)
	for frame in range(180):
		if scene.has_node("OfficeHub"):
			break
		await physics_frame
	var hub: Node = scene.get_node_or_null("OfficeHub")
	check(hub != null, "教室应安装 OfficeHub")
	if hub == null:
		quit(1)
		return
	check(not scene.get_node("Player").enabled, "安装办公室不得解除原有输入禁用")
	check(not scene.get_node("Interaction").is_processing(), "安装办公室不得解除原有处理禁用")
	check(hub.mode_name() == "monitor", "开局教室默认监控视角")
	check(not hub.teacher_view().get_node("%Frame").visible, "监控不显示老师行动和当前对象面板")
	check(hub._return.is_visible_in_tree(), "监控仍有关闭入口")
	check(not scene.get_node("ActionBar").visible, "老师教室不显示学生行为栏")
	check(not scene.get_node("ChatHUD").visible, "老师界面移除旧学生事件反馈")
	check(not scene.get_node("ChatHUD").is_processing(), "旧邀请不能继续刷新弹窗")
	for index in range(core.node_count()):
		if core.is_player(index):
			check(not scene.get_node("Actors").actor_for(index).visible, "不显示旧玩家为第17名学生")
			check(
				scene.get_node("Actors").actor_for(index).get_node("PickBody").collision_layer == 0,
				"隐藏的旧玩家不拦截学生拾取"
			)
	scene.get_node("Player").enabled = true
	scene.get_node("Interaction").set_process(true)
	scene.get_node("TransitionOverlay").force_hide()
	scene.get_node("TimeFlow").refresh()
	hub.set_mode("office")
	check(not scene.get_node("Player").enabled, "办公室禁止现场输入")
	check(hub.mode_name() == "office", "办公室模式")
	check(
		not scene.get_node("ActionBar/BackpackEntry/BackpackButton").visible,
		"办公室隐藏嵌套 CanvasLayer 的现场书包入口"
	)
	var before: int = core.time_snapshot().global_tick
	scene.get_node("Clock").pump(1.1)
	check(core.time_snapshot().global_tick > before, "办公室不暂停模拟")
	hub.set_mode("monitor")
	check(not scene.get_node("Player").enabled, "监控为只读")
	check(not scene.get_node("ActionBar").visible, "监控隐藏现场行为栏")
	hub.set_mode("classroom")
	check(not scene.get_node("Player").enabled, "进入教室也不恢复旧学生移动")
	check(not scene.get_node("ActionBar").visible, "实际教室使用老师操作而非学生行为")
	check(not scene.get_node("ChatHUD").visible, "实际教室不恢复旧邀请")
	check(not scene.get_node("Interaction").is_processing(), "实际教室不再轮询学生纸条")
	var teacher_ui: Control = hub.teacher_view()
	check(teacher_ui.visible, "显示原生老师操作面板")
	check(teacher_ui.get_node("%Frame").visible, "实际进入教室才显示老师行动")
	var camera: Camera3D = root.get_camera_3d()
	var picked := false
	for index in range(core.node_count()):
		if core.is_player(index):
			continue
		var actor: Node3D = scene.get_node("Actors").actor_for(index)
		var shape: CollisionShape3D = actor.get_node("PickBody").get_child(0)
		var point := camera.unproject_position(shape.global_position)
		if scene.get_node("Player").pick_actor(point) != index:
			continue
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = point
		hub._unhandled_input(click)
		picked = teacher_ui.selected_student() == index
		if picked:
			break
	check(picked, "禁用旧移动后仍可通过真实教室射线选择学生")
	check(hub._return.get_global_rect().position.x > root.size.x / 2.0, "返回入口在右侧，不遮教室中央")
	scene.get_node("NotePrompt").show_offer()
	scene.get_node("ChatHUD")._invitation_card.show()
	hub.set_mode("monitor")
	hub.set_mode("classroom")
	check(not scene.get_node("NotePrompt").is_open(), "切换清理旧纸条卡片")
	check(not scene.get_node("ChatHUD").visible, "旧邀请即使被刷新也不能显示")
	hub.select_observed_student(0)
	check(teacher_ui.selected_student() == 0, "监控／现场可选择学生")
	teacher_ui.profile_requested.emit(0)
	check(scene.get_node("UI/NpcProfile").is_open(), "老师面板可查看选中学生档案")
	await process_frame
	await process_frame
	var profile_targets: OptionButton = scene.get_node("UI/NpcProfile").get_node("%Targets")
	var target_press := InputEventScreenTouch.new()
	target_press.index = 0
	target_press.pressed = true
	target_press.position = profile_targets.size / 2.0
	profile_targets.gui_input.emit(target_press)
	var target_release := target_press.duplicate() as InputEventScreenTouch
	target_release.pressed = false
	profile_targets.gui_input.emit(target_release)
	var profile_picker: Control = scene.get_node("UI/NpcProfile").get_node("%TargetPicker")
	check(profile_picker.visible, "Touch opens relationship picker")
	await process_frame
	var slot: Button = scene.get_node("UI/NpcProfile").get_node("%TargetSlot1")
	var item_touch := InputEventScreenTouch.new()
	item_touch.index = 0
	item_touch.pressed = true
	item_touch.position = slot.size / 2.0
	slot.gui_input.emit(item_touch)
	var item_release := item_touch.duplicate() as InputEventScreenTouch
	item_release.pressed = false
	slot.gui_input.emit(item_release)
	check(profile_targets.selected == 1, "Touch chooses relationship target")
	check(not profile_picker.visible, "Picking closes target picker")
	check(scene.get_node("UI/NpcProfile").get_node("%Chat").text == "叫来办公室", "老师档案禁止旧学生闲聊")
	scene.get_node("UI/NpcProfile").get_node("%Chat").pressed.emit()
	check(hub.mode_name() == "office" and hub.picker_visible(), "档案叫来办公室跳转真实办公室入口")
	check(not scene.get_node("UI/NpcProfile").is_open(), "办公室入口关闭档案")
	hub.close_picker()
	check(not paused, "关闭办公室选择器后释放导航暂停")
	check(state.sim_core == core, "往返不重建内核")
	hub.set_mode("office")
	hub.open_tool("board")
	var board_entry: Node = scene.get_node("UI/ClueBoardEntry")
	check(board_entry.is_open(), "办公室可打开已有推理板")
	var board: Node = board_entry.get_node("Board")
	board_entry.record_observed_event(
		{"kind": "chat", "i": 0, "j": 1}, {"day": int(core.time_snapshot().day), "global_tick": 42}
	)
	board_entry.open()
	var board_count: int = board.displayed_page().events.size()
	board_entry.close()
	hub.set_mode("classroom")
	hub.set_mode("office")
	hub.open_tool("board")
	check(board.displayed_page().events.size() == board_count, "切场景保留当天推理板")
	board_entry.close()
	hub.open_tool("encyclopedia")
	var book: Node = scene.get_node("UI/EncyclopediaEntry")
	check(book.is_open(), "办公室可打开百科")
	book.close()
	hub.open_tool("profile")
	check(hub.picker_visible(), "档案入口先选择学生")
	hub.select_student(0)
	check(scene.get_node("UI/NpcProfile").is_open(), "选择学生打开原档案")
	check(scene.get_node("UI/NpcProfile").get_node("%Chat").text == "叫来办公室", "办公室档案不得触发旧现场聊天")
	scene.get_node("UI/NpcProfile").close()
	paused = true
	hub.open_tool("encyclopedia")
	book.close()
	check(paused, "工具关闭保留先前暂停")
	paused = false
	hub.open_tool("summon")
	hub.select_student(0)
	check(not scene.get_node("Player").enabled, "召唤占位不启动现场动作")
	check(state.sim_core == core, "工具不换内核")
	hub.close_picker()
	var monitor_button: Button = hub.office_view().action_button("monitor")
	var touch := InputEventScreenTouch.new()
	touch.position = monitor_button.size / 2.0
	touch.pressed = true
	monitor_button.gui_input.emit(touch)
	touch = touch.duplicate()
	touch.pressed = false
	monitor_button.gui_input.emit(touch)
	check(hub.mode_name() == "monitor", "原生触摸能打开监控")
	hub.set_mode("office")
	touch = touch.duplicate()
	touch.pressed = true
	monitor_button.gui_input.emit(touch)
	touch = touch.duplicate()
	touch.pressed = false
	touch.canceled = true
	monitor_button.gui_input.emit(touch)
	check(hub.mode_name() == "office", "取消触摸不得触发按钮")
	hub.open_tool("profile")
	await process_frame
	await process_frame
	var student_button: Button = hub._students.get_child(0)
	touch = touch.duplicate()
	touch.canceled = false
	touch.pressed = true
	touch.position = student_button.get_global_rect().get_center()
	hub._students.get_parent()._input(touch)
	var button_touch: InputEventScreenTouch = touch.duplicate()
	button_touch.position = student_button.size / 2.0
	student_button.gui_input.emit(button_touch)
	await process_frame
	check(student_button.has_meta("office_touch"), "触摸测试应命中真实学生按钮")
	var drag := InputEventScreenDrag.new()
	drag.position = touch.position + Vector2(0, -40)
	drag.relative = Vector2(0, -40)
	hub._students.get_parent()._input(drag)
	await process_frame
	check(not student_button.has_meta("office_touch"), "滚动开始必须取消学生按钮按下记录")
	touch = touch.duplicate()
	touch.pressed = false
	touch.position = drag.position
	button_touch = touch.duplicate()
	button_touch.position = student_button.size / 2.0
	student_button.gui_input.emit(button_touch)
	await process_frame
	check(hub.picker_visible(), "滚动消费拖动后，松手不得选中学生")
	check(not scene.get_node("UI/NpcProfile").is_open(), "列表滚动不打开档案")
	hub.close_picker()
	for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		await process_frame
		await process_frame
		var office: Control = hub.office_view()
		for key in ["monitor", "classroom", "summon", "profile", "board", "encyclopedia"]:
			var rect: Rect2 = office.action_button(key).get_global_rect()
			check(
				Rect2(Vector2.ZERO, office.get_viewport_rect().size).encloses(rect), "按钮在画面内：" + key
			)
		hub.set_mode("monitor")
		await process_frame
		check(not teacher_ui.get_node("%Frame").visible, "任意横屏尺寸下监控不显示行动纸卡")
		hub.set_mode("classroom")
		await process_frame
		var frame_rect: Rect2 = teacher_ui.get_node("%Frame").get_global_rect()
		var tools_rect: Rect2 = teacher_ui.get_node("%Tools").get_global_rect()
		check(frame_rect.encloses(teacher_ui.get_node("%Profile").get_global_rect()), "档案按钮在老师纸卡内")
		check(frame_rect.end.y < tools_rect.position.y, "老师操作面板不压底部入口")
		check(
			Rect2(Vector2.ZERO, teacher_ui.get_viewport_rect().size).encloses(frame_rect),
			"老师面板在画面内"
		)
		hub.set_mode("office")
	print(
		"OFFICE HUB: ",
		"PASS" if failures.is_empty() else "FAIL",
		" (",
		failures.size(),
		" failures)"
	)
	quit(0 if failures.is_empty() else 1)
