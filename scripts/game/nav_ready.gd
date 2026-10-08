class_name NavReady
extends RefCounted
## 导航就绪判定与等待（表现层唯一入口）。
##
## ⚠️ 为什么不能只查 `NavigationServer3D.map_get_iteration_id() > 0`：
##   实测（Godot 4.7.2 / 本机无头）：`NavigationRegion3D` 进树后 iteration_id 会先变成 1，
##   但**多边形数据要到下一次迭代才提交** —— 此时 `map_get_path()` 一律返回空数组，
##   表现为"刚进教室那几帧所有人都不走 / 点地面没反应"，很容易被误判成"导航坏了"。
##   所以就绪判定 = 地图有效 + 已同步 + **连续多帧能吸附到导航面上**（而不是只看 iteration）。
##
## 依据：主文档 §10.4（走动）；docs/design/架构总览.md「教室导航」一节。

## 默认最多等多少物理帧（约 3 秒 @60fps）
const DEFAULT_MAX_FRAMES := 180
## 探针与导航面的允许距离（米）：只用于判断「地图上确实有面」，不是精度判定
const READY_TOLERANCE := 0.5
## 导航面高度上限（米）：高于它说明吸附到了桌面 / 天花板上
const HEIGHT_LIMIT := 1.5
## 连续多少帧探针成功才算稳定（跨过「region 已加入但多边形未提交」的中间态）
const STABLE_FRAMES := 3


## 节点所在世界的地图 RID；不在树里返回空 RID。
static func map_of(node: Node3D) -> RID:
	if node == null or not node.is_inside_tree():
		return RID()
	return node.get_world_3d().navigation_map


## 地图此刻可用：有效 + 已同步 + 探针处能吸附到导航面。
static func is_ready(node: Node3D, probe: Vector3) -> bool:
	var map := map_of(node)
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= 0:
		return false
	var flat := Vector3(probe.x, 0.0, probe.z)
	var nearest := NavigationServer3D.map_get_closest_point(map, flat)
	if Vector2(nearest.x - flat.x, nearest.z - flat.z).length() > READY_TOLERANCE:
		return false
	return absf(nearest.y) <= HEIGHT_LIMIT


## 等地图可用（连续 STABLE_FRAMES 帧稳定）；超时返回 false。
## 调用方拿到 false 必须**明确失败**，不许退化成直线走动（见 §10.4：走动不穿家具）。
static func wait(
	node: Node3D, probe: Vector3, max_frames: int = DEFAULT_MAX_FRAMES
) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var stable := 0
	for _i in range(max_frames):
		if is_ready(node, probe):
			stable += 1
			if stable >= STABLE_FRAMES:
				return true
		else:
			stable = 0
		await node.get_tree().physics_frame
	return false


## 沿导航网格取一条折线；地图不可用或查不到路线时返回空数组。
static func query_path(node: Node3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := map_of(node)
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= 0:
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(
		map, Vector3(from.x, from.y, from.z), Vector3(to.x, from.y, to.z), true
	)
