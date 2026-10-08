extends GutTest
## 导航配置一致性：**data ↔ 烘焙产物 ↔ 场景**三方必须一致。
##
## 为什么值得单独一条门：烘焙参数与 data/rules/movement.csv 一旦漂移，后果是**静默的** ——
## 例如把 agent_max_climb 调到桌椅阻挡盒高度以上，Recast 就会把桌顶面与地面判为连通，
## 人物"沿导航走上桌子"，而没有任何报错。
##
## 依据：AGENTS.md（数值集中：任何增量 / 阈值 / 系数放 data）、主文档 §10.4。

const MOVEMENT_TABLE := "rules/movement"
const NAV_PATH := "res://resources/navigation/classroom_nav.tres"
const SCENE_PATH := "res://scenes/game/classroom3D.tscn"
const DESK_PATH := "res://scenes/components/desk_chair.tscn"
## 桌面实际高度（米）：阻挡盒不得低于它，否则 0.8 的盒会穿进桌面
const DESK_TOP_HEIGHT := 0.74


func _values() -> Dictionary:
	var out := {}
	for row in ConfigLoader.new().get_table(MOVEMENT_TABLE).get("rows", []):
		out[str(row.get("param", ""))] = float(str(row.get("value", "0")))
	return out


func test_baked_navmesh_matches_movement_table() -> void:
	assert_true(ResourceLoader.exists(NAV_PATH), "烘焙产物存在（先跑 tools/bake_classroom_nav.gd）")
	var nav := load(NAV_PATH) as NavigationMesh
	var values := _values()
	assert_almost_eq(nav.agent_radius, float(values["player_radius"]), 0.0001, "agent_radius = player_radius")
	assert_almost_eq(nav.cell_size, float(values["nav_cell_size"]), 0.0001, "cell_size = nav_cell_size")
	assert_almost_eq(nav.agent_height, float(values["nav_agent_height"]), 0.0001, "agent_height = nav_agent_height")
	assert_almost_eq(nav.agent_max_climb, float(values["nav_max_climb"]), 0.0001, "agent_max_climb = nav_max_climb")
	assert_gt(nav.get_polygon_count(), 0, "烘焙产物非空")


func test_climb_stays_below_blocker_height() -> void:
	var values := _values()
	assert_gt(
		float(values["nav_blocker_height"]),
		float(values["nav_max_climb"]),
		"桌椅阻挡盒必须高于 agent_max_climb（否则桌顶面与地面连通）"
	)
	assert_gt(
		float(values["nav_blocker_height"]), DESK_TOP_HEIGHT, "阻挡盒不得低于桌面实际高度（0.74 米）"
	)


func test_desk_component_exposes_nav_geometry_and_spots() -> void:
	var desk: Node3D = (load(DESK_PATH) as PackedScene).instantiate()
	var shape := desk.get_node_or_null("NavBlocker/Blocker") as CollisionShape3D
	assert_not_null(shape, "课桌组件有 NavBlocker/Blocker（导航阻挡）")
	if shape != null:
		var box := shape.shape as BoxShape3D
		assert_not_null(box, "阻挡体是 BoxShape3D")
		if box != null:
			assert_almost_eq(
				box.size.y, float(_values()["nav_blocker_height"]), 0.0001, "阻挡盒高度 = nav_blocker_height"
			)
	var stand := desk.get_node_or_null("StandSpot") as Node3D
	assert_not_null(stand, "座位有可走站位 StandSpot（落位与站位唯一来源）")
	if stand != null:
		assert_almost_eq(stand.position.z, -0.8, 0.0001, "StandSpot 在行间过道中心（z = -0.8）")
	assert_not_null(desk.get_node_or_null("SitPoint"), "座位有坐姿锚点 SitPoint（坐下帧动画预留）")
	desk.free()


func test_classroom_scene_wires_region_and_floor_geometry() -> void:
	var room: Node3D = (load(SCENE_PATH) as PackedScene).instantiate()
	var region := room.get_node_or_null("Navigation") as NavigationRegion3D
	assert_not_null(region, "教室有 NavigationRegion3D")
	if region != null:
		assert_not_null(region.navigation_mesh, "区域挂了 NavigationMesh")
		if region.navigation_mesh != null:
			assert_eq(
				region.navigation_mesh.resource_path, NAV_PATH, "区域引用的是烘焙产物，不是内嵌空网格"
			)
	assert_not_null(room.get_node_or_null("NavGeometry/FloorShape/Shape"), "教室有导航地板几何")
	assert_true(
		room.get_node("NavGeometry").is_in_group("nav_geometry"), "NavGeometry 在 nav_geometry 组里"
	)
	room.free()
