extends GutTest
## 真实场景回归：装饰不能改变移动几何、内核 RNG 或人物拾取。

const ROOM := "res://scenes/game/classroom3D.tscn"
const SEED := 20261011


func test_stress_light_updates_with_fixed_camera_without_mutating_core() -> void:
	var room := await _open_room()
	var art = room.get_node("ClassroomArt")
	art.set_camera_follow_enabled(false)
	var core = get_node("/root/GameState").sim_core
	for index in range(core.node_count()):
		core._stress[index] = 0.0
	art._process(100.0)
	var environment: Environment = room.get_node("WorldEnvironment").environment
	var warm := environment.ambient_light_color
	var phase_color: Color = room.get_node("WindowDaylight").light_color
	for index in range(core.node_count()):
		core._stress[index] = 100.0
	var before: PackedFloat64Array = core._stress.duplicate()
	art._process(0.1)
	var transition := environment.ambient_light_color
	art._process(100.0)
	var hot := environment.ambient_light_color
	assert_gt(warm.g, hot.g, "高压环境明显偏红")
	assert_gt(transition.g, hot.g, "压力骤变时逐渐过渡")
	assert_lt(transition.g, warm.g, "固定镜头时灯光仍然更新")
	assert_eq(core._stress, before, "灯光只读，不回写压力")
	assert_eq(room.get_node("WindowDaylight").light_color, phase_color, "保留时段日光")


func before_each() -> void:
	get_node("/root/GameState").start_game(SEED, 16)


func after_each() -> void:
	get_node("/root/GameState").end_game()


func _open_room(art_enabled: bool = true) -> Node3D:
	var room: Node3D = load(ROOM).instantiate()
	if room.has_node("ClassroomArt"):
		room.get_node("ClassroomArt").enabled = art_enabled
	room.get_node("Roam").enabled = false
	add_child_autofree(room)
	await get_tree().process_frame
	room.get_node("Clock").hold(&"art_regression")
	await get_tree().process_frame
	await get_tree().physics_frame
	for frame in range(12):
		await get_tree().physics_frame
	return room


func test_art_is_present_and_rebuild_preserves_geometry_and_rng() -> void:
	var room := await _open_room()
	var art: Node = room.get_node_or_null("ClassroomArt")
	assert_not_null(art, "实际游戏入口必须接入教室美术组件")
	if art == null:
		return
	var player: PlayerController = room.get_node("Player")
	var before: Array = player._raw_obstacles.duplicate()
	var core: SimCore = get_node("/root/GameState").sim_core
	var reference := SimCore.new(SEED, 16)
	assert_eq(core._rng.random(), reference._rng.random(), "装饰不能消耗模拟 RNG")
	var count: int = art.generated_count()
	assert_gt(count, 0, "装饰实际生成")
	art.rebuild()
	await get_tree().process_frame
	assert_eq(art.generated_count(), count, "重建不能叠加装饰或脚下阴影")
	player._collect_obstacles()
	assert_eq(player._raw_obstacles, before, "装饰不能改变纯几何障碍表")
	assert_eq(core._rng.random(), reference._rng.random(), "重建仍不消耗模拟 RNG")
	for child in art.find_children("*", "CollisionObject3D", true, false):
		fail_test("装饰不应生成物理碰撞体：" + str(child.name))
	for actor in room.get_node("Actors").get_children():
		assert_not_null(actor.get_node_or_null("PickBody"), "人物保留拾取体")
		assert_not_null(actor.get_node_or_null("ContactShadow"), "人物有随移动的接触阴影")


func test_four_variants_and_clear_aisles() -> void:
	var baseline := await _open_room(false)
	var walkable: Dictionary = {}
	var baseline_player: PlayerController = baseline.get_node("Player")
	var geometry: Array = baseline_player._raw_obstacles.duplicate()
	for marker in baseline.get_node("StandPoints").get_children():
		walkable[str(marker.name)] = baseline_player.is_walkable(marker.global_position)
	baseline.queue_free()
	await get_tree().process_frame
	get_node("/root/GameState").start_game(SEED, 16)
	var room := await _open_room()
	var art: Node = room.get_node_or_null("ClassroomArt")
	assert_not_null(art, "美术组件存在")
	if art == null:
		return
	var variants: Dictionary = {}
	for decoration in art.get_node("DeskDetails").get_children():
		variants[decoration.get_meta("variant")] = true
	assert_eq(variants.size(), 4, "桌面覆盖四种生活细节组合")
	var player: PlayerController = room.get_node("Player")
	assert_eq(player._raw_obstacles, geometry, "启动时也不改变障碍几何")
	for marker in room.get_node("StandPoints").get_children():
		assert_eq(
			player.is_walkable(marker.global_position),
			walkable[str(marker.name)],
			"保持原有通道站点可走性：" + str(marker.name)
		)


func test_export_presets_include_runtime_art_config() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	for section in ["preset.0", "preset.1"]:
		assert_string_contains(
			str(presets.get_value(section, "include_filter")), "data/ui/classroom_art.json"
		)


func test_warm_window_assets_are_reused_and_rebuild_is_idempotent() -> void:
	var room := await _open_room()
	var art := room.get_node("ClassroomArt") as ClassroomArt
	var assets := art.get_node_or_null("SceneDetails")
	assert_not_null(assets, "当前教室必须实际接入窗户和复用盆栽")
	if assets == null:
		return
	assert_eq(assets.get_child_count(), 32, "窗户、柜体、阅读书架、盆栽和桌侧书包实际接入")
	for window in ["WindowTall1", "WindowTall2", "WindowTall3"]:
		var original := room.get_node("Room/RightWall/" + window) as Node3D
		assert_false(original.visible, "旧窗户不与新模型重叠")
		var replacement := assets.get_node("Warm" + window) as Node3D
		assert_true(
			replacement.global_transform.is_equal_approx(original.global_transform), "沿用原窗洞定位"
		)
	var plant_a := assets.get_node("WindowPlantA") as Node3D
	var plant_b := assets.get_node("WindowPlantB") as Node3D
	assert_eq(plant_a.scene_file_path, plant_b.scene_file_path, "盆栽使用同一个共享组件")
	art.rebuild()
	await get_tree().process_frame
	assert_eq(art.get_node("SceneDetails").get_child_count(), 32, "重建不叠加模型")
	assert_eq(room.find_children("WindowDaylight", "DirectionalLight3D", true, false).size(), 1)


func test_room_uses_neutral_warm_light_and_walls() -> void:
	var room := await _open_room()
	var environment: Environment = room.get_node("WorldEnvironment").environment
	assert_gte(environment.ambient_light_color.r, environment.ambient_light_color.g, "环境光不偏绿")
	assert_gt(environment.ambient_light_color.r, environment.ambient_light_color.b, "保持暖色补光")
	var lower := room.get_node("Room/RightWall/Lower") as MeshInstance3D
	var color: Color = lower.material_override.albedo_color
	assert_gte(color.r, color.g, "大面积墙裙不呈饱和绿")
	assert_lt(absf(color.r - color.g), 0.06, "墙裙保持接近中性的浅暖灰")


func test_window_curtain_does_not_intersect_wall_pillars() -> void:
	var room := await _open_room()
	var curtain := (
		room.get_node("ClassroomArt/SceneDetails/WarmWindowTall2/Window_curtain") as MeshInstance3D
	)
	var pillar := room.get_node("Room/RightWall/Pillar2") as MeshInstance3D
	var cloth_bounds := curtain.global_transform * curtain.get_aabb()
	var pillar_bounds := pillar.global_transform * pillar.get_aabb()
	assert_lte(cloth_bounds.end.x, pillar_bounds.position.x, "全部窗帘褶皱位于墙柱内侧，避免被裁成条纹")


func test_furnishings_use_shared_assets_and_keep_bags_beside_desks() -> void:
	var room := await _open_room()
	var assets := room.get_node("ClassroomArt/SceneDetails")
	assert_false(room.get_node("Room/BackWall/Lockers").visible, "隐藏旧柜体，避免模型重叠")
	assert_false(room.get_node("Room/BackWall/Cabinet").visible, "隐藏旧矮柜")
	assert_not_null(assets.get_node_or_null("ReadingBookshelf"), "阅读书架接入当前教室")
	var cabinet := assets.get_node("WarmStorage1") as Node3D
	for index in range(1, 6):
		var other := assets.get_node("WarmStorage%d" % index) as Node3D
		assert_eq(other.scene_file_path, cabinet.scene_file_path, "矮柜模块复用同一资源")
	for seat in room.get_node("Seats").get_children():
		var bag := assets.get_node("DeskSideBag" + str(seat.name).trim_prefix("P")) as Node3D
		var local_position: Vector3 = seat.to_local(bag.global_position)
		assert_gt(local_position.x, 0.35, "书包位于桌侧，避开人物中心")
		assert_gt(local_position.y, 0.0, "挂包不沉入地面")
		assert_lt(absf(local_position.z), 0.25, "书包靠近桌身")


func test_wall_clock_is_round_and_faces_into_room() -> void:
	var room := await _open_room()
	var clock := room.get_node("ClassroomArt/RoomDetails/WallClock") as Node3D
	var art := room.get_node("ClassroomArt") as ClassroomArt
	var builder := ClassroomArtProps.new(art._materials, art._font)
	for placement in art._style["room_details"]:
		if placement["name"] == "WallClock":
			builder.add_prop(room, art._style["props"]["wall_clock"], placement)
	# Headless dummy renderer returns zero MultiMesh transforms; inspect CPU draw data.
	var transforms: Array = builder._batches["cylinder:metal"]["transforms"]
	var found := false
	for transform: Transform3D in transforms:
		if transform.origin.distance_to(clock.global_position) < 0.01:
			var bounds := transform * builder._unit_mesh("cylinder").get_aabb()
			assert_gt(bounds.size.y, 0.4, "钟面保持竖直圆形轮廓")
			assert_lt(bounds.size.z, 0.08, "钟壳深度不能误用钟面直径")
			found = true
	assert_true(found, "实际墙钟轮廓已生成")


func test_camera_follow_is_limited_and_can_restore_original_view() -> void:
	var room := await _open_room()
	var art := room.get_node("ClassroomArt") as ClassroomArt
	var camera := room.get_node("Camera3D") as Camera3D
	var player := room.get_node("Player") as PlayerController
	var original := camera.global_transform
	var actor_position := player._player_actor.global_position
	player._player_actor.global_position.x += 10.0
	art._process(10.0)
	assert_gt(camera.global_position.x, original.origin.x, "玩家向右移动时镜头向右偏移")
	assert_lte(camera.global_position.x - original.origin.x, 0.800001, "镜头跟随限制在小幅范围")
	assert_true(camera.global_basis.is_equal_approx(original.basis), "平移不改变视角或 WASD 朝向")
	player._player_actor.global_position = actor_position
	art._process(10.0)
	assert_true(camera.global_transform.is_equal_approx(original), "走回起点恢复原取景")
	player._player_actor.global_position.x += 10.0
	art._process(10.0)
	art.set_camera_follow_enabled(false)
	assert_true(camera.global_transform.is_equal_approx(original), "关闭试验立即恢复固定镜头")
	art._process(10.0)
	assert_true(camera.global_transform.is_equal_approx(original), "关闭后不再跟随")
	player._player_actor.global_position = actor_position
