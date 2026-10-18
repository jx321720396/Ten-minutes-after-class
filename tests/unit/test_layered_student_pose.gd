extends GutTest

const COMPONENT := "res://scenes/components/layered_student_pose.tscn"


func test_seated_back_uses_actual_chair_anchor_and_cushion_height() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var seat = load("res://scenes/components/desk_chair_compact.tscn").instantiate()
	add_child_autofree(seat)
	var pose = load(COMPONENT).instantiate()
	add_child_autofree(pose)
	pose.configure(settings, settings.bindings.values()[0])
	assert_true(pose.has_method("bind_seat"), "坐姿必须绑定真实椅子")
	if not pose.has_method("bind_seat"):
		return
	pose.bind_seat(seat)
	pose.show_pose("idle")
	pose.set_group_back(true, false)
	var upper: Sprite3D = pose.get_node("Upper")
	var lower: Sprite3D = pose.get_node("Lower")
	var anchor: Node3D = seat.get_node("SitPoint")
	var cushion: MeshInstance3D = seat.get_node("Chair/Seat")
	var expected_top: float = cushion.position.y + cushion.get_aabb().end.y
	assert_almost_eq(upper.position.z, anchor.position.z, 0.0001)
	assert_almost_eq(lower.position.z, anchor.position.z, 0.0001)
	var split: float = pose._settings["split_y"]
	var hip: float = upper.position.y - split * upper.pixel_size * upper.scale.y * 0.5
	assert_almost_eq(hip, expected_top, 0.0001, "坐骨落在实际坐垫上表面")


func test_idle_can_turn_back_and_restore_without_standing_up() -> void:
	var settings: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var binding: Dictionary = settings.bindings.values()[0].duplicate(true)
	# 先复用已存在纹理验证切换协议，不依赖新素材导入进度。
	binding["idle_back"] = binding["study"]
	var pose = load(COMPONENT).instantiate()
	add_child_autofree(pose)
	pose.configure(settings, binding)
	pose.show_pose("idle")
	assert_true(pose.has_method("set_group_back"), "坐姿组件必须支持共同活动转背")
	if not pose.has_method("set_group_back"):
		return
	pose.set_group_back(true, false)
	assert_eq(pose._pose, "idle_back")
	assert_true(pose.visible)
	assert_false(pose.get_node("Foreground").visible)
	pose.show_pose("idle")
	assert_eq(pose._pose, "idle_back", "每帧刷新坐姿不能覆盖转身")
	pose.set_group_back(false, false)
	assert_eq(pose._pose, "idle")
	pose.set_group_back(true, false)
	pose.show_pose("study")
	assert_eq(pose._pose, "study", "学习姿势不被聊天背影覆盖")
	pose.show_pose("stand")
	assert_false(pose.visible)


func test_all_students_have_idle_seated_pose_and_safe_transitions() -> void:
	var settings = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var rows: Array = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://assets/textures/characters/idle_seated_v1/manifest.json"
		)
	)
	assert_eq(rows.size(), 16)
	for row in rows:
		var binding: Dictionary = settings.bindings[row.sprite]
		assert_eq(
			binding.get("idle", ""),
			"res://assets/textures/characters/idle_seated_v1/" + row.file,
			"Each student must use their own idle image"
		)
		if not binding.has("idle"):
			continue
		var pose = load(COMPONENT).instantiate()
		add_child_autofree(pose)
		pose.configure(settings, binding)
		assert_eq(pose.pose_for("", "break", true, false, true), "idle")
		assert_eq(pose.pose_for("", "class", true, false, true), "idle")
		assert_eq(pose.pose_for("study", "break", true, false, true), "study")
		for activity in ["chat", "game", "sleep", "read"]:
			assert_eq(pose.pose_for(activity, "break", true, false, true), "idle")
			assert_eq(pose.pose_for(activity, "break", false, false, true), "stand")
		assert_eq(pose.pose_for("", "break", true, true, true), "idle")
		assert_eq(pose.pose_for("", "break", false, false, true), "stand")
		assert_eq(pose.pose_for("", "break", true, false, false), "stand")
		pose.show_pose("idle")
		assert_true(pose.visible)
		assert_false(pose.get_node("Foreground").visible, "Lap hands stay behind desktop")
		assert_eq(pose.get_node("Upper").texture.atlas, pose._textures["idle"])
		pose.show_pose("study")
		assert_true(pose.get_node("Foreground").visible)
		pose.show_pose("idle")
		assert_false(pose.get_node("Foreground").visible)
		assert_true(binding.has("idle_back"), "全班每人必须绑定独立坐姿背影")
		pose.set_group_back(true, false)
		assert_eq(pose._pose, "idle_back")
		assert_false(pose.get_node("Foreground").visible)
		assert_eq(pose.get_node("Upper").texture.atlas.resource_path, str(binding["idle_back"]))
		pose.set_group_back(false, false)
		assert_eq(pose._pose, "idle")


func test_full_roster_has_matching_standing_and_downward_study_assets() -> void:
	var settings = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var manifest = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://assets/textures/characters/study_front_v1/manifest.json"
		)
	)
	assert_eq(settings.bindings.size(), 16, "16名同学全部接入")
	var standing: Array = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/textures/characters/identity_v3/manifest.json")
	)
	for row in manifest:
		assert_true(settings.bindings.has(row.sprite), "当前名册外观必须有素材绑定")
		if not settings.bindings.has(row.sprite):
			continue
		var binding: Dictionary = settings.bindings[row.sprite]
		var standing_row: Dictionary = standing[int(row.id) - 1]
		assert_eq(standing_row.id, row.id)
		assert_eq(standing_row.identity_reference, row.reference, "保持原人物参考身份")
		assert_eq(binding.standing, standing_row.reference, "绑定对应同学的自然站姿")
		var texture := load(str(binding.standing)) as Texture2D
		assert_gt(int(binding.standing_floor_pixel), 0)
		assert_lte(int(binding.standing_floor_pixel), texture.get_height(), "鞋底标定不能超出原图")
		assert_eq(binding.study, standing_row.study, "站立与学习共享同一差异化外貌")
		assert_eq(
			standing_row.original_study,
			"res://assets/textures/characters/study_front_v1/" + row.file
		)
		assert_false(str(standing_row.features).is_empty(), "每位同学须有可辨识的外貌特征")
		assert_true(binding.has("layout"), "每图单独校准桌面和前景")
	assert_almost_eq(float(settings.get("standing_scale", 0)), 1.3225, 0.0001)


func test_export_presets_include_pose_config() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	for section in presets.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			assert_true(
				str(presets.get_value(section, "include_filter", "")).contains(
					"data/ui/student_poses.json"
				),
				"移动端导出必须包含分层姿态配置"
			)
			assert_true(
				str(presets.get_value(section, "include_filter", "")).contains(
					"data/ui/npc_profile.json"
				),
				"移动端导出必须包含档案与推理板画像映射"
			)


func test_pose_respects_activity_presence_and_movement() -> void:
	assert_true(ResourceLoader.exists(COMPONENT), "正式坐姿组件必须存在")
	if not ResourceLoader.exists(COMPONENT):
		return
	var pose = load(COMPONENT).instantiate()
	add_child_autofree(pose)
	var settings = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	pose.configure(settings, settings.bindings.values()[0])
	assert_eq(pose.pose_for("", "class", true, false, true), "idle")
	assert_eq(pose.pose_for("study", "break", true, false, true), "study")
	assert_eq(pose.pose_for("", "break", true, false, true), "idle")
	assert_eq(pose.pose_for("chat", "class", true, false, true), "idle")
	assert_eq(pose.pose_for("study", "break", false, false, true), "stand")
	assert_eq(pose.pose_for("study", "class", true, true, true), "study")
	assert_eq(pose.pose_for("study", "class", true, false, false), "stand")


func test_foreground_uses_same_texture_and_restores_standing_sprite() -> void:
	if not ResourceLoader.exists(COMPONENT):
		return
	var pose = load(COMPONENT).instantiate()
	add_child_autofree(pose)
	var settings = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/student_poses.json")
	)
	var binding: Dictionary = settings["bindings"].values()[0].duplicate(true)
	binding["idle"] = "res://assets/textures/characters/seated_v1/char_01_idle.webp"
	pose.configure(settings, binding)
	pose.show_pose("study")
	assert_true(pose.visible)
	assert_true(pose.get_node("Foreground").visible)
	assert_eq(
		pose.get_node("Upper").texture.atlas,
		pose.get_node("Foreground").get_child(0).material_override.albedo_texture
	)
	pose.show_pose("idle")
	assert_false(pose.get_node("Foreground").visible)
	pose.show_pose("stand")
	assert_false(pose.visible)


func test_real_classroom_switches_without_moving_actor_or_writing_core() -> void:
	var state := get_node("/root/GameState")
	state.start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	add_child_autofree(room)
	await get_tree().process_frame
	room.get_node("Clock").hold(&"pose_regression")
	for frame in range(15):
		await get_tree().physics_frame
	var actors = room.get_node("Actors")
	var core = state.sim_core
	assert_eq(actors._seated_poses.size(), 16, "全班同学启用新版图片")
	var index = actors._seated_poses.keys()[0]
	for candidate in actors._seated_poses:
		var standing = actors.actor_for(candidate).get_node("Sprite")
		var binding: Dictionary = actors._seated_poses[candidate]._binding
		var sole: float = (
			standing.position.y
			+ (
				(standing.texture.get_height() * 0.5 - binding.standing_floor_pixel)
				* standing.pixel_size
			)
		)
		assert_almost_eq(sole, 0.0, 0.0001, "每张站姿的实际鞋底都落在人物根节点")
		if (
			actors.seat_node_of(candidate).global_position.z
			> actors.seat_node_of(index).global_position.z
		):
			index = candidate
	var actor = actors.actor_for(index)
	var pose = actor.get_node("SeatedPose")
	var seat = actors.seat_node_of(index)
	actor.global_position = actors._stand_position(seat)
	var root_position = actor.global_position
	var original_activity = core.activity_of(index)
	core._current_act[index] = "study"  # fixture only; presentation must not write this.
	var rng_state = core._rng._mt.duplicate()
	var rng_index = core._rng._mti
	var grade = core.grade(index)
	actors._process(0.0)
	assert_true(pose.visible, "在座学习使用分层坐姿")
	assert_false(actor.get_node("Sprite").visible)
	assert_eq(actor.global_position, root_position, "坐姿只移动显示，不移动寻路根节点")
	assert_eq(core._rng._mt, rng_state)
	assert_eq(core._rng._mti, rng_index)
	assert_eq(core.grade(index), grade)
	assert_eq(core.activity_of(index), "study")
	var camera = room.get_node("Camera3D")
	# Isolate the frontmost real desk; roster order must not imply an unobstructed view.
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.look_at_from_position(
		seat.global_position + Vector3(0, 1.6, 2.5), seat.global_position + Vector3(0, .8, 0)
	)
	var head = pose.to_global(
		pose._foreground_vertex(Vector2(512, 220), pose._textures["study"], camera)
	)
	assert_eq(
		room.get_node("Player").pick_actor(camera.unproject_position(head)),
		index,
		"监控点击坐姿头部仍能选中同一名学生"
	)
	var pen_hand = pose.to_global(
		pose._foreground_vertex(Vector2(385, 650), pose._textures["study"], camera)
	)
	assert_eq(
		room.get_node("Player").pick_actor(camera.unproject_position(pen_hand)),
		index,
		"桌上手臂仍可拾取，不被原课桌包围盒吞掉"
	)
	var blocker := StaticBody3D.new()
	blocker.collision_layer = room.get_node("Player")._blocker_layer
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 0.2
	box.shape = shape
	blocker.add_child(box)
	room.add_child(blocker)
	var ray_origin: Vector3 = camera.project_ray_origin(camera.unproject_position(head))
	blocker.global_position = ray_origin.lerp(head, 0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(
		room.get_node("Player").pick_actor(camera.unproject_position(head)), -1, "可见坐姿仍受真实家具与墙壁遮挡"
	)
	blocker.free()
	core._current_act[index] = "chat"
	actors._process(0.0)
	assert_true(pose.visible, "在座聊天保持坐姿")
	assert_eq(pose._pose, "idle")
	assert_false(actor.get_node("Sprite").visible)
	core._current_act[index] = "study"
	actor.global_position += Vector3.RIGHT
	actors._process(0.0)
	assert_false(pose.visible, "离开自己的座位后不得悬浮显示桌前坐姿")
	core._current_act[index] = original_activity if not original_activity.is_empty() else null
	state.end_game()
