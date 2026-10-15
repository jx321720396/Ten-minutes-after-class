extends SceneTree

const OUTPUT := "res://docs/art/concepts/roster_art_integration_20261015/"

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var settings = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/student_poses.json"))
	var rows = JSON.parse_string(FileAccess.get_file_as_string("res://assets/textures/characters/study_front_v1/manifest.json"))
	var gallery := SubViewport.new()
	gallery.size = Vector2i(1600, 2040)
	gallery.disable_3d = true
	gallery.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(gallery)
	var bg := ColorRect.new()
	bg.color = Color("e9e5dc")
	bg.size = Vector2(gallery.size)
	gallery.add_child(bg)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "sans-serif"])
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(390, 460)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var sample = load("res://scenes/game/school_student_sample_showroom.tscn").instantiate()
		viewport.add_child(sample)
		sample.get_node("Sample").hide()
		sample.get_node("Student").hide()
		var desk = sample.get_node("Original")
		desk.show()
		desk.position = Vector3.ZERO
		var camera = sample.get_node("Camera3D")
		camera.size = 1.75
		camera.look_at_from_position(Vector3(0, 1.58, 3.6), Vector3(0, 0.76, -0.2))
		sample.get_node("WindowKey").light_energy = 0.45
		sample.get_node("SoftFill").light_energy = 0.15
		var environment = sample.get_node("@WorldEnvironment@2")
		environment.environment = environment.environment.duplicate()
		environment.environment.ambient_light_energy = 0.25
		var pose = load("res://scenes/components/layered_student_pose.tscn").instantiate()
		sample.add_child(pose)
		pose.configure(settings, settings.bindings[row.sprite])
		pose.show_pose("study")
		var picture := TextureRect.new()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.texture = viewport.get_texture()
		picture.position = Vector2(10 + index % 4 * 400, 10 + floori(index / 4.0) * 505)
		picture.size = Vector2(390, 460)
		gallery.add_child(picture)
		var label := Label.new()
		label.text = "%s  %s" % [row.id, row.name]
		label.position = picture.position + Vector2(0, 462)
		label.size = Vector2(390, 32)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 25)
		label.add_theme_color_override("font_color", Color("263b4a"))
		gallery.add_child(label)
	for frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	assert(gallery.get_texture().get_image().save_png(OUTPUT + "study_desks_all_16.png") == OK)
	print("Captured all 16 calibrated desk contacts")
	quit(0)
