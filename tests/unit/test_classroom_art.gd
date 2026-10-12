extends GutTest
## 真实场景回归：装饰不能改变移动几何、内核 RNG 或人物拾取。

const ROOM := "res://scenes/game/classroom3D.tscn"
const SEED := 20261011


func before_each() -> void:
	get_node("/root/GameState").start_game(SEED, 2)


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
	var reference := SimCore.new(SEED, 2)
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
	get_node("/root/GameState").start_game(SEED, 2)
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
