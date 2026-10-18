extends SceneTree
## 独立验收进程：活动夹具不写入玩家存档。

const OUTPUT := "res://docs/art/concepts/snack_seated_20261018/"
var failures := 0
var activity := "eat_snack"
var output := OUTPUT
var image_prefix := "classroom_snack_"


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--music"):
		activity = "listen_music"
		output = "res://docs/art/concepts/music_seated_20261018/"
		image_prefix = "classroom_music_"
	elif OS.get_cmdline_user_args().has("--reading"):
		activity = "read_book"
		output = "res://docs/art/concepts/reading_seated_20261018/"
		image_prefix = "classroom_reading_"
	elif OS.get_cmdline_user_args().has("--chat"):
		activity = "chat"
		output = "res://docs/art/concepts/chat_seated_20261018/"
		image_prefix = "classroom_chat_"
	elif OS.get_cmdline_user_args().has("--sleep"):
		activity = "sleep"
		output = "res://docs/art/concepts/sleep_seated_20261018/"
		image_prefix = "classroom_sleep_"
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var state := root.get_node("GameState")
	state.start_game(20261018, 16)
	state.tutorial_pending = false
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	for frame in range(240):
		if room.has_node("OfficeHub"):
			break
		await physics_frame
	room.get_node("Clock").hold(&"snack_capture")
	room.get_node("OfficeHub").set_mode("classroom")
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	room.get_node("TransitionOverlay").force_hide()
	var core = state.sim_core
	var actors = room.get_node("Actors")
	for index in core.node_count():
		core._current_act[index] = activity
		actors.actor_for(index).global_position = actors._stand_position(actors.seat_node_of(index))
	var rng_state := var_to_bytes([core._rng._mt, core._rng._mti])
	var grades := var_to_bytes(core._grade)
	for index in core.node_count():
		var pose = actors._seated_poses[index]
		pose.show_pose(activity, false)
	actors._process(0.0)
	for frame in range(15):
		await process_frame
	for index in core.node_count():
		var pose = actors._seated_poses[index]
		check(pose._pose == activity, "学生 %d 使用独立 %s 坐姿" % [index, activity])
		check(not actors.actor_for(index).get_node("Sprite").visible, "活动坐姿不叠加站姿")
	check(rng_state == var_to_bytes([core._rng._mt, core._rng._mti]), "切换不消耗内核随机数")
	check(grades == var_to_bytes(core._grade), "切换不改变成绩")
	for viewport_size in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = viewport_size
		for frame in range(6):
			await process_frame
		await RenderingServer.frame_post_draw
		var path := output + image_prefix + "%d.png" % viewport_size.x
		check(root.get_texture().get_image().save_png(path) == OK, "保存实机场景截图")
	print("SEATED_ACTIVITY: ", activity, " failures=", failures)
	quit(0 if failures == 0 else 1)
