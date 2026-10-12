extends GutTest
## 桌椅小样的兼容性：烘焙资产独立可用、站位和导航占位与现有组件相同。

const SAMPLE := "res://scenes/components/school_desk_chair_sample.tscn"
const ORIGINAL := "res://scenes/components/desk_chair.tscn"


func test_sample_is_baked_and_keeps_existing_interfaces() -> void:
	assert_true(ResourceLoader.exists(SAMPLE), "小样需要是可直接实例化的正式场景")
	if not ResourceLoader.exists(SAMPLE):
		return
	var sample: Node3D = load(SAMPLE).instantiate()
	var original: Node3D = load(ORIGINAL).instantiate()
	assert_null(sample.get_script(), "正式小样无需运行时建模脚本")
	for path in ["StandSpot", "SitPoint", "NavBlocker/Blocker"]:
		assert_not_null(sample.get_node_or_null(path), "保留接口：" + path)
		assert_eq(sample.get_node(path).transform, original.get_node(path).transform)
	assert_eq(
		sample.get_node("NavBlocker/Blocker").shape.size,
		original.get_node("NavBlocker/Blocker").shape.size
	)
	assert_eq(sample.get_node("Chair").transform, original.get_node("Chair").transform)
	assert_gt(sample.find_children("*", "MeshInstance3D", true, false).size(), 20)
	for node in sample.find_children("*", "MeshInstance3D", true, false):
		assert_not_null(node.mesh, "网格必须已存入场景")
		assert_gt(node.mesh.get_surface_count(), 0)
		var aabb: AABB = node.mesh.get_aabb()
		assert_true(aabb.size.is_finite(), "网格尺寸有限")
		assert_gt(aabb.size.length(), 0.0, "网格非空")
		if node.mesh is ArrayMesh:
			_check_front_face_winding(node.mesh)
	sample.free()
	original.free()


func _check_front_face_winding(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in range(0, vertices.size(), 3):
		var cross := (vertices[index + 1] - vertices[index]).cross(
			vertices[index + 2] - vertices[index]
		)
		var average := normals[index] + normals[index + 1] + normals[index + 2]
		assert_lt(cross.dot(average), 0.0, "Godot 正面必须顺时针，避免桌面被背面剔除")


func test_showroom_uses_sample_without_duplicate_geometry() -> void:
	var showroom: Node3D = load("res://scenes/game/school_desk_sample_showroom.tscn").instantiate()
	var standalone: Node3D = load(SAMPLE).instantiate()
	var embedded := showroom.get_node("Sample")
	assert_eq(
		embedded.find_children("*", "MeshInstance3D", true, false).size(),
		standalone.find_children("*", "MeshInstance3D", true, false).size(),
		"展示场景保留独立组件实例，不重叠几何"
	)
	showroom.free()
	standalone.free()
