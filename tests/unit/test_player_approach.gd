extends GutTest
## 玩家接近路线（PlayerController 的 plan_approach / follow_path / cancel）与人物拾取体单测。
##
## 依据：主文档 §10.4 / §10.5；docs/superpowers/plans/2026-10-07-chat-playable-loop.md §3.2、§9。
##
## 纯几何与装配部分**不挂树**：直接注入几何与人物节点即可验证，不依赖场景。

## 一间 10×10 的房间（左下角 (-5,-5)），中间一张 2×2 的桌子（原始矩形）。
const BOUNDS := Rect2(-5.0, -5.0, 10.0, 10.0)
const DESK := Rect2(-1.0, -1.0, 2.0, 2.0)
const RANGE := 1.2
const ACTORS_SCRIPT := preload("res://scripts/game/classroom_actors.gd")


## 造一个「已经在场上」的控制器：房间 + 桌子 + 可选站立点，玩家站在 from。
## ⚠️ 人物节点必须**进树**（Node3D 的 global_position 只在树里有效），控制器本身不进树 ——
## 否则会跑 `_ready`，把夹具注入的几何与人物覆盖掉。
func _controller(from: Vector3) -> PlayerController:
	var stage: Node3D = add_child_autofree(Node3D.new())
	var pc: PlayerController = autofree(PlayerController.new())
	pc._bounds = BOUNDS
	pc._raw_obstacles = [DESK]
	pc._obstacles = [DESK.grow(pc._radius)]
	pc._grid = 0.25
	pc._speed = 0.8
	var actor := Node3D.new()
	stage.add_child(actor)
	actor.position = from
	pc._player_actor = actor
	pc._build_nav()
	return pc


func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += Vector2(path[index - 1].x, path[index - 1].z).distance_to(
			Vector2(path[index].x, path[index].z)
		)
	return total


# ------------------------------------------------------------------ 算路（零副作用）


func test_plan_approach_stops_inside_range_and_avoids_the_desk() -> void:
	var pc := _controller(Vector3(-3.0, 0.0, 0.0))
	var plan := pc.plan_approach([Vector3(2.0, 0.0, 0.0)], RANGE)
	assert_true(bool(plan["ok"]), "存在合法接近点：%s" % str(plan))
	var destination: Vector3 = plan["destination"]
	var distance := Vector2(destination.x, destination.z).distance_to(Vector2(2.0, 0.0))
	assert_lte(distance, RANGE, "终点必须在交互范围内（1.2m）")
	assert_true(pc.is_walkable(destination), "终点必须站得住")
	assert_gt(float(plan["length_m"]), 0.0, "路径长度为正")
	assert_gt(
		_length(plan["path"]),
		Vector2(-3.0, 0.0).distance_to(Vector2(2.0, 0.0)),
		"绕开桌子 → 路径比直线更长"
	)
	for point in plan["path"]:
		assert_true(pc.is_walkable(point), "路径点都必须可行走：%s" % str(point))


func test_plan_approach_is_side_effect_free() -> void:
	var pc := _controller(Vector3(-3.0, 0.0, 0.0))
	var before := pc._player_actor.position
	assert_false(pc.is_approaching(), "算路之前没有接近请求")
	pc.plan_approach([Vector3(2.0, 0.0, 0.0)], RANGE)
	assert_eq(pc._player_actor.position, before, "算路不改人物位置")
	assert_false(pc.is_auto_walking(), "算路不启动移动")
	assert_eq(pc.active_request(), -1, "算路不占用请求编号")


func test_plan_approach_without_geometry_fails_explicitly() -> void:
	var stage: Node3D = add_child_autofree(Node3D.new())
	var pc: PlayerController = autofree(PlayerController.new())
	var actor := Node3D.new()
	stage.add_child(actor)
	pc._player_actor = actor
	var plan := pc.plan_approach([Vector3(1.0, 0.0, 0.0)], RANGE)
	assert_false(bool(plan["ok"]))
	assert_eq(str(plan["error"]), "no_geometry")


func test_plan_approach_needs_a_target() -> void:
	var pc := _controller(Vector3(0.5, 0.0, 2.0))
	var plan := pc.plan_approach([], RANGE)
	assert_false(bool(plan["ok"]))
	assert_eq(str(plan["error"]), "no_target")


func test_plan_approach_prefers_the_shortest_path() -> void:
	# 玩家贴在桌子左侧，目标在桌子右侧：最短的合法点应当比「绕远的一侧」更近
	var pc := _controller(Vector3(-3.0, 0.2, 0.0))
	var plan := pc.plan_approach([Vector3(2.0, 0.0, 0.0)], RANGE)
	assert_true(bool(plan["ok"]), str(plan))
	var first: Vector3 = plan["path"][0]
	assert_almost_eq(first.x, pc._cell_center(pc._cell_id(Vector3(-3.0, 0.2, 0.0))).x, 0.001, "起点是玩家所在格")


func test_plan_approach_uses_the_actual_path_end() -> void:
	var pc := _controller(Vector3(-3.0, 0.0, 0.0))
	var plan := pc.plan_approach([Vector3(2.0, 0.0, 0.0)], RANGE)
	var path: PackedVector3Array = plan["path"]
	assert_eq(plan["destination"], path[path.size() - 1], "标记必须用**实际路径终点**，不是另一个吸附点")


# ------------------------------------------------------------------ 跟随 / 取消 / 到达


func test_follow_path_rejects_empty_and_blocked_paths() -> void:
	var pc := _controller(Vector3(-3.0, 0.0, 0.0))
	var failed: Array = []
	pc.request_failed.connect(
		func(request_id: int, reason: StringName) -> void: failed.append([request_id, reason])
	)
	assert_false(pc.follow_path(7, PackedVector3Array()), "空路径必须拒绝")
	assert_eq(failed.size(), 1)
	assert_eq(int(failed[0][0]), 7)
	assert_eq(str(failed[0][1]), "empty_path")
	var through_desk := PackedVector3Array([Vector3(-3.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0)])
	assert_false(pc.follow_path(8, through_desk), "穿桌路径必须拒绝")
	assert_eq(str(failed[1][1]), "blocked_path")
	assert_eq(pc.active_request(), -1, "被拒绝的路径不占用请求编号")


func test_follow_path_then_arrival_carries_the_request_id() -> void:
	var pc := _controller(Vector3(-3.0, 0.0, 0.0))
	var arrived: Array = []
	pc.request_arrived.connect(func(request_id: int) -> void: arrived.append(request_id))
	var plan := pc.plan_approach([Vector3(2.0, 0.0, 0.0)], RANGE)
	assert_true(pc.follow_path(11, plan["path"]), "合法路径应被接受")
	assert_eq(pc.active_request(), 11, "当前请求编号已登记")
	assert_eq(arrived.size(), 0, "还没走到，不发到达")
	pc._finish_path()
	assert_eq(arrived, [11], "到达带请求编号")
	assert_eq(pc.active_request(), -1, "到达后请求清空")
	assert_false(pc.is_auto_walking(), "到达后不再自动行走")


func test_plain_ground_click_never_emits_an_arrival() -> void:
	# 普通点地面没有请求编号：它的到达不得被当成「某个请求走到了」
	var pc := _controller(Vector3(-3.0, 0.0, 0.0))
	var arrived: Array = []
	var cancelled: Array = []
	pc.request_arrived.connect(func(request_id: int) -> void: arrived.append(request_id))
	pc.request_cancelled.connect(
		func(request_id: int, reason: StringName) -> void: cancelled.append([request_id, reason])
	)
	pc._start_auto_walk(Vector3(2.0, 0.0, 0.0))
	assert_true(pc.is_auto_walking(), "普通点地面照常走路")
	pc._finish_path()
	assert_eq(arrived.size(), 0, "没有请求就没有到达通知")
	assert_eq(cancelled.size(), 0)


func test_old_request_callbacks_cannot_touch_a_newer_path() -> void:
	var pc := _controller(Vector3(-3.0, 0.0, 0.0))
	var cancelled: Array = []
	pc.request_cancelled.connect(
		func(request_id: int, reason: StringName) -> void: cancelled.append([request_id, reason])
	)
	var plan := pc.plan_approach([Vector3(2.0, 0.0, 0.0)], RANGE)
	pc.follow_path(21, plan["path"])
	# 旧编号（20）来取消：不该动新路径
	pc.cancel_request_movement(20, &"stale")
	assert_eq(cancelled.size(), 0, "编号对不上就不取消")
	assert_eq(pc.active_request(), 21, "新路径仍在")
	assert_true(pc.is_auto_walking())
	# 自己的编号：取消一次，只发一次
	pc.cancel_request_movement(21, &"new_selection")
	assert_eq(cancelled, [[21, &"new_selection"]])
	assert_eq(pc.active_request(), -1)
	assert_false(pc.is_auto_walking(), "取消后停下")
	pc.cancel_request_movement(21, &"again")
	assert_eq(cancelled.size(), 1, "重复取消不重复发通知")


func test_new_ground_click_cancels_the_pending_approach() -> void:
	var pc := _controller(Vector3(-3.0, 0.0, 0.0))
	var cancelled: Array = []
	pc.request_cancelled.connect(
		func(request_id: int, reason: StringName) -> void: cancelled.append([request_id, reason])
	)
	var plan := pc.plan_approach([Vector3(2.0, 0.0, 0.0)], RANGE)
	pc.follow_path(31, plan["path"])
	pc._start_auto_walk(Vector3(-4.0, 0.0, -4.0))
	assert_eq(cancelled, [[31, &"new_ground_click"]], "新地面点击作废未提交的接近请求")
	assert_true(pc.is_auto_walking(), "新目的地照常生效")


func test_moving_state_is_written_back_to_the_core() -> void:
	# 计划 §3.3：接近时标记玩家为「移动中」，NPC 不把移动中的玩家拉进新交互
	var pc := _controller(Vector3(-3.0, 0.0, 0.0))
	var core := SimCore.from_npc(12345, 8, ConfigLoader.new().load_all())
	pc._core = core
	pc._player_index = int(core.node_count()) - 1
	var plan := pc.plan_approach([Vector3(2.0, 0.0, 0.0)], RANGE)
	pc.follow_path(41, plan["path"])
	assert_true(core.is_moving(pc._player_index), "开始接近 → 内核知道玩家在移动")
	pc.cancel_request_movement(41, &"wasd")
	assert_false(core.is_moving(pc._player_index), "取消移动后清掉移动状态")


# ------------------------------------------------------------------ 交互几何与拾取装配


func test_interaction_geometry_exposes_raw_rects() -> void:
	var pc := _controller(Vector3(-3.0, 0.0, 0.0))
	var geometry := pc.interaction_geometry()
	assert_eq(geometry["bounds"], BOUNDS, "房间边界原样导出")
	var rects: Array = geometry["obstacles"]
	assert_eq(rects.size(), 1)
	assert_eq(rects[0], DESK, "导出的是**未按人物半径外扩**的原始矩形")
	assert_ne(rects[0], pc._obstacles[0], "导航用的是外扩后的矩形，两者不同")


func test_pick_layer_comes_from_config() -> void:
	var pc := _controller(Vector3(0.0, 0.0, 0.0))
	assert_eq(pc.actor_pick_layer, 0, "默认不写死，读配置表")
	pc._load_pick_config()
	assert_eq(pc.effective_pick_layer(), 2, "人物拾取层来自 data/rules/player_interaction.csv")
	assert_eq(pc.effective_blocker_layer(), 1, "世界遮挡层来自同一张表")


# ------------------------------------------------------------------ 点击分派（真实物理射线）

## 造一个俯视镜头 + 可选人物拾取体 / 遮挡体，用**真实射线**验证点击分派。
## 控制器必须**进树**（射线与 get_viewport 都要求）；夹具在 `_ready` 之后再注入，
## 免得被它的自动装配覆盖。
func _click_stage(with_actor: bool, with_blocker: bool) -> Dictionary:
	var stage: Node3D = add_child_autofree(Node3D.new())
	var camera := Camera3D.new()
	camera.look_at_from_position(Vector3(2.0, 6.0, 2.6), Vector3(2.0, 0.0, 2.0), Vector3.UP)
	stage.add_child(camera)
	camera.current = true
	var pc: PlayerController = add_child_autofree(PlayerController.new()) as PlayerController
	await get_tree().process_frame
	await get_tree().process_frame
	var core := SimCore.from_npc(12345, 8, ConfigLoader.new().load_all())
	pc._bounds = BOUNDS
	pc._raw_obstacles = []
	pc._obstacles = []
	pc._grid = 0.25
	pc._pick_layer = 2
	pc._blocker_layer = 1
	pc._core = core
	pc._player_index = int(core.node_count()) - 1
	var actor := Node3D.new()
	stage.add_child(actor)
	actor.position = Vector3(-2.0, 0.0, -2.0)
	pc._player_actor = actor
	pc._build_nav()
	if with_actor:
		stage.add_child(_box_body(Vector3(2.0, 0.5, 2.0), 2, 5))
	if with_blocker:
		stage.add_child(_box_body(Vector3(2.0, 3.0, 2.0), 1, -1))
	return {"pc": pc, "camera": camera, "stage": stage}


func _box_body(at: Vector3, layer: int, actor_index: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	if actor_index >= 0:
		body.set_meta("actor_index", actor_index)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.0, 1.2)
	shape.shape = box
	body.add_child(shape)
	body.position = at
	return body


func test_click_on_actor_selects_instead_of_walking() -> void:
	var fixture: Dictionary = await _click_stage(true, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pc: PlayerController = fixture["pc"]
	var camera: Camera3D = fixture["camera"]
	var picked: Array = []
	var grounded: Array = []
	pc.actor_picked.connect(func(index: int) -> void: picked.append(index))
	pc.ground_clicked.connect(func(point: Vector3) -> void: grounded.append(point))

	var on_actor := camera.unproject_position(Vector3(2.0, 0.5, 2.0))
	assert_eq(str(pc.handle_click(on_actor)), "actor", "命中人物 → 走人物分支")
	assert_eq(picked, [5], "发的是选中信号，带宽内核索引")
	assert_false(pc.is_auto_walking(), "点人物不会先向地面走一步")
	assert_eq(grounded.size(), 0, "不产生地面点击")

	var on_ground := camera.unproject_position(Vector3(-1.0, 0.0, 1.0))
	assert_eq(str(pc.handle_click(on_ground)), "ground", "点空地面 → 照旧走过去")
	assert_true(pc.is_auto_walking(), "地面点击正常启动移动")


func test_actor_behind_a_blocker_is_not_selectable() -> void:
	var fixture: Dictionary = await _click_stage(true, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pc: PlayerController = fixture["pc"]
	var camera: Camera3D = fixture["camera"]
	var picked: Array = []
	pc.actor_picked.connect(func(index: int) -> void: picked.append(index))
	var on_actor := camera.unproject_position(Vector3(2.0, 0.5, 2.0))
	assert_eq(str(pc.handle_click(on_actor)), "ground", "最近的命中是遮挡体 → 不选人")
	assert_eq(picked.size(), 0, "隔着家具选不中")
	assert_true(pc.is_auto_walking(), "这时按地面点击处理")


func test_pick_body_is_derived_from_the_sprite_size() -> void:
	var actors: Node3D = autofree(ACTORS_SCRIPT.new())
	actors.pick_layer = 2
	var actor: Node3D = autofree(Node3D.new())
	actors.add_child(actor)
	var texture := GradientTexture2D.new()
	texture.width = 200
	texture.height = 400
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.pixel_size = 0.0032
	actor.add_child(sprite)
	actors._attach_pick_body(actor, 5)
	var body := actor.get_node_or_null("PickBody") as Area3D
	assert_not_null(body, "拾取体必须存在")
	assert_eq(body.collision_layer, 2, "拾取体在配置的人物拾取层上")
	assert_eq(body.collision_mask, 0, "拾取体不参与物理碰撞，只被射线查询")
	assert_eq(int(body.get_meta("actor_index")), 5, "索引写在元数据里（不靠节点名）")
	var shape := body.get_child(0) as CollisionShape3D
	var box := shape.shape as BoxShape3D
	# 宽度按立绘比例：200 × 0.0032 = 0.64m；高度用统一人物高度
	assert_almost_eq(box.size.x, 0.64, 0.001, "宽度来自实际立绘尺寸")
	assert_almost_eq(box.size.y, actors.character_height, 0.001, "高度来自人物高度")
	assert_eq(shape.position.y, box.size.y * 0.5, "拾取体底部踩在脚底")


func test_pick_body_is_skipped_without_a_layer() -> void:
	var actors: Node3D = autofree(ACTORS_SCRIPT.new())
	actors.pick_layer = 0
	var actor: Node3D = autofree(Node3D.new())
	actors.add_child(actor)
	actors._attach_pick_body(actor, 0)
	assert_null(actor.get_node_or_null("PickBody"), "没有配层就不建拾取体（不静默塞一层）")


func test_feedback_anchor_and_index_lookup() -> void:
	var actors: Node3D = autofree(ACTORS_SCRIPT.new())
	var actor: Node3D = autofree(Node3D.new())
	actors.add_child(actor)
	actor.set_meta("actor_index", 3)
	actors._attach_feedback_anchor(actor)
	assert_almost_eq(
		(actor.get_node("FeedbackAnchor") as Marker3D).position.y,
		actors.feedback_anchor_height,
		0.001,
		"气泡锚点高度可配"
	)
	assert_eq(actors.actor_index_of(actor), 3, "从元数据反查索引")
	var stranger: Node3D = autofree(Node3D.new())
	assert_eq(actors.actor_index_of(stranger), -1, "不是人物返回 -1")
	assert_null(actors.actor_for(0), "还没 build 时越界返回 null")
