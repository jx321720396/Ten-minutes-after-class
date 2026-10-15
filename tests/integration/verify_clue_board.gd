extends SceneTree
## 老师版推理板：每日隔离、学生边界、共享笔记、只读与原生场景。

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_verify")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func _verify() -> void:
	var path := "res://scripts/ui/clue_board_data.gd"
	check(ResourceLoader.exists(path), "缺少每日推理板数据模型")
	if not ResourceLoader.exists(path):
		quit(1)
		return
	var model: RefCounted = load(path).new()
	var students := [0, 1, 2, 3]
	model.record_event({"kind": "chat", "i": 0, "j": 1}, {"day": 1, "global_tick": 1}, students)
	model.record_event({"kind": "chat", "i": 0, "j": 1}, {"day": 1, "global_tick": 1}, students)
	model.record_event({"kind": "comfort", "i": 2, "j": 3}, {"day": 2, "global_tick": 2}, students)
	model.record_event({"kind": "chat", "i": 0, "j": 16}, {"day": 2}, students)
	model.record_event({"kind": "report", "i": 0, "j": 1}, {"day": 2}, students)
	var notebook := {
		"history":
		[
			{
				"source": 0,
				"subject": 1,
				"axis": "affinity",
				"band": "band_high",
				"origin": "guess",
				"day": 1
			},
			{
				"source": 2,
				"subject": 3,
				"axis": "affinity",
				"value": 70,
				"origin": "known",
				"day": 2
			},
			{
				"source": 2,
				"subject": 3,
				"axis": "hostility",
				"band": "band_high",
				"origin": "guess",
				"day": 2
			},
			{
				"source": 3,
				"subject": 2,
				"axis": "affinity",
				"band": "band_low",
				"origin": "guess",
				"day": 2
			}
		]
	}
	var before := notebook.duplicate(true)
	var first: Dictionary = model.page(1, notebook, students)
	var second: Dictionary = model.page(2, notebook, students)
	check(first.events.size() == 1, "同 tick 重复事件去重")
	check(second.people == [2, 3], "次日不能携带前日人物与事件，老师不能入图")
	check(second.events.size() == 1, "私有事件不得自动公开")
	check(second.judgments.size() == 3, "方向、好感、敌对不能合并覆盖")
	check(notebook == before, "只读共享笔记")
	check(model.page(3, notebook, students).people.is_empty(), "无事件日期显示空白")
	model.seal(1, notebook, students)
	var restored: RefCounted = load(path).new()
	restored.state = JSON.parse_string(JSON.stringify(model.state))
	check(
		restored.page(1, {}, students) == JSON.parse_string(JSON.stringify(first)),
		"归档 JSON 往返后保留当日内容"
	)
	var state: Node = root.get_node("GameState")
	state.start_game(12345, 16)
	var core: SimCore = state.sim_core
	var kernel_before := [
		core._a.duplicate(), core._h.duplicate(), core._rng._mt.duplicate(), core._rng._mti
	]
	var entry: Node = load("res://scenes/ui/clue_board_entry.tscn").instantiate()
	root.add_child(entry)
	entry.bind_sources(core, null, null)
	entry.record_observed_event({"kind": "chat", "i": 0, "j": 1}, {"day": 1, "global_tick": 1})
	entry.open()
	await process_frame
	check(entry.is_open() and paused, "打开推理板持有暂停")
	check(entry.get_node("Board").displayed_page().people == [0, 1], "真实入口只展示学生")
	entry.close()
	check(not paused, "关闭释放自己的暂停")
	paused = true
	entry.open()
	entry.close()
	check(paused, "不得释放其他窗口的暂停")
	paused = false
	check([core._a, core._h, core._rng._mt, core._rng._mti] == kernel_before, "推理板不得改变矩阵和随机流")
	# 16 人同日入图：检查布局不重叠，所有节点仍是场景原件。
	var board: Control = entry.get_node("Board")
	var native_count := board.get_node("Design/Graph/Cards").get_child_count()
	for index in range(15):
		entry.record_observed_event(
			{"kind": "chat", "i": index, "j": index + 1}, {"day": 2, "global_tick": 100 + index}
		)
	entry.open()
	entry.show_day(2)
	check(board.displayed_page().people.size() == 16, "全池学生可同日入图")
	var cards: Node = board.get_node("Design/Graph/Cards")
	for a in range(16):
		for b in range(a + 1, 16):
			check(
				not cards.get_child(a).get_rect().intersects(cards.get_child(b).get_rect()),
				"16 人卡片不能重叠"
			)
	check(cards.get_child_count() == native_count, "开关和翻页不得动态创建节点")
	var previous: Button = board.get_node("%PreviousDay")
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = previous.size / 2.0
	press.pressed = true
	previous.gui_input.emit(press)
	var release := press.duplicate() as InputEventScreenTouch
	release.pressed = false
	previous.gui_input.emit(release)
	check(int(board.displayed_page().day) == 1, "原生触摸翻一天，不重复触发")
	entry.close()
	# 无真实教室也可确认日末回调会打开、暂停并归档当前页。
	entry._on_report(2)
	check(entry.is_open() and paused, "日末自动打开推理板")
	check(board.displayed_page().sealed, "日末内容已归档")
	entry.close()
	entry.queue_free()
	await process_frame
	state.end_game()
	print("CLUE_BOARD: ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	call_deferred("quit", 0 if failures.is_empty() else 1)
