extends GutTest
## ActorWalker 行走组件单测（表现层）。
##
## 只验证组件「怎么走」：插值到位、时长、朝向、中断与瞬移；
## **不做玩法判断**（该不该走由驱动器决定），也不涉及任何 data 数值。

const WALKER_SCENE := "res://scenes/components/actor_walker.tscn"


## 造一个「人物节点」（Node3D + 名为 Sprite 的 Sprite3D 立绘），并挂上行走组件。
func _make_walker() -> Array:
	var actor := Node3D.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	actor.add_child(sprite)
	add_child_autofree(actor)
	var walker: ActorWalker = load(WALKER_SCENE).instantiate()
	actor.add_child(walker)
	return [actor, walker, sprite]


func test_walk_reaches_target_and_emits_signals() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: ActorWalker = parts[1]
	watch_signals(walker)

	walker.walk_to(Vector3(2.0, 0.0, 1.0), 0.2)
	assert_true(walker.is_moving(), "开始移动后 is_moving 应为 true")
	assert_signal_emitted(walker, "walk_started")

	await wait_seconds(0.5)
	assert_false(walker.is_moving(), "走完应停下")
	assert_signal_emitted(walker, "walk_finished")
	assert_almost_eq(actor.global_position.x, 2.0, 0.001, "终点 X 应到位")
	assert_almost_eq(actor.global_position.z, 1.0, 0.001, "终点 Z 应到位")


func test_zero_duration_arrives_immediately() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: ActorWalker = parts[1]
	walker.walk_to(Vector3(1.5, 0.0, -0.5), 0.0)
	assert_false(walker.is_moving(), "时长为 0 → 立即到位，不进入移动态")
	assert_almost_eq(actor.global_position.x, 1.5, 0.001, "应立即到 X")
	assert_almost_eq(actor.global_position.z, -0.5, 0.001, "应立即到 Z")


func test_height_is_kept_and_settled() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: ActorWalker = parts[1]
	actor.global_position = Vector3(0.0, 0.02, 0.0)
	walker.walk_to(Vector3(1.0, 9.0, 0.0), 0.1)
	await wait_seconds(0.3)
	assert_almost_eq(actor.global_position.y, 0.02, 0.001, "只改 XZ，高度保持原值")
	assert_almost_eq(actor.global_position.x, 1.0, 0.001, "X 到位")


func test_stop_keeps_current_position() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: ActorWalker = parts[1]
	watch_signals(walker)
	walker.walk_to(Vector3(4.0, 0.0, 0.0), 1.0)
	await wait_seconds(0.15)
	walker.stop()
	assert_false(walker.is_moving(), "stop 后不再移动")
	assert_signal_emitted(walker, "walk_finished")
	var stopped_x := actor.global_position.x
	await wait_seconds(0.3)
	assert_almost_eq(actor.global_position.x, stopped_x, 0.001, "停下后位置不再变化")
	assert_true(stopped_x > 0.0 and stopped_x < 4.0, "应停在途中而不是终点")


func test_flip_facing_follows_direction() -> void:
	var parts := _make_walker()
	var walker: ActorWalker = parts[1]
	var sprite: Sprite3D = parts[2]
	walker.walk_to(Vector3(-3.0, 0.0, 0.0), 0.2)
	assert_true(sprite.flip_h, "往 -X 走应翻转朝向")
	await wait_seconds(0.4)
	assert_false(sprite.flip_h, "到位后恢复正面")


func test_teleport_does_not_emit_started() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: ActorWalker = parts[1]
	watch_signals(walker)
	walker.teleport_to(Vector3(2.0, 0.0, 2.0))
	assert_almost_eq(actor.global_position.x, 2.0, 0.001, "瞬移立即到位（X）")
	assert_almost_eq(actor.global_position.z, 2.0, 0.001, "瞬移立即到位（Z）")
	assert_false(walker.is_moving(), "瞬移不进入移动态")
	assert_signal_not_emitted(walker, "walk_started")


# ------------------------------------------------------------------ 导航行走（教室用；本测试场景没有导航地图）


## 没有导航地图时：**明确失败且一步不走** —— 直线兜底会穿桌（§10.4）。
func test_navigated_walk_without_a_map_fails_and_does_not_move() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: ActorWalker = parts[1]
	var before := actor.global_position
	assert_false(walker.walk_to_navigated(Vector3(2.0, 0.0, 2.0), 1.0), "没有导航地图应返回 false")
	assert_false(walker.is_moving(), "不应进入移动态")
	await wait_seconds(0.2)
	assert_eq(actor.global_position, before, "一步都不该走")


## 按**时限**导航行走同样在没有地图时明确失败。
func test_navigated_walk_in_without_a_map_fails() -> void:
	var parts := _make_walker()
	var walker: ActorWalker = parts[1]
	assert_false(walker.walk_to_navigated_in(Vector3(1.0, 0.0, 0.0), 3.0), "没有导航地图应返回 false")
	assert_false(walker.is_moving(), "不应进入移动态")


## 直线回退是**显式开关**（只给"没有导航地图的单测"用），不是默认行为。
func test_straight_fallback_is_opt_in() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: ActorWalker = parts[1]
	assert_true(
		walker.walk_to_navigated(Vector3(1.0, 0.0, 0.0), 2.0, true), "显式开启回退 → 返回 true"
	)
	assert_true(walker.is_moving(), "回退会真的走直线")
	await wait_seconds(1.0)
	assert_almost_eq(actor.global_position.x, 1.0, 0.01, "直线回退到位")
