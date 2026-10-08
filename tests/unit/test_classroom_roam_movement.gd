extends GutTest
## ClassroomRoam 移动耗时口径单测（表现层）。
##
## 只验证「耗时怎么算」：统一速度（movement.csv 的 meters_per_tick）× 实际距离，
## 与玩家 PlayerController 同口径（策划 2026-10-07 裁决第 6b 项）；不验证
## 「该不该走 / 走到哪」的玩法判断（那是 _decide_batch / _pick_point 的职责，
## 另有演示参数 leave_probability，不在此测）。

const MOVEMENT_TABLE := "rules/movement"


## 造一个不挂树的组件实例，直接注入 _speed / _fallback_seconds / _snapshot ——
## 与 test_player_controller.gd 的做法一致（_ready 不跑，避免依赖场景装配）。
func _roam() -> Node:
	var loader := ConfigLoader.new()
	var speed := 0.13
	var rows: Array = loader.get_table(MOVEMENT_TABLE).get("rows", [])
	for row in rows:
		if str(row.get("param", "")) == "meters_per_tick":
			speed = float(str(row.get("value", "0")))
			break
	var roam_script: Script = load("res://scripts/game/classroom_roam.gd")
	var node: Node = roam_script.new()
	node._speed = speed
	node._fallback_seconds = 15.0
	node._snapshot = {"remaining_seconds": 100.0, "kind": "class"}
	return node


func test_move_seconds_scales_with_distance() -> void:
	var roam := _roam()
	var speed_value: float = roam._speed
	assert_almost_eq(roam.move_seconds(speed_value * 10.0), 10.0, 0.001, "距离 = 10×速度 → 10 秒")
	assert_almost_eq(roam.move_seconds(speed_value * 30.0), 30.0, 0.001, "距离 = 30×速度 → 30 秒")
	assert_true(roam.move_seconds(speed_value * 30.0) > roam.move_seconds(speed_value * 10.0), "耗时随距离单调递增")


func test_move_seconds_zero_distance_uses_fallback() -> void:
	var roam := _roam()
	assert_eq(roam.move_seconds(0.0), roam._fallback_seconds, "距离为 0 → 兜底时长")
	assert_eq(roam.move_seconds(-1.0), roam._fallback_seconds, "负距离（防御）→ 兜底时长")


func test_home_seconds_capped_by_remaining_class_time() -> void:
	var roam := _roam()
	# 剩余 100 秒 → 80% = 80 秒；距离大到需要 100 秒（约 7.69 米）
	var seconds: float = roam._home_seconds(1000.0)
	assert_almost_eq(seconds, 80.0, 0.001, "超过剩余 80% 应被钳制")


func test_home_seconds_short_distance_not_capped() -> void:
	var roam := _roam()
	# 距离 10 米 → 10/0.13 ≈ 76.9 秒，小于 80 秒上限 → 不被钳制
	var seconds: float = roam._home_seconds(10.0)
	var speed_value: float = roam._speed
	assert_almost_eq(seconds, 10.0 / speed_value, 0.01, "距离不足时按实际距离计算，不被钳制")


func test_home_seconds_no_snapshot_uses_distance() -> void:
	var roam := _roam()
	roam._snapshot = {}
	# 剩余时间未知（快照空）→ 只按距离算，不受 80% 上限影响
	var seconds: float = roam._home_seconds(10.0)
	var speed_value: float = roam._speed
	assert_almost_eq(seconds, 10.0 / speed_value, 0.01, "无快照时距离口径生效")
