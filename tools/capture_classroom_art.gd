extends SceneTree
## 同种子、同镜头教室验收：实际入口场景，冻结模拟后截图并记录帧耗时。

const SCENE := "res://scenes/game/classroom3D.tscn"
const OUTPUT := "res://tools/out/classroom_art/"
const SEED := 20261011
const WARMUP_FRAMES := 90
const SAMPLE_SECONDS := 3.0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var label := "after"
	var npc_count := 16
	var art_enabled := true
	var clean := false
	var view := ""
	var right_preview := false
	var no_camera_follow := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
		elif argument.begins_with("--npc="):
			npc_count = int(argument.trim_prefix("--npc="))
		elif argument == "--no-art":
			art_enabled = false
		elif argument == "--clean":
			clean = true
		elif argument.begins_with("--view="):
			view = argument.trim_prefix("--view=")
		elif argument == "--camera-right-preview":
			right_preview = true
		elif argument == "--no-camera-follow":
			no_camera_follow = true
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.get_node("GameState").start_game(SEED, npc_count)
	var scene: Node = load(SCENE).instantiate()
	if scene.has_node("ClassroomArt"):
		scene.get_node("ClassroomArt").enabled = art_enabled
	scene.get_node("Roam").enabled = false
	root.add_child(scene)
	current_scene = scene
	if no_camera_follow and art_enabled:
		scene.get_node("ClassroomArt").set_camera_follow_enabled(false)
	# 场景绑定在首个 process_frame 后发生；冻结帧内核还未推进一个 tick。
	await process_frame
	scene.get_node("Clock").hold(&"classroom_art_capture")
	for frame in range(WARMUP_FRAMES):
		await process_frame
	scene.get_node("TransitionOverlay").force_hide()
	if right_preview:
		# Frozen presentation probe only: move the rendered actor to a safe stand marker.
		var player := scene.get_node("Player") as PlayerController
		player._player_actor.global_position = (
			scene.get_node("StandPoints/SIDE_RIGHT").global_position
		)
	await create_timer(2.0).timeout
	if clean:
		_hide_interface(scene)
	if not view.is_empty():
		if art_enabled:
			scene.get_node("ClassroomArt").set_camera_follow_enabled(false)
		var style: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/ui/classroom_art.json")
		)
		var views: Dictionary = style.get("capture_views", {})
		if not views.has(view):
			push_error("未知教室截图视角：" + view)
			quit(1)
			return
		var definition: Dictionary = views[view]
		var camera := scene.get_node("Camera3D") as Camera3D
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = float(definition["size"])
		camera.look_at_from_position(
			ClassroomArtProps.vector(definition["position"]),
			ClassroomArtProps.vector(definition["target"])
		)
		if bool(definition.get("hide_actors", false)):
			scene.get_node("Actors").visible = false
	var frame_times: Array[float] = []
	var measurement_start := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - measurement_start) / 1000000.0 < SAMPLE_SECONDS:
		var started := Time.get_ticks_usec()
		await process_frame
		frame_times.append(float(Time.get_ticks_usec() - started) / 1000.0)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT + label + ".png")
	frame_times.sort()
	var report := {
		"label": label,
		"engine": Engine.get_version_info().string,
		"seed": SEED,
		"npc_count": npc_count,
		"actors": scene.get_node("Actors").get_child_count(),
		"art_enabled": art_enabled,
		"clean": clean,
		"camera_right_preview": right_preview,
		"camera_follow_disabled": no_camera_follow,
		"samples": frame_times.size(),
		"frame_ms_mean": _mean(frame_times),
		"frame_ms_median": frame_times[frame_times.size() / 2],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"screenshot_error": error,
	}
	var file := FileAccess.open(OUTPUT + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(error)


func _hide_interface(scene: Node) -> void:
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for child in scene.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
		elif child is Control:
			(child as Control).visible = false
	for actor in scene.get_node("Actors").get_children():
		var tag := actor.get_node_or_null("NameTag") as Label3D
		if tag != null:
			tag.visible = false


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()
