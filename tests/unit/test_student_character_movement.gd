extends GutTest
## ActorWalker「按速度走」单测（表现层）：验证 `walk_to_at_speed()` 按实际距离 / 速度
## 换算耗时并正确到位 —— 与玩家 PlayerController 同口径（策划 2026-10-07 裁决第 6b 项，
## 统一速度、耗时随实际行走距离变化，放弃固定 15 tick）。
## 驱动器侧（classroom_roam.gd）的口径单测在 test_classroom_roam_movement.gd。

const WALKER_SCENE := "res://scenes/components/actor_walker.tscn"


## 造一个「人物节点」（Node3D + 名为 Sprite 的 Sprite3D 立绘），并挂上行走组件。
## 不用 class_name ActorWalker（class_name 需要全局类缓存，直接跑本文件时不一定已生成），
## 统一用节点引用 + 鸭子类型调用，与 test_classroom_roam_movement.gd 同风格。
func _make_walker() -> Array:
	var actor := Node3D.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	actor.add_child(sprite)
	add_child_autofree(actor)
	var walker: Node = load(WALKER_SCENE).instantiate()
	actor.add_child(walker)
	return [actor, walker, sprite]


func test_walk_to_at_speed_arrives_in_expected_seconds() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: Node = parts[1]
	watch_signals(walker)
	actor.global_position = Vector3.ZERO
	# 距离 2.0m，速度 0.5 m/s → 4.0s 到位
	walker.walk_to_at_speed(Vector3(2.0, 0.0, 0.0), 0.5)
	assert_true(walker.is_moving(), "应按速度进入移动态")
	assert_signal_emitted(walker, "walk_started")
	await wait_seconds(4.5)
	assert_false(walker.is_moving(), "走完应停下")
	assert_signal_emitted(walker, "walk_finished")
	assert_almost_eq(actor.global_position.x, 2.0, 0.001, "终点 X 应到位")
	assert_almost_eq(actor.global_position.z, 0.0, 0.001, "终点 Z 应到位")


func test_walk_to_at_speed_zero_speed_is_noop() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: Node = parts[1]
	var start := actor.global_position
	walker.walk_to_at_speed(Vector3(3.0, 0.0, 0.0), 0.0)
	assert_false(walker.is_moving(), "速度 ≤ 0 → 不移动")
	assert_eq(actor.global_position, start, "位置不应变化")


func test_walk_to_at_speed_negative_speed_is_noop() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: Node = parts[1]
	var start := actor.global_position
	walker.walk_to_at_speed(Vector3(3.0, 0.0, 0.0), -0.5)
	assert_false(walker.is_moving(), "负速度（防御）→ 不移动")
	assert_eq(actor.global_position, start, "位置不应变化")


func test_walk_to_at_speed_longer_distance_takes_longer() -> void:
	var parts := _make_walker()
	var actor: Node3D = parts[0]
	var walker: Node = parts[1]
	actor.global_position = Vector3.ZERO
	walker.walk_to_at_speed(Vector3(4.0, 0.0, 0.0), 0.5)  # 4m / 0.5 = 8s
	await wait_seconds(4.5)
	assert_true(walker.is_moving(), "4 秒时 8 秒的行程应仍在移动")
	await wait_seconds(4.5)
	assert_false(walker.is_moving(), "走完 8 秒后应停下")
