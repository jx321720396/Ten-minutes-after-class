extends GutTest

const COMPONENT := preload("res://scenes/components/layered_student_pose.tscn")


func test_music_pose_tracks_activity_and_restores_other_poses() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	settings["activity_poses"] = {"listen_music": "listen_music"}
	var binding: Dictionary = settings.bindings.values()[0].duplicate(true)
	binding["listen_music"] = binding.idle
	var pose = COMPONENT.instantiate()
	add_child_autofree(pose)
	pose.configure(settings, binding)
	assert_eq(pose.pose_for("listen_music", "break", true, false, true), "listen_music")
	assert_eq(pose.pose_for("listen_music", "break", false, false, true), "stand")
	assert_eq(pose.pose_for("listen_music", "break", true, false, false), "stand")
	assert_true(pose.show_pose("listen_music"))
	assert_true(pose.visible)
	assert_false(pose.get_node("Foreground").visible)
	pose.set_group_back(true, false)
	assert_eq(pose._pose, "listen_music", "听音乐贴图不被聊天背影覆盖")
	pose.show_pose("study")
	assert_eq(pose._pose, "study")
	pose.set_group_back(false, false)
	pose.show_pose("idle")
	assert_eq(pose._pose, "idle")
	pose.show_pose("stand")
	assert_false(pose.visible)


func test_every_student_has_distinct_loadable_music_pose() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var paths := {}
	var preload_paths := AssetPreloader.pose_texture_paths()
	for binding in settings.bindings.values():
		var path := str(binding.get("listen_music", ""))
		assert_false(path.is_empty(), "每位学生都有听音乐贴图")
		if path.is_empty():
			continue
		assert_false(paths.has(path), "学生之间不复用同一张脸")
		paths[path] = true
		assert_has(preload_paths, path, "听音乐贴图进入后台预加载")
		var pose = COMPONENT.instantiate()
		add_child_autofree(pose)
		pose.configure(settings, binding)
		assert_eq(pose.pose_for("listen_music", "break", true, false, true), "listen_music")
		assert_true(pose.show_pose("listen_music"))
		var texture: Texture2D = pose.get_node("Upper").texture.atlas
		assert_eq(texture.resource_path, path)
		assert_eq(texture.get_size(), Vector2(1024, 1536))
		pose.show_pose("eat_snack")
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, str(binding.eat_snack))
		pose.show_pose("listen_music")
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, path)
		assert_false(pose.get_node("Foreground").visible)
		pose.show_pose("idle")
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, str(binding.idle))
	assert_eq(paths.size(), 16)
