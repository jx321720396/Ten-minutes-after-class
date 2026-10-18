extends GutTest

const COMPONENT := preload("res://scenes/components/layered_student_pose.tscn")


func test_chat_front_back_and_exit_reuse_existing_back_texture() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	settings["activity_poses"] = {"chat": "chat"}
	settings["back_pose_variants"] = {"idle": "idle_back", "chat": "idle_back"}
	var binding: Dictionary = settings.bindings.values()[0].duplicate(true)
	binding["chat"] = binding.idle
	var pose = COMPONENT.instantiate()
	add_child_autofree(pose)
	pose.configure(settings, binding)
	assert_eq(pose.pose_for("chat", "break", true, false, true), "chat")
	assert_true(pose.show_pose("chat"))
	assert_eq(pose._pose, "chat")
	pose.set_group_back(true, false)
	assert_eq(pose._pose, "idle_back", "聊天背面直接调用已有坐姿背影")
	assert_eq(pose.get_node("Upper").texture.atlas.resource_path, str(binding.idle_back))
	pose.show_pose("chat")
	assert_eq(pose._pose, "idle_back", "每帧刷新不能覆盖聊天朝向")
	pose.set_group_back(false, false)
	assert_eq(pose._pose, "chat")
	pose.show_pose("study")
	assert_eq(pose._pose, "study")
	pose.show_pose("idle")
	assert_eq(pose._pose, "idle")
	assert_eq(pose.pose_for("chat", "break", false, false, true), "stand")
	assert_eq(pose.pose_for("chat", "break", true, false, false), "stand")
	pose.show_pose("stand")
	assert_false(pose.visible)


func test_all_students_have_chat_front_and_reuse_their_own_back() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var paths := {}
	var preload_paths := AssetPreloader.pose_texture_paths()
	for binding in settings.bindings.values():
		var path := str(binding.get("chat", ""))
		assert_false(path.is_empty())
		if path.is_empty():
			continue
		assert_false(paths.has(path), "每位学生保留独立外观")
		paths[path] = true
		assert_has(preload_paths, path)
		assert_has(preload_paths, str(binding.idle_back), "复用的背影也在预加载中")
		var pose = COMPONENT.instantiate()
		add_child_autofree(pose)
		pose.configure(settings, binding)
		assert_eq(pose.pose_for("chat", "break", true, false, true), "chat")
		assert_true(pose.show_pose("chat"))
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, path)
		assert_eq(pose.get_node("Upper").texture.atlas.get_size(), Vector2(1024, 1536))
		pose.set_group_back(true, false)
		assert_eq(pose._pose, "idle_back")
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, str(binding.idle_back))
		pose.show_pose("read_book")
		assert_eq(pose._pose, "read_book", "停止聊天后不残留聊天背影")
		pose.show_pose("chat")
		pose.set_group_back(false, false)
		assert_eq(pose._pose, "chat")
		assert_false(pose.get_node("Foreground").visible)
	assert_eq(paths.size(), 16)
