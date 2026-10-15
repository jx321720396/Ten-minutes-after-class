extends SceneTree
## 只用于验收截图；夹具不进入游戏入口、不写入存档。


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var state: Node = root.get_node("GameState")
	state.start_game(20261014, 16)
	var room: Node = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	for frame in range(240):
		if room.has_node("OfficeHub"):
			break
		await physics_frame
	room.get_node("TransitionOverlay").force_hide()
	await create_timer(0.5).timeout
	var entry: Node = room.get_node("UI/ClueBoardEntry")
	var model: RefCounted = load("res://scripts/ui/npc_profile_data.gd").new()
	model.state = state.profile_notebook
	for pair in [[0, 1], [0, 2], [1, 2], [3, 4]]:
		entry.record_observed_event(
			{"kind": "chat", "i": pair[0], "j": pair[1]},
			{"day": 1, "phase_id": "lunch_break", "global_tick": 30 + pair[1]}
		)
	entry.record_observed_event(
		{"kind": "comfort", "i": 2, "j": 3},
		{"day": 1, "phase_id": "afternoon_break", "global_tick": 100}
	)
	model.mark(1, 4, "hostility", "band_high", {"day": 1, "phase_id": "lunch_break"})
	var dense := OS.get_cmdline_user_args().has("--dense")
	if dense:
		for index in range(15):
			entry.record_observed_event(
				{"kind": "chat", "i": index, "j": index + 1},
				{"day": 1, "phase_id": "lunch_break", "global_tick": 200 + index}
			)
	entry.open()
	entry.get_node("Board")._select_event(4)
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://docs/art/concepts/teacher_clue_board_20261014/"
	DirAccess.make_dir_recursive_absolute(directory)
	get_root().get_texture().get_image().save_png(
		directory + ("clue_board_dense_1080.png" if dense else "clue_board_1080.png")
	)
	get_root().size = Vector2i(1280, 720)
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(
		directory + ("clue_board_dense_720.png" if dense else "clue_board_720.png")
	)
	entry.close()
	room.queue_free()
	await process_frame
	state.end_game()
	quit()
