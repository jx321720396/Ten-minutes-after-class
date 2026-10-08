extends SceneTree
## 教室导航网格离线烘焙（表现层工具，不参与玩法数值）。
##
## 运行：
##   godot --headless --path . --script tools/bake_classroom_nav.gd
##
## 为什么要有这个工具，而不是在编辑器里手点 Bake：
##   · 烘焙参数（cell / agent / climb）是**唯一数值来源** data/rules/movement.csv，
##     手点一次就会和 data 漂移，而漂移的后果是「人物沿导航走上桌子」这类静默错误；
##   · 产物是可提交资源 resources/navigation/classroom_nav.tres，
##     tests/unit/test_nav_config.gd 会断言「产物参数 == data 值」，改 data 忘了重烘焙就会红。
##
## 几何来源：场景里 groups=["nav_geometry"] 的碰撞体（桌椅阻挡盒 + 地板盒），
## 由 classes（StaticBody3D/CollisionShape3D）解析，**不吃美术 mesh**。

const SCENE_PATH := "res://scenes/game/classroom3D.tscn"
const MOVEMENT_TABLE := "rules/movement"
const OUTPUT_PATH := "res://resources/navigation/classroom_nav.tres"
const REPORT_PATH := "user://bake_nav_report.txt"
const NAV_GROUP := "nav_geometry"
## 报告里判定「疑似桌顶面」的高度阈值（米）：高于它又远离地板的顶点单独点名
const SUSPECT_HEIGHT := 0.5

var _report: Array[String] = []
var _failed := false


func _initialize() -> void:
	var values := _load_values()
	if values.is_empty():
		_fail("读不到 data/rules/%s —— 烘焙中止（不生成半成品资源）" % MOVEMENT_TABLE)
		_finish(1)
		return
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("载入 %s 失败" % SCENE_PATH)
		_finish(1)
		return
	var room: Node3D = packed.instantiate()
	root.add_child(room)
	# 等两帧：实例化的子场景（Seats/*）完成挂组与几何装配
	await process_frame
	await process_frame
	var blockers := _count_group_members(room)
	_report.append("nav_geometry 组成员：%d" % blockers)
	if blockers == 0:
		_fail("场景里没有 nav_geometry 组的几何 —— 请检查 desk_chair.tscn 的 NavBlocker 与 NavGeometry")
		room.queue_free()
		_finish(1)
		return

	var navmesh := _make_navmesh(values)
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, room, _noop)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source, _noop)

	var polygons := navmesh.get_polygon_count()
	var vertices := navmesh.get_vertices()
	_report.append("烘焙结果：顶点 %d / 多边形 %d" % [vertices.size(), polygons])
	if polygons == 0:
		_fail("烘焙结果为空 —— 检查地板盒是否存在、参数是否合理")
		room.queue_free()
		_finish(1)
		return
	_report_bounds(vertices)
	var err := ResourceSaver.save(navmesh, OUTPUT_PATH)
	if err != OK:
		_fail("保存 %s 失败（错误码 %d）" % [OUTPUT_PATH, err])
		room.queue_free()
		_finish(1)
		return
	_report.append("已写出 %s" % OUTPUT_PATH)
	room.queue_free()
	_finish(0)


func _noop() -> void:
	pass


## 烘焙参数：全部来自 data/rules/movement.csv（缺键即失败，不用默认值兜底 —— 兜底会掩盖漂移）。
func _load_values() -> Dictionary:
	var rows: Array = ConfigLoader.new().get_table(MOVEMENT_TABLE).get("rows", [])
	var table := {}
	for row in rows:
		table[str(row.get("param", ""))] = float(str(row.get("value", "0")))
	var wanted := [
		"player_radius", "nav_cell_size", "nav_agent_height", "nav_max_climb", "nav_blocker_height",
	]
	var out := {}
	for key in wanted:
		if not table.has(key) or float(table[key]) <= 0.0:
			_fail("movement.csv 缺参数或值非法：%s" % key)
			return {}
		out[key] = float(table[key])
	if float(out["nav_max_climb"]) >= float(out["nav_blocker_height"]):
		_fail(
			(
				"nav_max_climb（%s）必须小于 nav_blocker_height（%s）—— 否则 Recast 会把桌顶面与地面判为连通"
				% [out["nav_max_climb"], out["nav_blocker_height"]]
			)
		)
		return {}
	return out


func _make_navmesh(values: Dictionary) -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	# 几何来源：只吃 nav_geometry 组的静态碰撞体，不吃美术 mesh（墙板 / 窗帘 / 灯都不参与）
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	navmesh.geometry_source_group_name = NAV_GROUP
	navmesh.cell_size = float(values["nav_cell_size"])
	navmesh.cell_height = float(values["nav_cell_size"])
	navmesh.agent_radius = float(values["player_radius"])
	navmesh.agent_height = float(values["nav_agent_height"])
	navmesh.agent_max_climb = float(values["nav_max_climb"])
	navmesh.agent_max_slope = 45.0
	navmesh.region_min_size = 2.0
	navmesh.region_merge_size = 20.0
	navmesh.edge_max_length = 12.0
	navmesh.edge_max_error = 1.3
	navmesh.vertices_per_polygon = 6.0
	navmesh.detail_sample_distance = 6.0
	navmesh.detail_sample_max_error = 1.0
	return navmesh


func _report_bounds(vertices: PackedVector3Array) -> void:
	var box := AABB()
	for i in range(vertices.size()):
		if i == 0:
			box = AABB(vertices[i], Vector3.ZERO)
		else:
			box = box.expand(vertices[i])
	_report.append(
		(
			"导航面 AABB：x[%.2f, %.2f] y[%.2f, %.2f] z[%.2f, %.2f]"
			% [
				box.position.x, box.end.x,
				box.position.y, box.end.y,
				box.position.z, box.end.z,
			]
		)
	)
	var high := 0
	for v in vertices:
		if v.y > SUSPECT_HEIGHT:
			high += 1
	_report.append(
		"高于 %.1f 米的顶点：%d 个（桌顶面会是孤立面；是否真的不可达由 tests/integration/check_classroom_nav.gd 判定）"
		% [SUSPECT_HEIGHT, high]
	)


func _count_group_members(node: Node) -> int:
	var count := 0
	if node.is_in_group(NAV_GROUP):
		count += 1
	for child in node.get_children():
		count += _count_group_members(child)
	return count


func _fail(message: String) -> void:
	_failed = true
	_report.append("✗ %s" % message)
	push_error("bake_classroom_nav：%s" % message)


func _finish(code: int) -> void:
	var text := "\n".join(_report)
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	print("=== bake_classroom_nav ===")
	print(text)
	print("=== %s ===" % ("失败" if _failed else "完成"))
	quit(code)
