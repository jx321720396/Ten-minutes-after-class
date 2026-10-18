extends SceneTree
## 独立截图夹具：真实会话 + 生产朝向组件，不改变正式存档。

const OUTPUT := "res://tools/out/group_facing/"


func _initialize() -> void:
	call_deferred("_capture")


func _save(filename: String) -> void:
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var result := root.get_texture().get_image().save_png(OUTPUT + filename)
	assert(result == OK)
	print("group facing screenshot: ", filename)


func _capture() -> void:
	if OS.get_cmdline_user_args().has("catalog"):
		await _catalog()
		quit()
		return
	root.size = Vector2i(1280, 720)
	var state: Variant = root.get_node("GameState")
	state.start_game(20261018, 16)
	var room: Node3D = load("res://scenes/game/classroom3D.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	for frame in range(180):
		if room.has_node("GroupFacing"):
			break
		await process_frame
	assert(room.has_node("GroupFacing"))
	room.get_node("TransitionOverlay").force_hide()
	room.get_node("TransitionOverlay").visible = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var core: SimCore = state.sim_core
	core._sessions.clear()
	var actors: Node3D = room.get_node("Actors")
	var positions := [Vector2(2.4, 4.3), Vector2(2.4, 3.1), Vector2(-1.9, 3.7), Vector2(-2.7, 3.7)]
	for index in range(positions.size()):
		var actor: Node3D = actors.actor_for(index)
		actor.get_node("Walker").stop()
		actors._seated_poses[index].hide()
		actor.get_node("Sprite").show()
		actor.global_position = Vector3(
			positions[index].x, actor.global_position.y, positions[index].y
		)
		core.set_position(index, positions[index].x, positions[index].y)
	core._sessions.begin("chat", [0, 1], 100)
	core._sessions.begin("chat", [2, 3], 100)
	var facing: Node = room.get_node("GroupFacing")
	assert(facing._sprites.size() == 16, "全班背影必须加载")
	var entry: Dictionary = facing._sprites[0]
	var front_foot: float = (
		entry["front_y"]
		+ (
			(
				entry["front"].get_height() * 0.5
				- float(
					(
						actors
						. _pose_settings["bindings"][actors.actor_for(0).get_meta(
							"appearance_sprite"
						)]["standing_floor_pixel"]
					)
				)
			)
			* entry["front_pixel_size"]
		)
	)
	facing.refresh()
	assert(facing._back.has(0), "前方学生必须转背")
	assert(not facing._back.has(1), "后方学生必须保持正面")
	assert(not facing._back.has(2) and not facing._back.has(3), "横排不转背")
	var binding: Dictionary = actors._pose_settings["bindings"][actors.actor_for(0).get_meta(
		"appearance_sprite"
	)]
	var back_foot: float = (
		entry["back_y"]
		+ (
			(entry["back"].get_height() * 0.5 - float(binding["back_floor_pixel"]))
			* entry["back_pixel_size"]
		)
	)
	assert(is_equal_approx(front_foot, back_foot), "转身脚底不漂移")
	room.get_node("Rings").refresh()
	await _save("classroom_active.png")
	# 坐姿同伴保留为目标；只替换站立请教者的背影。
	var front_actor: Node3D = actors.actor_for(0)
	var old_position := front_actor.global_position
	var seated_position: Vector3 = actors.sit_position_of(1)
	front_actor.global_position = seated_position + Vector3(0, 0, 1.2)
	actors.actor_for(1).get_node("Sprite").hide()
	actors._seated_poses[1].show()
	facing.refresh()
	assert(facing._back.has(0), "站立者必须朝向坐姿同伴")
	assert(not facing._back.has(1), "坐姿不替换为站立背影")
	front_actor.get_node("Walker")._moving = true
	facing.refresh()
	assert(not facing._back.has(0), "移动时保持行走表现")
	front_actor.get_node("Walker")._moving = false
	front_actor.global_position = old_position
	actors.actor_for(1).get_node("Sprite").show()
	actors._seated_poses[1].hide()
	core._sessions.clear()
	facing.refresh()
	assert(facing._back.is_empty(), "结束恢复正面")
	assert(actors.actor_for(0).get_node("Sprite").texture == facing._sprites[0]["front"])
	room.get_node("Rings").refresh()
	await _save("classroom_ended.png")
	current_scene = null
	room.queue_free()
	state.end_game()
	await process_frame
	quit()


func _catalog() -> void:
	root.size = Vector2i(1920, 1080)
	var canvas := Control.new()
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("e9e3d5")
	background.size = Vector2(root.size)
	canvas.add_child(background)
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var index := 0
	for key in settings["bindings"]:
		var origin := Vector2((index % 4) * 480, (index / 4) * 270)
		var image := TextureRect.new()
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var binding_key := (
			"idle_back" if OS.get_cmdline_user_args().has("seated_catalog") else "standing_back"
		)
		image.texture = load(str(settings["bindings"][key][binding_key]))
		image.position = origin + Vector2(5, 30)
		image.size = Vector2(470, 238)
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		canvas.add_child(image)
		var label := Label.new()
		label.text = "%02d  %s" % [index + 1, key]
		label.position = origin + Vector2(15, 0)
		label.add_theme_color_override("font_color", Color("303747"))
		canvas.add_child(label)
		index += 1
	await _save(
		(
			"all_16_seated_backs.png"
			if OS.get_cmdline_user_args().has("seated_catalog")
			else "all_16_backs.png"
		)
	)
	canvas.queue_free()
	await process_frame
