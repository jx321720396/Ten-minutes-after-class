extends SceneTree
## 使用真实教室与生产圈层渲染；会话及站位只在截图实例注入。

const OUTPUT := "res://tools/out/activity_rings/"


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
	var positions := [
		Vector2(-0.4, 1.85),
		Vector2(0.4, 1.85),
		Vector2(0.0, 1.25),
		Vector2(-1.85, -0.3),
		Vector2(-1.85, 0.4),
		Vector2(-2.6, -3.5),
		Vector2(-1.9, -3.5),
		Vector2(-3.9, 1.6),
		Vector2(1.8, -3.5)
	]
	for index in range(positions.size()):
		var pos: Vector2 = positions[index]
		var actor: Node3D = scene.get_node("Actors").actor_for(index)
		actor.global_position = Vector3(pos.x, actor.global_position.y, pos.y)
		core.set_position(index, pos.x, pos.y)
	core._sessions.begin("chat", [0, 1, 2], 100)
	core._sessions.begin("chat", [3, 4], 100)
	core._sessions.begin("chat", [5, 6], 100)
	scene.get_node("Rings").refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var result := root.get_texture().get_image().save_png(OUTPUT + "classroom.png")
	print("activity rings screenshot: ", result)
	current_scene = null
	scene.queue_free()
	state.end_game()
	await process_frame
	quit(result)
