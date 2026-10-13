extends GutTest
## 新手教程 P0 回归（docs/gdd/v4/28-新手教程设计.md）：
## 开场卡 → 五步提示（条件 / 超时 / 课间结束收尾）→ 完成与跳过写「已看」标记。
## 覆盖层测试用临时标记文件，不碰开发者真档（user://tutorial_seen.dat）；
## 教室级用例验证「默认无教程、入口置位才弹」。

const OVERLAY = preload("res://scenes/ui/tutorial_overlay.tscn")
const SETTINGS = preload("res://scenes/ui/settings_menu.tscn")
const ROOM := "res://scenes/game/classroom3D.tscn"
const ROOM_SEED := 20261013

var _seen_tmp := "user://test_tutorial_seen_tmp.dat"


func before_each() -> void:
	_cleanup_seen()
	get_node("/root/GameState").start_game(ROOM_SEED, 16)


func after_each() -> void:
	get_node("/root/GameState").tutorial_pending = false
	get_node("/root/GameState").end_game()
	_cleanup_seen()


func _cleanup_seen() -> void:
	if FileAccess.file_exists(_seen_tmp):
		DirAccess.remove_absolute(_seen_tmp)


func _overlay() -> TutorialOverlay:
	var d: TutorialOverlay = OVERLAY.instantiate()
	d.seen_path = _seen_tmp
	add_child_autofree(d)
	return d


func _hint_text(d: TutorialOverlay) -> String:
	return d._hint_label.text


## 正常走完开场卡（发 intro_closed、时钟语义与真实流程一致），停在 S1。
func _close_intro(d: TutorialOverlay) -> void:
	for _i in range(d._cfg.intro_cards.size()):
		d._next_btn.pressed.emit()


# ------------------------------------------------------------------ 配置

func test_config_loads_with_three_cards_and_five_steps() -> void:
	var d := _overlay()
	assert_eq(d._cfg.get("intro_cards", []).size(), 3, "开场卡 3 张")
	assert_eq(d._cfg.get("steps", []).size(), 5, "首课间 5 步")
	for card in d._cfg.get("intro_cards", []):
		assert_false(str(card.get("text", "")).is_empty(), "每张卡有文案")
	for step in d._cfg.get("steps", []):
		assert_false(str(step.get("text", "")).is_empty(), "每步有文案")


# ------------------------------------------------------------------ 开场卡 → 步进

func test_intro_cards_advance_then_first_step_shows() -> void:
	var d := _overlay()
	d.bind_world(null, null, {})
	watch_signals(d)
	d.start_first_run()
	assert_true(d.visible, "教程开始即可见")
	assert_true(d.is_intro_open(), "开场卡打开")
	d._next_btn.pressed.emit()
	d._next_btn.pressed.emit()
	assert_true(d.is_intro_open(), "前两张卡只是翻页")
	d._next_btn.pressed.emit()
	assert_signal_emitted(d, "intro_closed", "最后一张卡关闭开场")
	assert_false(d.is_intro_open(), "开场卡收起")
	assert_true(d._hint_bar.visible, "进入步进提示")
	assert_eq(_hint_text(d), str(d._cfg.steps[0].text), "S1 文案来自配置")
	assert_true(FileAccess.file_exists(_seen_tmp) == false, "步进未完成不写已看")


func test_s1_autopass_advances_by_time() -> void:
	var d := _overlay()
	d.bind_world(null, null, {})
	d.start_first_run()
	d._next_btn.pressed.emit()
	d._next_btn.pressed.emit()
	d._next_btn.pressed.emit()
	await wait_seconds(3.4)
	assert_eq(_hint_text(d), str(d._cfg.steps[1].text), "S1 到点自动放行进 S2")


func test_s2_move_completes_by_player_displacement() -> void:
	var d := _overlay()
	var player := Node3D.new()
	add_child_autofree(player)
	d.bind_world(null, player, {})
	d.start_first_run()
	_close_intro(d)
	d._advance()  # S1 → S2
	assert_true(d._tracking_move, "S2 开始记录玩家位移")
	player.global_position = player.global_position + Vector3(3.0, 0.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_hint_text(d), str(d._cfg.steps[2].text), "位移够远即完成 S2 进 S3")


func test_s3_armed_then_s4_chat_commit_chain() -> void:
	var d := _overlay()
	d.bind_world(null, null, {})
	d.start_first_run()
	_close_intro(d)
	d._advance()
	d._advance()  # S1 → S2 → S3
	d.notify_armed(&"chat")
	assert_eq(_hint_text(d), str(d._cfg.steps[3].text), "任意行为被选中即完成 S3")
	d.notify_committed(&"study")
	assert_eq(_hint_text(d), str(d._cfg.steps[3].text), "非等待行为不推进 S4")
	d.notify_committed(&"chat")
	assert_eq(_hint_text(d), str(d._cfg.steps[4].text), "闲聊提交（含被拒口径）完成 S4")


func test_observe_commit_finishes_and_marks_seen() -> void:
	var d := _overlay()
	d.bind_world(null, null, {})
	d.start_first_run()
	_close_intro(d)
	for _i in range(4):
		d._advance()  # S1 → S2 → S3 → S4 → S5
	watch_signals(d)
	d.notify_committed(&"observe")
	assert_false(d.is_running(), "S5 完成即收尾")
	assert_signal_emitted(d, "tutorial_finished")
	assert_true(FileAccess.file_exists(_seen_tmp), "完成写已看标记")


func test_skip_during_intro_releases_and_marks_seen() -> void:
	var d := _overlay()
	d.bind_world(null, null, {})
	watch_signals(d)
	d.start_first_run()
	d.skip()
	assert_false(d.is_running(), "跳过即结束")
	assert_signal_emitted(d, "intro_closed", "开场卡期间跳过也要通知释放时钟")
	assert_signal_emitted(d, "tutorial_finished")
	assert_true(FileAccess.file_exists(_seen_tmp), "跳过写已看标记")
	assert_false(d._hint_bar.visible, "提示条收起")


# ------------------------------------------------------------------ 教室接线

func _open_room() -> Node3D:
	var room: Node3D = load(ROOM).instantiate()
	room.get_node("Roam").enabled = false
	add_child_autofree(room)
	# classroom._ready 内有多个 await（等帧、等导航、绑完教程在最后），多等几帧确保接完线
	for _i in range(24):
		await get_tree().process_frame
	return room


func test_classroom_without_pending_has_no_tutorial_and_no_freeze() -> void:
	var room := await _open_room()
	var clock: SimulationClock = room.get_node("Clock")
	var d: TutorialOverlay = room.get_node("TutorialOverlay")
	assert_false(d.is_running(), "入口没置位：不弹教程")
	assert_false(d.visible, "覆盖层不可见")
	assert_false(clock.is_held_by(&"tutorial"), "世界不被教程冻结（转场等其他 hold 不在断言内）")


func test_classroom_with_pending_shows_intro_and_freezes_until_skip() -> void:
	get_node("/root/GameState").tutorial_pending = true
	var room := await _open_room()
	var clock: SimulationClock = room.get_node("Clock")
	var d: TutorialOverlay = room.get_node("TutorialOverlay")
	d.seen_path = _seen_tmp  # 教室里的实例也要换临时标记，否则 skip 会污染开发者真档
	assert_true(d.is_running(), "入口置位：教程弹开场卡")
	assert_true(d.is_intro_open(), "开场卡打开")
	assert_true(clock.is_held_by(&"tutorial"), "开场卡期间教程持着冻结")
	d.skip()
	await get_tree().process_frame
	assert_false(clock.is_held_by(&"tutorial"), "跳过后教程释放冻结，世界开跑")
	assert_false(d.is_running(), "教程收尾")
	assert_true(FileAccess.file_exists(_seen_tmp), "已看标记写到临时路径，不碰真档")


func test_classroom_intro_close_enters_s1_with_highlight() -> void:
	# 回归 CanvasLayer 类型错误：教室绑的是 time_hud._panel / action_bar._panel（Control），
	# 关卡进 S1 后高亮要真的画出来，且不报「CanvasLayer → Control」类型错。
	get_node("/root/GameState").tutorial_pending = true
	var room := await _open_room()
	var clock: SimulationClock = room.get_node("Clock")
	var d: TutorialOverlay = room.get_node("TutorialOverlay")
	d.seen_path = _seen_tmp
	for _i in range(3):
		d._next_btn.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(clock.is_held_by(&"tutorial"), "开场卡关闭即释放时钟")
	assert_true(d._hint_bar.visible, "进入 S1 提示")
	assert_true(d._highlight.visible, "S1 高亮时间卡面板")


# ------------------------------------------------------------------ 设置入口

func test_settings_menu_emits_replay_request() -> void:
	var menu: Control = SETTINGS.instantiate()
	add_child_autofree(menu)
	watch_signals(menu)
	(menu.get_node("Overlay/CenterContainer/Panel/VBox/ReplayBtn") as Button).pressed.emit()
	assert_signal_emitted(menu, "replay_requested", "重看按钮发 replay_requested")
	assert_signal_emitted(menu, "closed", "点击后面板关闭")


# ------------------------------------------------------------------ 锚点高亮

func _goto_step(d: TutorialOverlay, index: int) -> void:
	_close_intro(d)
	for _i in range(index):
		d._advance()


func test_anchor_with_canvas_layer_does_not_crash_and_hides_highlight() -> void:
	# 回归：TimeHUD / 行为栏本体是 CanvasLayer，曾被直接当 Control 用导致运行时报错
	var d := _overlay()
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	d.bind_world(null, null, {"time_hud": layer})
	d.start_first_run()
	_goto_step(d, 0)
	await get_tree().process_frame
	assert_false(d._highlight.visible, "锚点非 Control：不画高亮也不报错")


func test_anchor_with_control_positions_highlight() -> void:
	var d := _overlay()
	var panel := PanelContainer.new()
	add_child_autofree(panel)
	d.bind_world(null, null, {"time_hud": panel})
	d.start_first_run()
	_goto_step(d, 0)
	await get_tree().process_frame
	assert_true(d._highlight.visible, "Control 锚点画高亮")
	assert_true(d._highlight.size.x >= panel.size.x, "高亮框罩住目标")


# ------------------------------------------------------------------ 「下一步」按钮

func test_every_step_has_manual_next_button_and_clicking_through_finishes() -> void:
	var d := _overlay()
	d.bind_world(null, null, {})
	d.start_first_run()
	_close_intro(d)
	watch_signals(d)
	for i in range(d._cfg.steps.size()):
		assert_true(d._hint_next_btn.visible, "第 %d 步有「下一步」按钮" % (i + 1))
		assert_eq(_hint_text(d), str(d._cfg.steps[i].text))
		d._hint_next_btn.pressed.emit()
	assert_false(d.is_running(), "最后一步点下一步即收尾")
	assert_signal_emitted(d, "tutorial_finished")
	assert_true(FileAccess.file_exists(_seen_tmp), "点完写已看标记")


func test_hint_bar_lets_world_clicks_through_but_button_catches() -> void:
	# 条身不拦截鼠标（不挡地面点击 / 行为栏），只有按钮自己接输入
	var d := _overlay()
	d.bind_world(null, null, {})
	d.start_first_run()
	_close_intro(d)
	assert_eq(d._hint_bar.mouse_filter, Control.MOUSE_FILTER_IGNORE, "提示条不挡点击")
	assert_eq(d._hint_next_btn.mouse_filter, Control.MOUSE_FILTER_STOP, "按钮接点击")
	assert_true(d._hint_next_btn.custom_minimum_size.y >= 44.0, "热区 ≥44（§20.0.4）")
