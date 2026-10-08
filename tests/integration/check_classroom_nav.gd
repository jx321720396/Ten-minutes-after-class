extends SceneTree
## 教室导航验收（**连通性**，不是覆盖率）。
##
## 运行：
##   godot --headless --path . --script tests/integration/check_classroom_nav.gd
##
## 为什么不能只查「离最近的导航面多近」：那只证明**覆盖** —— 一块孤岛面离目标也可能只有几厘米。
## 这里查三件事：
##   1. 公共起点到每个座位入口（StandSpot）与每个站立点**真的有路径**，且路径末点落在目标上；
##   2. 桌椅阻挡盒**真的不可走**（桌中心到导航面的最小距离 ≥ 阈值）—— 否则人物会穿桌 / 走上桌子；
##   3. 导航面高度落在合理范围（防止烘焙把面抬到天花板高度）。
##
## 失败时退出码为 1，可直接接进 CI。

const SCENE_PATH := "res://scenes/game/classroom3D.tscn"
const START_POINT := "PODIUM_LEFT"
## 路径末点与目标的允许偏差（米）：略大于烘焙 cell_size，但远小于「落在孤岛面」的偏差
const ARRIVE_TOLERANCE := 0.15
## 桌中心到导航面的最小允许距离（米）：桌椅必须是不可走区
const DESK_PROBE_MIN_DISTANCE := 0.2
## 导航面高度上限（米）：高过它说明烘焙把面抬到了桌面 / 天花板上
const HEIGHT_SANITY_LIMIT := 1.0
const MAX_WAIT_FRAMES := 180
## 探针与导航面的允许距离（米）：只用于"地图上有没有面"的判定
const READY_TOLERANCE := 0.5
## 连续多少帧探针成功才算地图稳定：跨过「region 已加入、多边形未提交」的中间态
const STABLE_FRAMES := 3

var _failures: Array[String] = []
var _lines: Array[String] = []
var _worst_arrive := 0.0
var _worst_desk := 99.0


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("载入 %s 失败" % SCENE_PATH)
		_finish()
		return
	var room: Node3D = packed.instantiate()
	root.add_child(room)
	# 先等一帧：add_child 之后立刻读子节点的 global_position 会拿到 (0,0)
	await process_frame
	var map := root.world_3d.navigation_map
	var start_node := room.get_node_or_null("StandPoints/%s" % START_POINT) as Node3D
	if start_node == null:
		_fail("找不到公共起点 StandPoints/%s" % START_POINT)
		_finish()
		return
	var origin := start_node.global_position
	if not await _wait_map(map, origin):
		_fail("导航地图未同步 —— NavigationRegion3D 是否已烘焙？（先跑 tools/bake_classroom_nav.gd）")
		_finish()
		return
	_lines.append("公共起点 %s = (%.2f, %.2f)" % [START_POINT, origin.x, origin.z])
	_check_height(map, origin)
	_check_reachable(map, origin, room)
	_check_desks_excluded(map, room)
	_finish()


func _wait_map(map: RID, probe: Vector3) -> bool:
	var stable := 0
	for _i in range(MAX_WAIT_FRAMES):
		if _has_surface(map, probe):
			stable += 1
			if stable >= STABLE_FRAMES:
				return true
		else:
			stable = 0
		await physics_frame
	return false


## 探针处能否吸附到导航面（只证明"地图上有面"，不证明连通）。
func _has_surface(map: RID, probe: Vector3) -> bool:
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= 0:
		return false
	var flat := Vector3(probe.x, 0.0, probe.z)
	var nearest := NavigationServer3D.map_get_closest_point(map, flat)
	return Vector2(nearest.x - flat.x, nearest.z - flat.z).length() <= READY_TOLERANCE


## 导航面高度：所有查询点都落在同一平面附近，且不能高过桌面。
func _check_height(map: RID, origin: Vector3) -> void:
	var probe := NavigationServer3D.map_get_closest_point(map, Vector3(origin.x, 0.0, origin.z))
	_lines.append("起点处导航面高度 y = %.3f" % probe.y)
	if probe.y < -0.5 or probe.y > HEIGHT_SANITY_LIMIT:
		_fail("导航面高度异常（y = %.3f）—— 烘焙把可行走面抬错了" % probe.y)


## 连通性：从公共起点到每个座位入口 / 站立点都必须有路径，且末点落在目标上。
func _check_reachable(map: RID, origin: Vector3, room: Node3D) -> void:
	var reachable := 0
	var total := 0
	var seats := room.get_node_or_null("Seats")
	if seats == null:
		_fail("场景里找不到 Seats")
	else:
		for seat in seats.get_children():
			var spot := seat.get_node_or_null("StandSpot") as Node3D
			if spot == null:
				_fail("%s 缺 StandSpot（座位入口）" % seat.name)
				continue
			total += 1
			if _reachable(map, origin, spot.global_position, "%s/StandSpot" % seat.name):
				reachable += 1
	var stands := room.get_node_or_null("StandPoints")
	if stands == null:
		_fail("场景里找不到 StandPoints")
	else:
		for child in stands.get_children():
			var node := child as Node3D
			if node == null:
				continue
			total += 1
			if _reachable(map, origin, node.global_position, "StandPoints/%s" % child.name):
				reachable += 1
	_lines.append("可达目标：%d / %d（最大末点偏差 %.3f m）" % [reachable, total, _worst_arrive])
	if reachable != total:
		_fail("有 %d 个目标走不过去" % (total - reachable))


func _reachable(map: RID, origin: Vector3, target: Vector3, label: String) -> bool:
	var path := NavigationServer3D.map_get_path(map, origin, target, true)
	if path.is_empty():
		_fail("%s：没有路径" % label)
		return false
	var end: Vector3 = path[path.size() - 1]
	var missing := Vector2(end.x - target.x, end.z - target.z).length()
	_worst_arrive = maxf(_worst_arrive, missing)
	if missing > ARRIVE_TOLERANCE:
		_fail("%s：路径末点偏离 %.3f m（不可达，或落在孤岛面上）" % [label, missing])
		return false
	return true


## 桌椅必须是不可走区：桌中心到最近导航面的距离不能太小。
func _check_desks_excluded(map: RID, room: Node3D) -> void:
	var seats := room.get_node_or_null("Seats")
	if seats == null:
		return
	var probed := 0
	for seat in seats.get_children():
		var blocker := seat.get_node_or_null("NavBlocker") as Node3D
		if blocker == null:
			_fail("%s 缺 NavBlocker（桌椅导航阻挡）" % seat.name)
			continue
		var probe := blocker.global_position
		var nearest := NavigationServer3D.map_get_closest_point(map, probe)
		var distance := Vector2(nearest.x - probe.x, nearest.z - probe.z).length()
		_worst_desk = minf(_worst_desk, distance)
		probed += 1
	_lines.append("桌椅不可走：探测 %d 处，桌中心到导航面最小距离 %.3f m" % [probed, _worst_desk])
	if probed == 0:
		_fail("没有任何桌椅阻挡盒可探测")
		return
	if _worst_desk < DESK_PROBE_MIN_DISTANCE:
		_fail(
			(
				"桌椅阻挡失效：桌中心距导航面只有 %.3f m（应 ≥ %.2f）—— 人物会穿桌"
				% [_worst_desk, DESK_PROBE_MIN_DISTANCE]
			)
		)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	var out: Array[String] = _lines.duplicate()
	if _failures.is_empty():
		out.append("✓ 导航验收全部通过")
	else:
		for failure in _failures:
			out.append("✗ %s" % failure)
	print("=== check_classroom_nav ===")
	print("\n".join(out))
	print("=== %s ===" % ("通过" if _failures.is_empty() else "失败 %d 项" % _failures.size()))
	quit(0 if _failures.is_empty() else 1)
