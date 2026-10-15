extends Node3D
## Continuous-surface art probe: shared vertices keep cloth and joints connected.

const CONFIG := "res://data/ui/samples/chenyang_soft_mesh_sample.json"
var settings: Dictionary
var _source := PackedVector3Array()
var _uv := PackedVector2Array()
var _indices := PackedInt32Array()
var _surface := MeshInstance3D.new()
var _material := StandardMaterial3D.new()


func _ready() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var texture := load(str(settings.texture)) as Texture2D
	var columns: int = settings.grid[0]
	var rows: int = settings.grid[1]
	var pixel: float = settings.height / (settings.floor_pixel - settings.top_pixel)
	for row in range(rows + 1):
		for column in range(columns + 1):
			var uv := Vector2(float(column) / columns, float(row) / rows)
			_uv.append(uv)
			_source.append(
				Vector3(
					(uv.x * texture.get_width() - settings.center_pixel) * pixel,
					(settings.floor_pixel - uv.y * texture.get_height()) * pixel,
					0
				)
			)
	for row in range(rows):
		for column in range(columns):
			var first := row * (columns + 1) + column
			_indices.append_array(
				PackedInt32Array(
					[
						first,
						first + columns + 1,
						first + 1,
						first + 1,
						first + columns + 1,
						first + columns + 2
					]
				)
			)
	_material.albedo_texture = texture
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_material.alpha_scissor_threshold = 0.45
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_surface.material_override = _material
	add_child(_surface)
	set_sample_pose("idle", 0.0)


func set_sample_pose(mode: String, time: float) -> void:
	var pose: Dictionary = settings.poses[mode]
	var phase: float = time * pose.frequency
	var breath: float = sin(phase)
	var vertices := PackedVector3Array()
	for point in _source:
		var result := Vector2(point.x, point.y)
		var side := -1.0 if point.x < 0.0 else 1.0
		var shoulder := Vector2(side * settings.shoulder[0], settings.shoulder[1])
		var elbow := Vector2(side * settings.elbow[0], settings.elbow[1])
		var arm_weight := smoothstep(
			settings.arm_boundary[0], settings.arm_boundary[1], absf(point.x)
		)
		arm_weight *= smoothstep(settings.arm_bottom[0], settings.arm_bottom[1], point.y)
		arm_weight *= 1.0 - smoothstep(settings.arm_top[0], settings.arm_top[1], point.y)
		var active: bool = side < 0.0 and mode == "chat"
		var shoulder_angle := deg_to_rad(
			pose.shoulder_degrees * (0.5 + 0.5 * sin(phase)) if active else 0.0
		)
		var elbow_angle := deg_to_rad(
			pose.elbow_degrees * (0.5 + 0.5 * sin(phase + 0.35)) if active else 0.0
		)
		var lower_weight := (
			1.0 - smoothstep(settings.elbow_blend[0], settings.elbow_blend[1], point.y)
		)
		var arm := result.lerp(_rotate(result, elbow, elbow_angle), lower_weight)
		arm = _rotate(arm, shoulder, shoulder_angle)
		result = result.lerp(arm, arm_weight)
		var upper_weight := smoothstep(settings.breath_zone[0], settings.breath_zone[1], point.y)
		result.x *= 1.0 + breath * pose.breath_width * upper_weight
		result.y += breath * pose.breath_height * upper_weight
		var head_weight := smoothstep(settings.head_blend[0], settings.head_blend[1], point.y)
		var head := _rotate(
			result, Vector2(0, settings.head_pivot), deg_to_rad(sin(phase + .5) * pose.head_degrees)
		)
		result = result.lerp(head, head_weight)
		assert(result.is_finite())
		vertices.append(Vector3(result.x, result.y, 0))
	# Check every shared triangle: deformation must not fold or invert the surface.
	for index in range(0, _indices.size(), 3):
		var a := vertices[_indices[index]]
		var b := vertices[_indices[index + 1]]
		var c := vertices[_indices[index + 2]]
		assert((b - a).cross(c - a).z > 0.0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_surface.mesh = mesh


func _rotate(point: Vector2, pivot: Vector2, angle: float) -> Vector2:
	return pivot + (point - pivot).rotated(angle)
