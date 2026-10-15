extends SceneTree
## 真实教室接线：办公室不偷看、监控录入、日末自动弹出与次日隔离。

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_verify")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func _verify() -> void:
	var state: Node = root.get_node("GameState")
	state.start_game(20261014, 16)
	var room: Node = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	for frame in range(240):
		if room.has_node("OfficeHub"):
			break
		await physics_frame
	var hub: Node = room.get_node("OfficeHub")
	var entry: Node = room.get_node("UI/ClueBoardEntry")
	var clock: SimulationClock = room.get_node("Clock")
	hub.set_mode("office")
	root.get_node("EventBus").event_happened.emit({"kind": "chat", "i": 0, "j": 1})
	entry.open()
	check(entry.get_node("Board").displayed_page().events.is_empty(), "办公室不补录未观察事件")
	entry.close()
	hub.set_mode("monitor")
	root.get_node("EventBus").event_happened.emit({"kind": "comfort", "i": 0, "j": 1})
	entry.open()
	check(entry.get_node("Board").displayed_page().events.size() == 1, "监控录入公开互动")
	entry.close()
	for step in range(2000):
		room.get_node("TransitionOverlay").force_hide()
		room.get_node("TransitionOverlay").hide()
		room.get_node("TimeFlow").refresh()
		clock.pump(1000.0)
		if str(clock.snapshot().mode) != "running":
			break
	check(str(clock.snapshot().mode) == "report", "真实时钟到达日末")
	check(entry.is_open() and paused, "真实日末自动打开并暂停")
	check(not room.get_node("TransitionOverlay").visible, "日末不能被旧黑幕遮挡")
	check(entry.get_node("Board").displayed_page().sealed, "日末页已归档")
	entry.close()
	check(str(clock.snapshot().mode) == "running" and not paused, "手记继续按钮进入次日")
	entry.open()
	var page: Dictionary = entry.get_node("Board").displayed_page()
	check(int(page.day) == 2 and page.people.is_empty(), "次日是干净的新页面")
	entry.show_day(1)
	check(not entry.get_node("Board").displayed_page().events.is_empty(), "可回看前日归档")
	entry.close()
	room.queue_free()
	await process_frame
	state.end_game()
	print(
		"CLUE_BOARD_FLOW: ",
		"PASS" if failures.is_empty() else "FAIL",
		" failures=",
		failures.size()
	)
	call_deferred("quit", 0 if failures.is_empty() else 1)
