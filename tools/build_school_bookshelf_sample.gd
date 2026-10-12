extends SceneTree
## 离线建模：由 data/ 生成烘焙桌椅组件与展示场景，不修改现有 .tres 或玩法场景。

const CONFIG := "res://data/ui/school_bookshelf_sample.json"
const SAMPLE := "res://scenes/components/school_bookshelf_sample.tscn"
const SHOWROOM := "res://scenes/game/school_bookshelf_sample_showroom.tscn"

var _data: Dictionary
var _materials: Dictionary = {}


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	_data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	for key in _data["materials"]:
		var definition: Dictionary = _data["materials"][key]
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(str(definition["color"]))
		material.roughness = float(definition["roughness"])
		material.metallic = float(definition.get("metallic", 0.0))
		if definition.has("texture"):
			material.albedo_texture = load(str(definition["texture"]))
			material.uv1_triplanar = true
			material.uv1_scale = _v(definition["uv_scale"])
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_materials[key] = material
	var sample := Node3D.new()
	sample.name = "SchoolBookshelfSample"
	for definition in _data["parts"]:
		_add_part(sample, definition)
	_own_children(sample, sample)
	var error := _save(sample, SAMPLE)
	sample.free()
	if error != OK:
		quit(error)
		return
	_build_showroom()
	print("saved ", SAMPLE, " and ", SHOWROOM)
	quit()


func _add_part(parent: Node3D, definition: Dictionary) -> void:
	var kind := str(definition["kind"])
	if kind == "pipe":
		_add_pipe(parent, definition)
		return
	var mesh: Mesh
	match kind:
		"panel":
			mesh = _panel(definition)
		"leaf":
			var leaf := SphereMesh.new()
			leaf.radius = 0.5
			leaf.height = 1.0
			leaf.radial_segments = int(_data["quality"]["joint_segments"])
			leaf.rings = int(_data["quality"]["joint_rings"])
			mesh = leaf
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = float(definition["radius"])
			cylinder.bottom_radius = cylinder.top_radius
			cylinder.height = float(definition["height"])
			cylinder.radial_segments = int(_data["quality"]["tube_segments"])
			cylinder.rings = 1
			mesh = cylinder
		_:
			var box := BoxMesh.new()
			box.size = _v(definition["size"])
			mesh = box
	var instance := _mesh(parent, str(definition["name"]), mesh, str(definition["material"]))
	if kind == "leaf":
		instance.scale = _v(definition["size"])
	instance.position = _v(definition["position"])
	instance.rotation_degrees = _v(definition.get("rotation", [0, 0, 0]))


func _add_pipe(parent: Node3D, definition: Dictionary) -> void:
	var points: Array = definition["points"]
	var radius := float(definition["radius"])
	var group := Node3D.new()
	group.name = str(definition["name"])
	parent.add_child(group)
	for index in range(points.size() - 1):
		var start := _v(points[index])
		var end := _v(points[index + 1])
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = start.distance_to(end)
		cylinder.radial_segments = int(_data["quality"]["tube_segments"])
		cylinder.rings = 1
		var instance := _mesh(group, "Tube%d" % index, cylinder, str(definition["material"]))
		instance.position = (start + end) * 0.5
		instance.basis = Basis(Quaternion(Vector3.UP, (end - start).normalized()))
	for index in range(points.size()):
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = int(_data["quality"]["joint_segments"])
		sphere.rings = int(_data["quality"]["joint_rings"])
		var joint := _mesh(group, "Joint%d" % index, sphere, str(definition["material"]))
		joint.position = _v(points[index])


func _panel(definition: Dictionary) -> ArrayMesh:
	var size := _v(definition["size"])
	var bevel := float(definition["bevel"])
	var radius := float(definition["corner_radius"])
	var curve := float(definition.get("curve", 0.0))
	var rings: Array = []
	var normals: Array = []
	var settings := [
		[-size.y * 0.5, bevel, -1.0],
		[-size.y * 0.5 + bevel, 0.0, 0.0],
		[size.y * 0.5 - bevel, 0.0, 0.0],
		[size.y * 0.5, bevel, 1.0]
	]
	for setting in settings:
		var vertices: Array[Vector3] = []
		var directions: Array[Vector3] = []
		var centers := [
			Vector2(size.x * 0.5 - radius, size.z * 0.5 - radius),
			Vector2(-size.x * 0.5 + radius, size.z * 0.5 - radius),
			Vector2(-size.x * 0.5 + radius, -size.z * 0.5 + radius),
			Vector2(size.x * 0.5 - radius, -size.z * 0.5 + radius)
		]
		for corner in range(centers.size()):
			var steps := int(_data["quality"]["corner_segments"])
			for step in range(steps + 1):
				var angle := (float(corner) + float(step) / steps) * PI * 0.5
				var point: Vector2 = (
					centers[corner] + Vector2(cos(angle), sin(angle)) * (radius - float(setting[1]))
				)
				var vertex := Vector3(point.x, float(setting[0]), point.y)
				vertex.y += curve * pow(vertex.x / (size.x * 0.5), 2.0)
				vertices.append(vertex)
				var direction := Vector3(cos(angle), float(setting[2]), sin(angle)).normalized()
				# 弧面法线使用变形的逆转置，避免椅背看起来仍是平板。
				var slope := curve * 2.0 * vertex.x / pow(size.x * 0.5, 2.0)
				direction.x -= slope * direction.y
				directions.append(direction.normalized())
		rings.append(vertices)
		normals.append(directions)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = rings[0].size()
	for ring in range(rings.size() - 1):
		for index in range(count):
			var next := (index + 1) % count
			_emit(surface, rings[ring][index], normals[ring][index])
			_emit(surface, rings[ring][next], normals[ring][next])
			_emit(surface, rings[ring + 1][index], normals[ring + 1][index])
			_emit(surface, rings[ring][next], normals[ring][next])
			_emit(surface, rings[ring + 1][next], normals[ring + 1][next])
			_emit(surface, rings[ring + 1][index], normals[ring + 1][index])
	for side in [0, rings.size() - 1]:
		var direction := Vector3.DOWN if side == 0 else Vector3.UP
		for index in range(count):
			var next := (index + 1) % count
			var center := Vector3(0.0, float(settings[side][0]), 0.0)
			_emit(surface, center, direction)
			_emit(surface, rings[side][next if side == 0 else index], direction)
			_emit(surface, rings[side][index if side == 0 else next], direction)
	return surface.commit()


func _emit(surface: SurfaceTool, vertex: Vector3, normal: Vector3) -> void:
	surface.set_normal(normal)
	surface.set_uv(Vector2(vertex.x, vertex.z))
	surface.add_vertex(vertex)


func _mesh(parent: Node3D, mesh_name: String, mesh: Mesh, material_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = _materials[material_name]
	parent.add_child(instance)
	return instance


func _build_showroom() -> void:
	var showroom := Node3D.new()
	showroom.name = "SchoolBookshelfShowroom"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(_data["showroom"]["camera_size"])
	camera.current = true
	showroom.add_child(camera)
	camera.position = _v(_data["showroom"]["camera_position"])
	camera.look_at_from_position(camera.position, _v(_data["showroom"]["camera_target"]))
	var environment_node := WorldEnvironment.new()
	environment_node.environment = Environment.new()
	environment_node.environment.background_mode = Environment.BG_COLOR
	environment_node.environment.background_color = Color(str(_data["showroom"]["background"]))
	environment_node.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_node.environment.ambient_light_color = Color(
		str(_data["showroom"]["ambient_color"])
	)
	environment_node.environment.ambient_light_energy = float(_data["showroom"]["ambient_energy"])
	showroom.add_child(environment_node)
	for definition in _data["showroom"]["lights"]:
		var light := DirectionalLight3D.new()
		light.name = str(definition["name"])
		light.rotation_degrees = _v(definition["rotation"])
		light.light_color = Color(str(definition["color"]))
		light.light_energy = float(definition["energy"])
		light.shadow_enabled = bool(definition["shadows"])
		showroom.add_child(light)
	var ground := PlaneMesh.new()
	ground.size = Vector2(
		float(_data["showroom"]["ground_size"]), float(_data["showroom"]["ground_size"])
	)
	_mesh(showroom, "Ground", ground, "ground")
	for definition in _data["showroom"]["models"]:
		var furniture: Node3D = load(str(definition["scene"])).instantiate()
		furniture.name = str(definition["name"])
		furniture.position = _v(definition["position"])
		furniture.rotation_degrees = _v(definition["rotation"])
		showroom.add_child(furniture)
	_own_children(showroom, showroom)
	_save(showroom, SHOWROOM)
	showroom.free()


func _own_children(parent: Node, owner_node: Node) -> void:
	for child in parent.get_children():
		child.owner = owner_node
		# 展示场景引用组件实例；组件内部的 owner 仍归组件根节点。
		if child.scene_file_path.is_empty():
			_own_children(child, owner_node)


func _save(node: Node, path: String) -> Error:
	var packed := PackedScene.new()
	var error := packed.pack(node)
	if error != OK:
		return error
	return ResourceSaver.save(packed, path)


func _v(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
