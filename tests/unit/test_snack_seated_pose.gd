extends GutTest

const COMPONENT := preload("res://scenes/components/layered_student_pose.tscn")


func test_snack_pose_tracks_activity_and_restores_other_poses() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	settings["activity_poses"] = {"eat_snack": "eat_snack"}
	var binding: Dictionary = settings.bindings.values()[0].duplicate(true)
	binding["eat_snack"] = binding.idle
	var pose = COMPONENT.instantiate()
	add_child_autofree(pose)
	pose.configure(settings, binding)
	assert_eq(pose.pose_for("eat_snack", "break", true, false, true), "eat_snack")
	assert_eq(pose.pose_for("eat_snack", "break", false, false, true), "stand")
	assert_eq(pose.pose_for("eat_snack", "break", true, false, false), "stand")
	assert_true(pose.show_pose("eat_snack"))
	assert_true(pose.visible)
	assert_false(pose.get_node("Foreground").visible)
	pose.set_group_back(true, false)
	assert_eq(pose._pose, "eat_snack", "吃零食贴图不被聊天背影覆盖")
	pose.show_pose("study")
	assert_eq(pose._pose, "study")
	pose.set_group_back(false, false)
	pose.show_pose("idle")
	assert_eq(pose._pose, "idle")
	pose.show_pose("stand")
	assert_false(pose.visible)


func test_every_student_has_distinct_loadable_snack_pose() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var paths := {}
	var preload_paths := AssetPreloader.pose_texture_paths()
	for binding in settings.bindings.values():
		var path := str(binding.get("eat_snack", ""))
		assert_false(path.is_empty(), "每位学生都有吃零食贴图")
		if path.is_empty():
			continue
		assert_false(paths.has(path), "学生之间不复用同一张脸")
		paths[path] = true
		assert_has(preload_paths, path, "吃零食贴图进入后台预加载")
		var pose = COMPONENT.instantiate()
		add_child_autofree(pose)
		pose.configure(settings, binding)
		assert_eq(pose.pose_for("eat_snack", "break", true, false, true), "eat_snack")
		assert_true(pose.show_pose("eat_snack"))
		var texture: Texture2D = pose.get_node("Upper").texture.atlas
		assert_eq(texture.resource_path, path)
		assert_eq(texture.get_size(), Vector2(1024, 1536))
	assert_eq(paths.size(), 16)
