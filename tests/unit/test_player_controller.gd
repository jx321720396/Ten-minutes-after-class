extends GutTest
## 玩家操控组件（PlayerController）单测：桌椅阻挡、格网换算、内核位置/占用接口。
##
## 依据：主文档 §10.5（玩家位置与交互范围）、§10.4（走动耗时）；策划 2026-10-07 裁决第 4/5 项。
##
## 纯几何部分**不挂树**（_ready 不跑），直接注入 _bounds / _obstacles 就能测 ——
## 这保证阻挡判定不依赖场景装配，可独立复现。

const SEED := 12345
const NPC := 8


## 一间 10×10 的房间（左下角 (-5,-5)），中间一张 2×2 的桌子（中心原点，已外扩人物半径）。
func _controller() -> PlayerController:
	var pc := PlayerController.new()
	pc._bounds = Rect2(-5.0, -5.0, 10.0, 10.0)
	pc._obstacles = [Rect2(-1.0, -1.0, 2.0, 2.0)]
	pc._grid = 0.25
	return pc


func test_is_walkable_rejects_desk_and_bounds() -> void:
	var pc := _controller()
	assert_false(pc.is_walkable(Vector3(0.0, 0.0, 0.0)), "桌子中心不可站")
	assert_false(pc.is_walkable(Vector3(0.9, 0.0, 0.9)), "桌子角落内不可站")
	assert_false(pc.is_walkable(Vector3(6.0, 0.0, 0.0)), "房间外不可站")
	assert_true(pc.is_walkable(Vector3(2.0, 0.0, 2.0)), "过道可站")
	assert_true(pc.is_walkable(Vector3(-2.0, 0.0, -2.0)), "过道可站")


func test_slide_stops_at_desk() -> void:
	var pc := _controller()
	# 从 (-2, 0) 朝 +X 走 1.5：撞上桌子左沿（x=-1），一步也走不进 → 停在原地
	var result: Vector3 = pc._slide(Vector3(-2.0, 0.0, 0.0), Vector3(1.5, 0.0, 0.0))
	assert_eq(result, Vector3(-2.0, 0.0, 0.0), "撞桌子应停在原地")


func test_slide_glides_along_desk_edge() -> void:
	var pc := _controller()
	# 从 (-1.5, 0) 斜向右上：整体与 X 轴都被挡，只有 Z 轴可行 → 沿桌沿滑（只走 Z）
	var result: Vector3 = pc._slide(Vector3(-1.5, 0.0, 0.0), Vector3(0.8, 0.0, 0.8))
	assert_eq(result, Vector3(-1.5, 0.0, 0.8), "斜向撞墙应沿墙滑")


func test_cell_center_roundtrip() -> void:
	var pc := _controller()
	# 原点 (0,0) 落在第 (20,20) 格：中心 = -5 + 20.5 × 0.25 = 0.125
	var id := pc._cell_id(Vector3(0.0, 0.0, 0.0))
	var center := pc._cell_center(id)
	assert_almost_eq(center.x, 0.125, 0.001, "格中心 x")
	assert_almost_eq(center.z, 0.125, 0.001, "格中心 z")


# ------------------------------------------------------------------ 内核位置 / 占用接口


func test_core_position_roundtrip_and_distance() -> void:
	var core := SimCore.from_npc(SEED, NPC, ConfigLoader.new().load_all())
	var me := int(core.node_count()) - 1
	core.set_position(me, 1.5, -2.25)
	assert_eq(core.position_of(me), Vector2(1.5, -2.25), "位置往返应一致")
	core.set_position(0, 0.0, 0.0)
	core.set_position(1, 3.0, 4.0)
	assert_almost_eq(core.distance_between(0, 1), 5.0, 0.0001, "3-4-5 平面距离")


func test_core_position_out_of_bounds_is_ignored() -> void:
	var core := SimCore.from_npc(SEED, NPC, ConfigLoader.new().load_all())
	var me := int(core.node_count()) - 1
	core.set_position(me, 1.0, 2.0)
	core.set_position(me + 99, 9.0, 9.0)
	core.set_position(-1, 9.0, 9.0)
	assert_eq(core.position_of(me), Vector2(1.0, 2.0), "越界写入不应改变任何位置")


func test_core_is_busy() -> void:
	var core := SimCore.from_npc(SEED, NPC, ConfigLoader.new().load_all())
	var me := int(core.node_count()) - 1
	assert_false(core.is_busy(me), "开局玩家不忙")
	var busy_until: Array = core._busy_until
	busy_until[me] = int(core._global_tick) + 5
	core._busy_until = busy_until
	assert_true(core.is_busy(me), "busy_until 推到未来 → 忙")
