class_name ClassroomArtProps
extends RefCounted
## 纯表现资产组装器：配置定义形状，以共享材质的 MultiMesh 批量绘制；不生成碰撞。

var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _font: Font


func _init(materials: Dictionary, font: Font) -> void:
	_materials = materials
	_font = font


func add_prop(parent: Node3D, definition: Dictionary, placement: Dictionary) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = str(placement["name"])
	parent.add_child(anchor)
	anchor.position = vector(placement.get("position", [0, 0, 0]))
	anchor.rotation_degrees = vector(placement.get("rotation", [0, 0, 0]))
	anchor.scale = vector(placement.get("scale", [1, 1, 1]))
	for part in definition.get("parts", []):
		_add_part(anchor, part)
	for label in definition.get("labels", []):
		_add_label(anchor, label)
	return anchor


func _add_part(anchor: Node3D, part: Dictionary) -> void:
	var kind := str(part.get("kind", "box"))
	var material := str(part["material"])
	var key := kind + ":" + material
	if not _batches.has(key):
		_batches[key] = {"kind": kind, "material": material, "transforms": []}
	var rotation := vector(part.get("rotation", [0, 0, 0])) * PI / 180.0
	var basis := Basis.from_euler(rotation).scaled(vector(part["size"]))
	var transform := Transform3D(basis, vector(part["position"]))
	_batches[key]["transforms"].append(anchor.global_transform * transform)


func _add_label(anchor: Node3D, definition: Dictionary) -> void:
	var label := Label3D.new()
	label.name = str(definition["name"])
	label.font = _font
	label.text = str(definition["text"])
	label.position = vector(definition["position"])
	label.rotation_degrees = vector(definition.get("rotation", [0, 0, 0]))
	label.font_size = int(definition["font_size"])
	label.pixel_size = float(definition["pixel_size"])
	label.modulate = Color(str(definition["color"]))
	label.outline_size = int(definition.get("outline_size", 0))
	label.no_depth_test = false
	label.shaded = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	anchor.add_child(label)


func flush(parent: Node3D) -> void:
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _unit_mesh(str(batch["kind"]))
		multimesh.instance_count = batch["transforms"].size()
		for index in range(multimesh.instance_count):
			multimesh.set_instance_transform(
				index, parent.global_transform.affine_inverse() * batch["transforms"][index]
			)
		var instance := MultiMeshInstance3D.new()
		instance.name = str(key).replace(":", "_")
		instance.multimesh = multimesh
		instance.material_override = _materials[batch["material"]]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)


func _unit_mesh(kind: String) -> Mesh:
	match kind:
		"cylinder":
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.5
			mesh.bottom_radius = 0.5
			mesh.height = 1.0
			mesh.radial_segments = 8
			mesh.rings = 1
			return mesh
		"sphere":
			var mesh := SphereMesh.new()
			mesh.radius = 0.5
			mesh.height = 1.0
			mesh.radial_segments = 8
			mesh.rings = 4
			return mesh
		_:
			var mesh := BoxMesh.new()
			mesh.size = Vector3.ONE
			return mesh


static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
