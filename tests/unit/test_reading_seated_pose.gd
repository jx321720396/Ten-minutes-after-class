extends GutTest

const COMPONENT := preload("res://scenes/components/layered_student_pose.tscn")


func test_reading_pose_tracks_activity_and_restores_other_poses() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	settings["activity_poses"] = {"read_book": "read_book"}
	var binding: Dictionary = settings.bindings.values()[0].duplicate(true)
	binding["read_book"] = binding.idle
	var pose = COMPONENT.instantiate()
	add_child_autofree(pose)
	pose.configure(settings, binding)
	assert_eq(pose.pose_for("read_book", "break", true, false, true), "read_book")
	assert_eq(pose.pose_for("read_book", "break", false, false, true), "stand")
	assert_eq(pose.pose_for("read_book", "break", true, false, false), "stand")
	assert_true(pose.show_pose("read_book"))
	assert_true(pose.visible)
	assert_false(pose.get_node("Foreground").visible)
	pose.set_group_back(true, false)
	assert_eq(pose._pose, "read_book", "看课外书贴图不被聊天背影覆盖")
	pose.show_pose("study")
	assert_eq(pose._pose, "study")
	pose.set_group_back(false, false)
	pose.show_pose("idle")
	assert_eq(pose._pose, "idle")
	pose.show_pose("stand")
	assert_false(pose.visible)


func test_every_student_has_distinct_loadable_reading_pose() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var paths := {}
	var preload_paths := AssetPreloader.pose_texture_paths()
	for binding in settings.bindings.values():
		var path := str(binding.get("read_book", ""))
		assert_false(path.is_empty(), "每位学生都有看课外书贴图")
		if path.is_empty():
			continue
		assert_false(paths.has(path), "学生之间不复用同一张脸")
		paths[path] = true
		assert_has(preload_paths, path, "看课外书贴图进入后台预加载")
		var pose = COMPONENT.instantiate()
		add_child_autofree(pose)
		pose.configure(settings, binding)
		assert_eq(pose.pose_for("read_book", "break", true, false, true), "read_book")
		assert_true(pose.show_pose("read_book"))
		var texture: Texture2D = pose.get_node("Upper").texture.atlas
		assert_eq(texture.resource_path, path)
		assert_eq(texture.get_size(), Vector2(1024, 1536))
		pose.show_pose("eat_snack")
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, str(binding.eat_snack))
		pose.show_pose("read_book")
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, path)
		assert_false(pose.get_node("Foreground").visible)
		pose.show_pose("listen_music")
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, str(binding.listen_music))
		pose.show_pose("read_book")
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, path)
		pose.show_pose("idle")
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, str(binding.idle))
	assert_eq(paths.size(), 16)


func test_roster_uses_only_the_five_shared_book_designs() -> void:
	var rows: Array = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://assets/textures/characters/reading_seated_v1/manifest.json"
		)
	)
	var books: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://assets/textures/characters/reading_seated_v1/books.json"
		)
	)
	assert_eq(books.size(), 5)
	assert_eq(rows.size(), 16)
	var used := {}
	for row in rows:
		assert_has(books, str(row.book), "全班复用配置中的五款书")
		used[str(row.book)] = true
	assert_eq(used.size(), 5)
