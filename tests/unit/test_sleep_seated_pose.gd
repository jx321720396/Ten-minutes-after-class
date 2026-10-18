extends GutTest

const COMPONENT := preload("res://scenes/components/layered_student_pose.tscn")


func test_all_students_sleep_on_desktop_and_restore_activities() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var paths := {}
	var preload_paths := AssetPreloader.pose_texture_paths()
	for binding in settings.bindings.values():
		var path := str(binding.get("sleep", ""))
		assert_false(path.is_empty())
		if path.is_empty():
			continue
		assert_false(paths.has(path))
		paths[path] = true
		assert_has(preload_paths, path)
		var pose = COMPONENT.instantiate()
		add_child_autofree(pose)
		pose.configure(settings, binding)
		assert_eq(pose.pose_for("sleep", "break", true, false, true), "sleep")
		assert_true(pose.show_pose("sleep"))
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, path)
		assert_eq(pose.get_node("Upper").texture.atlas.get_size(), Vector2(1024, 1536))
		assert_true(pose.get_node("Foreground").visible, "头和手臂不能被桌面遮掉")
		assert_false(pose._settings.use_seat_depth)
		pose.set_group_back(true, false)
		assert_eq(pose._pose, "sleep", "睡觉不使用聊天背影")
		for activity in ["study", "eat_snack", "listen_music", "read_book", "chat"]:
			pose.set_group_back(false, false)
			assert_true(pose.show_pose(activity))
			assert_eq(pose._pose, activity)
			assert_eq(pose.get_node("Foreground").visible, activity == "study")
			assert_true(pose.show_pose("sleep"))
		pose.show_pose("idle")
		assert_eq(pose._pose, "idle")
		assert_false(pose.get_node("Foreground").visible)
		assert_eq(pose.pose_for("sleep", "break", false, false, true), "stand")
		assert_eq(pose.pose_for("sleep", "break", true, false, false), "stand")
		pose.show_pose("stand")
		assert_false(pose.visible)
	assert_eq(paths.size(), 16)


func test_desktop_mesh_tracks_camera_and_sleep_keeps_desktop_depth() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var seat = load("res://scenes/components/desk_chair_compact.tscn").instantiate()
	add_child_autofree(seat)
	var pose = COMPONENT.instantiate()
	add_child_autofree(pose)
	pose.configure(settings, settings.bindings.values()[0])
	pose.bind_seat(seat)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.position = Vector3(0, 2, 4)
	camera.look_at(Vector3(0, 0.7, 0))
	camera.make_current()
	assert_true(pose.show_pose("sleep"))
	var upper: Sprite3D = pose.get_node("Upper")
	assert_almost_eq(upper.position.z, float(settings.body_depth), 0.0001)
	var part: MeshInstance3D = pose.get_node("Foreground").get_child(0)
	assert_not_null(part.mesh)
	var previous_mesh := part.mesh
	camera.position.x += 0.5
	pose._process(0.0)
	assert_ne(part.mesh, previous_mesh, "镜头变化后更新桌面前景投影")
	var center := upper.global_position
	assert_lt(pose.ray_hit(center + Vector3(0, 0, 2), Vector3.FORWARD), INF)
	pose.show_pose("idle")
	assert_false(pose.get_node("Foreground").visible)
