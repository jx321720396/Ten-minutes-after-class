extends SceneTree
## Real classroom and existing gameplay camera. No production actor replacement.

const OUTPUT := "res://docs/art/concepts/chenyang_classroom_walk_20261015/"
const FRAMES := "res://tools/out/chenyang_classroom_walk_frames/"
const RIG := preload("res://tools/art_samples/chenyang_front_walk.gd")


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/samples/chenyang_classroom_walk.json")
	)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(config.viewport[0], config.viewport[1])
	var state = root.get_node("GameState")
	state.start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	for frame in range(60):
		await physics_frame
	room.get_node("Clock").hold(&"classroom_walk_capture")
	room.get_node("OfficeHub").set_mode("monitor")
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	room.get_node("TransitionOverlay").force_hide()
	room.get_node("TransitionOverlay").hide()
	var camera: Camera3D = room.get_node("Camera3D")
	var original_camera := camera.global_transform
	var original_fov := camera.fov
	var actors = room.get_node("Actors")
	var selected := -1
	for index in actors._seated_poses:
		state.sim_core._current_act[index] = "study"
		var actor = actors.actor_for(index)
		actor.global_position = actors._stand_position(actors.seat_node_of(index))
		var walker = actor.get_node_or_null("Walker")
		if walker != null:
			walker.set_process(false)
			walker.set_physics_process(false)
		if actors._seated_poses[index]._binding.standing.ends_with("char_01_body_base_v1.png"):
			selected = index
	assert(selected >= 0)
	actors._process(0.0)
	actors.set_process(false)
	var actor = actors.actor_for(selected)
	actor.get_node("Sprite").hide()
	actors._seated_poses[selected].hide()
	var rig := RIG.new()
	room.add_child(rig)
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
		room.add_child(shadow)
		shadows.append(shadow)
	var start := Vector3(config.start[0], config.start[1], config.start[2])
	var fps: int = config.capture_fps
	var frames := roundi(rig.gait.period * fps * config.capture_cycles)
	DirAccess.make_dir_recursive_absolute(FRAMES)
	for frame in range(frames):
		var time := float(frame) / fps
		rig.set_sample_pose("walk", time)
		rig.position = start + Vector3(0, 0, rig.travel_at(time))
		actor.global_position = rig.global_position
		for side_index in range(2):
			var foot := rig.foot_at([-1.0, 1.0][side_index], time)
			shadows[side_index].position = (
				rig.position + Vector3(rig.gait.shadow_x[side_index], .002, foot.x)
			)
			shadows[side_index].material_override.set_shader_parameter(
				"strength", rig.gait.shadow_strength * (1.0 - foot.y / (rig.gait.foot_lift * 1.5))
			)
		await process_frame
		await RenderingServer.frame_post_draw
		assert(camera.global_transform == original_camera and camera.fov == original_fov)
		var picture := root.get_texture().get_image()
		assert(picture.save_png(FRAMES + "%03d.png" % frame) == OK)
		if frame in [0, 60, frames - 1]:
			assert(picture.save_png(OUTPUT + "classroom_walk_%03d.png" % frame) == OK)
	print(
		"CLASSROOM_WALK: PASS %d frames; original camera unchanged; real classroom depth" % frames
	)
	quit(0)
