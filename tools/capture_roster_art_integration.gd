extends SceneTree
## 仅用于验证真实场景显示；活动赋值为截图夹具，不保存游戏。

const OUTPUT := "res://docs/art/concepts/roster_art_integration_20261015/"


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var state = root.get_node("GameState")
	state.start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	for frame in range(60):
		await physics_frame
	room.get_node("Clock").hold(&"capture_roster")
	room.get_node("TransitionOverlay").force_hide()
	room.get_node("OfficeHub").set_mode("monitor")
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	var actors = room.get_node("Actors")
	var core = state.sim_core
	for index in actors._seated_poses:
		var actor = actors.actor_for(index)
		actor.global_position = actors._stand_position(actors.seat_node_of(index))
		core._current_act[index] = "study"
	actors._process(0.0)
	await _save("classroom_learning.png")
	for index in actors._seated_poses:
		core._current_act[index] = "chat"
	actors._process(0.0)
	await _save("classroom_standing.png")
	var profile = room.get_node("UI/NpcProfile")
	profile.open_profile(actors._seated_poses.keys()[1])
	await _save("profile_1280.png")
	profile.close()
	var entry = room.get_node("UI/ClueBoardEntry")
	var students: Array = actors._seated_poses.keys()
	for index in range(students.size() - 1):
		entry.record_observed_event(
			{"kind": "chat", "i": students[index], "j": students[index + 1]},
			{"day": 1, "global_tick": index + 1}
		)
	entry.open()
	await _save("clue_board_1280.png")
	entry.close()
	print("Roster integration screenshots captured")
	quit(0)


func _save(filename: String) -> void:
	current_scene.get_node("TransitionOverlay").force_hide()
	current_scene.get_node("TransitionOverlay").hide()
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + filename) == OK)
