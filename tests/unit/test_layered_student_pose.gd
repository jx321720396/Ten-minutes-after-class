extends GutTest

const COMPONENT := "res://scenes/components/layered_student_pose.tscn"


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
	for row in manifest:
		assert_true(settings.bindings.has(row.sprite), "当前名册外观必须有素材绑定")
		if not settings.bindings.has(row.sprite):
			continue
		var binding: Dictionary = settings.bindings[row.sprite]
		assert_eq(binding.standing, row.reference, "姓名映射不能误用旧24人文件编号")
		assert_eq(binding.study, "res://assets/textures/characters/study_front_v1/" + row.file)
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
	assert_eq(pose.pose_for("", "class", true, false, true), "study")
	assert_eq(pose.pose_for("study", "break", true, false, true), "study")
	assert_eq(pose.pose_for("", "break", true, false, true), "stand")
	assert_eq(pose.pose_for("chat", "class", true, false, true), "stand")
	assert_eq(pose.pose_for("study", "break", false, false, true), "stand")
	assert_eq(pose.pose_for("study", "class", true, true, true), "stand")
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
	binding["idle"] = "res://assets/textures/characters/seated_v1/char_01_idle.png"
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
	blocker.global_position = camera.global_position.lerp(head, 0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(
		room.get_node("Player").pick_actor(camera.unproject_position(head)), -1, "可见坐姿仍受真实家具与墙壁遮挡"
	)
	blocker.free()
	core._current_act[index] = "chat"
	actors._process(0.0)
	assert_false(pose.visible, "聊天恢复站姿")
	assert_true(actor.get_node("Sprite").visible)
	core._current_act[index] = "study"
	actor.global_position += Vector3.RIGHT
	actors._process(0.0)
	assert_false(pose.visible, "离开自己的座位后不得悬浮显示桌前坐姿")
	core._current_act[index] = original_activity if not original_activity.is_empty() else null
	state.end_game()
