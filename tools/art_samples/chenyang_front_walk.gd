extends "res://tools/art_samples/chenyang_soft_mesh.gd"
## Isolated frontal gait probe. Uses the approved continuous character texture.

var gait: Dictionary


func _ready() -> void:
	gait = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/samples/chenyang_front_walk.json")
	)
	super._ready()


func travel_at(time: float) -> float:
	return time * gait.foot_travel / (gait.period * gait.stance_fraction)


## x = foot depth relative to moving root; y = sole lift above floor.
func foot_at(side: float, time: float) -> Vector2:
	var phase := fposmod(time / gait.period + (0.5 if side > 0.0 else 0.0), 1.0)
	if phase < gait.stance_fraction:
		return Vector2(gait.foot_travel * (0.5 - phase / gait.stance_fraction), 0)
	var swing: float = (phase - gait.stance_fraction) / (1.0 - gait.stance_fraction)
	var ease := swing * swing * (3.0 - 2.0 * swing)
	return Vector2(gait.foot_travel * (ease - 0.5), sin(swing * PI) * gait.foot_lift)


func set_sample_pose(mode: String, time: float) -> void:
	if mode != "walk":
		super.set_sample_pose(mode, time)
		return
	var cycle: float = time / gait.period * TAU
	var bob: float = -gait.body_bob * (1.0 - cos(cycle * 2.0))
	var sway: float = sin(cycle) * gait.body_sway
	var vertices := PackedVector3Array()
	for point in _source:
		var side := -1.0 if point.x < 0.0 else 1.0
		var foot := foot_at(side, time)
		var opposite := foot_at(-side, time)
		var result := point
		var knee_lift: float = foot.y * 0.45 + bob * 0.4
		var knee_depth: float = foot.x * 0.5 + foot.y / gait.foot_lift * gait.knee_lead
		if point.y < gait.ankle_y:
			result.y += foot.y
			result.z = foot.x
		elif point.y < gait.knee_y:
			var lower: float = (point.y - gait.ankle_y) / (gait.knee_y - gait.ankle_y)
			result.y += lerpf(foot.y, knee_lift, lower)
			result.z = lerpf(foot.x, knee_depth, lower)
		elif point.y < gait.hip_y:
			var upper: float = (point.y - gait.knee_y) / (gait.hip_y - gait.knee_y)
			result.y += lerpf(knee_lift, bob, upper)
			result.z = lerpf(knee_depth, 0.0, upper)
		else:
			result.y += bob
		result.x += sway * smoothstep(gait.ankle_y, gait.hip_y, point.y)
		var arm := smoothstep(settings.arm_boundary[0], settings.arm_boundary[1], absf(point.x))
		arm *= smoothstep(settings.arm_bottom[0], settings.arm_bottom[1], point.y)
		arm *= 1.0 - smoothstep(settings.arm_top[0], settings.arm_top[1], point.y)
		var drop := clampf((settings.shoulder[1] - point.y) / gait.arm_drop_length, 0.0, 1.0)
		var swing: float = opposite.x / (gait.foot_travel * 0.5)
		result.z = lerpf(result.z, swing * gait.arm_depth * drop, arm)
		result.x += side * absf(swing) * gait.arm_out * drop * arm
		result.y += absf(swing) * gait.arm_lift * drop * arm
		assert(result.is_finite())
		vertices.append(result)
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
