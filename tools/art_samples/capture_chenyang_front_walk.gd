extends SceneTree

const OUTPUT := "res://docs/art/concepts/chenyang_front_walk_20261015/"
const FRAMES := "res://tools/out/chenyang_front_walk_frames/"
const RIG := preload("res://tools/art_samples/chenyang_front_walk.gd")


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(800, 800)
	var world = load("res://scenes/game/school_student_sample_showroom.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for path in ["Student", "Sample", "Original"]:
		world.get_node(path).hide()
	var floor_material := ShaderMaterial.new()
	floor_material.shader = load("res://tools/art_samples/walk_sample_floor.gdshader")
	world.get_node("Ground").material_override = floor_material
	var rig := RIG.new()
	world.add_child(rig)
	var shadows: Array[MeshInstance3D] = []
	for side_index in range(2):
		var shadow := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(rig.gait.shadow_size[0], rig.gait.shadow_size[1])
		shadow.mesh = quad
		shadow.rotation.x = -PI / 2.0
		var material := ShaderMaterial.new()
		material.shader = load("res://tools/art_samples/walk_contact_shadow.gdshader")
		shadow.material_override = material
		world.add_child(shadow)
		shadows.append(shadow)
	floor_material.set_shader_parameter("tile_size", rig.gait.floor_tile)
	var camera: Camera3D = world.get_node("Camera3D")
	camera.size = 2.15
	var label := Label.new()
	label.text = "陈阳 · 正面行走小样"
	label.position = Vector2(0, 24)
	label.size = Vector2(800, 45)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", Color("29444a"))
	world.add_child(label)
	var fps: int = rig.gait.capture_fps
	var frames: int = roundi(rig.gait.period * fps * rig.gait.capture_cycles)
	DirAccess.make_dir_recursive_absolute(FRAMES)
	var previous: Dictionary = {}
	for frame in range(frames):
		var time := float(frame) / fps
		rig.set_sample_pose("walk", time)
		rig.position.z = rig.travel_at(time)
		camera.look_at_from_position(
			Vector3(0, 2.05, 4.8 + rig.position.z), Vector3(0, .86, rig.position.z)
		)
		for side_index in range(2):
			var side: float = [-1.0, 1.0][side_index]
			var foot := rig.foot_at(side, time)
			var ground: float = rig.position.z + foot.x
			shadows[side_index].position = Vector3(rig.gait.shadow_x[side_index], .002, ground)
			shadows[side_index].material_override.set_shader_parameter(
				"strength", rig.gait.shadow_strength * (1.0 - foot.y / (rig.gait.foot_lift * 1.5))
			)
			if previous.has(side) and foot.y == 0.0 and previous[side].y == 0.0:
				assert(absf(ground - previous[side].x) < rig.gait.foot_plant_tolerance)
			previous[side] = Vector2(ground, foot.y)
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		assert(picture.save_png(FRAMES + "%03d.png" % frame) == OK)
		if frame in [0, 8, 15, 23]:
			assert(picture.save_png(OUTPUT + "walk_%02d.png" % frame) == OK)
	print(
		"FRONT_WALK: PASS %d frames; planted feet stable; continuous triangles; no flips" % frames
	)
	quit(0)
