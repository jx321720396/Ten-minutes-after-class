extends SceneTree
## 独立截图实例；测试夹具只在此工具注入，不进入正式游戏。

const OUTPUT := "res://docs/art/concepts/risk_warning_20261016/"


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var state = root.get_node("GameState")
	state.start_game(20261016, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	for frame in range(30):
		await physics_frame
	var clock = room.get_node("Clock")
	clock.hold(&"risk_capture")
	room.get_node("OfficeHub").set_mode("monitor")
	room.get_node("TransitionOverlay").force_hide()
	room.get_node("TransitionOverlay").hide()
	var hud = room.get_node("TimeHUD")
	var card = hud.get_node("AttentionCard")
	hud._refresh(clock.snapshot())
	await _save("implemented_empty_1280.png")
	# 用真实内核登记事件并结算，绝不把预设示例填入生产快照。
	var core: SimCore = state.sim_core
	for source in range(3):
		core._h[source * core.node_count() + 5] = 60.0
	core._note_harm(0, 5, "aggression")
	for source in range(core.node_count()):
		if source != 6:
			core._a[source * core.node_count() + 6] = 10.0
	core._risk.register_join_reject(6)
	core._risk.register_join_reject(6)
	core._risk.settle_day(core, 1)
	core._stress[7] = 95.0
	core._check_breakdown()
	hud._refresh(clock.snapshot())
	await _save("implemented_warnings_1280.png")
	card._open_details("bully")
	await _save("implemented_details_1280.png")
	card.get_node("Details").hide()
	root.size = Vector2i(1920, 1080)
	await _save("implemented_warnings_1920.png")
	root.size = Vector2i(960, 540)
	card._open_details("all")
	await _save("implemented_details_960.png")
	room.queue_free()
	state.end_game()
	await process_frame
	print("RISK_ATTENTION_CAPTURE: PASS")
	quit()


func _save(filename: String) -> void:
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + filename) == OK)
