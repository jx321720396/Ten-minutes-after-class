extends SceneTree
## 图稿验收工具：真实教室底图，示例提交包仅用于截图，不修改或保存内核。


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1920, 1080)
	root.get_node("GameState").start_game(20261011, 16)
	var scene: Node = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in range(10):
		await process_frame
	await create_timer(0.6).timeout
	scene.get_node("TransitionOverlay").force_hide()
	var hud: ChatFeedbackHUD = scene.get_node("ChatHUD")
	var clock: SimulationClock = scene.get_node("Clock")
	clock.hold(&"pen_screenshot_fixture")
	hud.present_locked_result({"mode": "join", "request_id": 4242, "accepted": true, "p_belief": 0.72})
	await _save("ready")
	hud.get_node("PenCard/Column/PenButton").pressed.emit()
	await create_timer(0.18).timeout
	await _save("spinning")
	hud.get_node("PenCard/Column/PenButton").pressed.emit()
	await create_timer(0.4).timeout
	await _save("result")
	hud.clear()
	clock.release(&"pen_screenshot_fixture")
	quit()


func _save(state: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tools/out")
	var path := "res://tools/out/pen-check-%s.png" % state
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
