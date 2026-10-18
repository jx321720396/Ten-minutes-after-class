extends SceneTree

const OUTPUT := "res://docs/art/concepts/identity_roster_20261016/"


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	var rows: Array = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/textures/characters/identity_v3/manifest.json")
	)
	var gallery := SubViewport.new()
	gallery.size = Vector2i(1600, 2320)
	gallery.disable_3d = true
	gallery.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(gallery)
	var bg := ColorRect.new()
	bg.color = Color("eae8df")
	bg.size = Vector2(gallery.size)
	gallery.add_child(bg)
	for index in range(rows.size()):
		var picture := TextureRect.new()
		picture.texture = load(str(rows[index].reference))
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.position = Vector2(index % 4 * 400 + 10, floori(index / 4.0) * 580 + 10)
		picture.size = Vector2(380, 530)
		gallery.add_child(picture)
		var label := Label.new()
		label.text = "%s  %s" % [rows[index].id, rows[index].name]
		label.position = picture.position + Vector2(0, 535)
		label.size = Vector2(380, 35)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 25)
		label.add_theme_color_override("font_color", Color("293f45"))
		gallery.add_child(label)
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(
		gallery.get_texture().get_image().save_png(OUTPUT + "all_16_distinct_standing.png") == OK
	)
	gallery.queue_free()
	await process_frame
	await _capture_heads(rows)
	await _classroom_capture()
	print("STANDING_ROSTER: PASS gallery and actual classroom/profile/board captures")
	quit(0)


func _classroom_capture() -> void:
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
	room.get_node("Clock").hold(&"capture_standing_roster")
	room.get_node("OfficeHub").set_mode("monitor")
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	room.get_node("TransitionOverlay").force_hide()
	room.get_node("TransitionOverlay").hide()
	var actors = room.get_node("Actors")
	for index in actors._seated_poses:
		actors.actor_for(index).global_position = actors._stand_position(actors.seat_node_of(index))
		state.sim_core._current_act[index] = "study"
	actors._process(0.0)
	await _save("classroom_distinct_study.png")
	await _capture_desks(actors)
	for index in actors._seated_poses:
		state.sim_core._current_act[index] = "chat"
	actors._process(0.0)
	await _save("classroom_distinct_standing.png")
	var profile = room.get_node("UI/NpcProfile")
	profile.open_profile(actors._seated_poses.keys()[0])
	await _save("profile_natural_standing.png")
	profile.close()


func _save(filename: String) -> void:
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + filename) == OK)


func _capture_heads(rows: Array) -> void:
	var gallery := SubViewport.new()
	gallery.size = Vector2i(1600, 1600)
	gallery.disable_3d = true
	gallery.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(gallery)
	var bg := ColorRect.new()
	bg.color = Color("eae8df")
	bg.size = Vector2(gallery.size)
	gallery.add_child(bg)
	for index in range(rows.size()):
		var face := AtlasTexture.new()
		face.atlas = load(str(rows[index].reference))
		face.region = Rect2(190, 0, 644, 440)
		var picture := TextureRect.new()
		picture.texture = face
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.position = Vector2(index % 4 * 400 + 10, floori(index / 4.0) * 400 + 10)
		picture.size = Vector2(380, 335)
		gallery.add_child(picture)
		var label := Label.new()
		label.text = "%s  %s" % [rows[index].id, rows[index].name]
		label.position = picture.position + Vector2(0, 340)
		label.size = Vector2(380, 40)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 27)
		label.add_theme_color_override("font_color", Color("293f45"))
		gallery.add_child(label)
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(gallery.get_texture().get_image().save_png(OUTPUT + "identity_heads.png") == OK)
	gallery.queue_free()
	await process_frame


func _capture_desks(actors: Node) -> void:
	var gallery := SubViewport.new()
	gallery.size = Vector2i(1600, 2040)
	gallery.disable_3d = true
	gallery.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(gallery)
	var bg := ColorRect.new()
	bg.color = Color("eae8df")
	bg.size = Vector2(gallery.size)
	gallery.add_child(bg)
	var views: Array[SubViewport] = []
	var core = actors.current_core()
	for index in actors._seated_poses:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(390, 460)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		views.append(viewport)
		var sample = load("res://scenes/game/school_student_sample_showroom.tscn").instantiate()
		viewport.add_child(sample)
		for path in ["Student", "Sample", "Original"]:
			sample.get_node(path).hide()
		var desk = actors.seat_node_of(index).duplicate()
		sample.add_child(desk)
		desk.transform = Transform3D.IDENTITY
		var camera = sample.get_node("Camera3D")
		camera.size = 1.8
		camera.look_at_from_position(Vector3(0, 1.58, 3.6), Vector3(0, .76, -.2))
		var pose = load("res://scenes/components/layered_student_pose.tscn").instantiate()
		sample.add_child(pose)
		pose.configure(actors._pose_settings, actors._seated_poses[index]._binding)
		pose.show_pose("study")
		var number := int(core.character_id(index)) - 1
		var picture := TextureRect.new()
		picture.texture = viewport.get_texture()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.position = Vector2(number % 4 * 400 + 5, floori(number / 4.0) * 505 + 5)
		picture.size = Vector2(390, 460)
		gallery.add_child(picture)
		var label := Label.new()
		label.text = "%02d  %s" % [number + 1, core.alias(index)]
		label.position = picture.position + Vector2(0, 462)
		label.size = Vector2(390, 35)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 25)
		label.add_theme_color_override("font_color", Color("293f45"))
		gallery.add_child(label)
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(gallery.get_texture().get_image().save_png(OUTPUT + "study_desk_contacts.png") == OK)
	gallery.queue_free()
	for viewport in views:
		viewport.queue_free()
	await process_frame
