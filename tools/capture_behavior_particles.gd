extends SceneTree
## 实际教室渲染验收；仅在本次截图实例注入六类公开状态，不改变游戏规则。

const OUTPUT := "res://tools/out/behavior_particles/"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1920, 1080)
	var state: Variant = root.get_node("GameState")
	state.start_game(20261007, 16)
	var scene: Node3D = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in range(180):
		if scene.get_node("Interaction")._core != null:
			break
		await physics_frame
	scene.get_node("TransitionOverlay").bind_clock(null)
	scene.get_node("TransitionOverlay").force_hide()
	scene.get_node("TransitionOverlay").visible = false
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var core: SimCore = state.sim_core
	core._sessions.clear()
	for i in range(core.node_count()):
		core._current_act[i] = ""
	var kinds := ["study", "listen_music", "eat_snack", "read_book", "comfort"]
	for i in range(kinds.size()):
		core._current_act[i] = kinds[i]
	core._sessions.begin("chat", [5, 6], core.global_tick() + 30)
	core._current_act[7] = "comfort"
	core._current_act[8] = "study"
	var bubbles: ChatActivityBubble = scene.get_node("ChatBubble")
	bubbles.bind_clock(null)
	bubbles.bind_time_flow(null)
	for step in range(25):
		bubbles._process(0.1)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var result := root.get_texture().get_image().save_png(OUTPUT + "classroom.png")
	print("behavior particles screenshot: ", result)
	current_scene = null
	scene.queue_free()
	state.end_game()
	await process_frame
	quit(result)
