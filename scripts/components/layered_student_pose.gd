extends Node3D
## Pure presentation: one continuous pose texture supplies body and desk-side arms.

var _settings: Dictionary
var _binding: Dictionary
var _pose := "stand"
var _textures: Dictionary = {}
var _camera_transform := Transform3D.IDENTITY
var _projection := Vector3.ZERO
var _seat_transform := Transform3D.IDENTITY
var _hit_image: Image


func configure(settings: Dictionary, binding: Dictionary) -> void:
	_settings = settings.duplicate(true)
	_settings.merge(binding.get("layout", {}), true)
	_binding = binding
	_pose = "stand"
	_hit_image = null
	_textures.clear()
	for key in ["study", "idle"]:
		if binding.has(key):
			_textures[key] = load(str(binding[key])) as Texture2D
	visible = false


func pose_for(activity: String, kind: String, at_home: bool, moving: bool, present: bool) -> String:
	if not present or moving or not at_home:
		return "stand"
	if activity == "study" or (activity.is_empty() and kind == "class"):
		return "study"
	return "idle" if activity.is_empty() and _binding.has("idle") else "stand"


func show_pose(value: String) -> void:
	visible = value != "stand"
	if not visible or value == _pose:
		return
	_pose = value
	_hit_image = null
	var texture: Texture2D = _textures[value]
	_build_body(texture)
	_build_foreground(texture)
	_update_foreground()
	get_node("Foreground").visible = value == "study"


func _build_body(texture: Texture2D) -> void:
	var split := float(_settings["split_y"])
	var pixel := float(_settings["pixel_size"])
	var lower_height := (
		(texture.get_height() - split) * pixel + float(_settings["lower_height_gain"])
	)
	var bottom := float(_settings["floor_y"]) + lower_height
	var upper_height := split * pixel + float(_settings["upper_height_gain"])
	var upper := get_node("Upper") as Sprite3D
	var lower := get_node("Lower") as Sprite3D
	_set_sprite(upper, texture, Rect2(0, 0, texture.get_width(), split))
	_set_sprite(lower, texture, Rect2(0, split, texture.get_width(), texture.get_height() - split))
	upper.scale.y = upper_height / (split * pixel)
	lower.scale.y = lower_height / ((texture.get_height() - split) * pixel)
	upper.position = Vector3(0, bottom + upper_height * 0.5, _settings["body_depth"])
	lower.position = Vector3(0, bottom - lower_height * 0.5, _settings["body_depth"])


func _set_sprite(sprite: Sprite3D, texture: Texture2D, region: Rect2) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	sprite.texture = atlas
	sprite.pixel_size = float(_settings["pixel_size"])
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = float(_settings["alpha_threshold"])
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_foreground(texture: Texture2D) -> void:
	var foreground := get_node("Foreground")
	for child in foreground.get_children():
		foreground.remove_child(child)
		child.free()
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = float(_settings["alpha_threshold"])
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	for outline in _settings["foreground_polygons"]:
		var part := MeshInstance3D.new()
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.set_meta("outline", outline)
		foreground.add_child(part)


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _pose != "study":
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var projection := Vector3(camera.projection, camera.fov, camera.size)
	if (
		camera.global_transform != _camera_transform
		or projection != _projection
		or global_transform != _seat_transform
	):
		_update_foreground()


func _update_foreground() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _pose != "study":
		return
	_camera_transform = camera.global_transform
	_seat_transform = global_transform
	_projection = Vector3(camera.projection, camera.fov, camera.size)
	var texture: Texture2D = _textures[_pose]
	for part in get_node("Foreground").get_children():
		var pixels := PackedVector2Array()
		var vertices := PackedVector3Array()
		var uv := PackedVector2Array()
		for point in part.get_meta("outline"):
			var pixel := Vector2(point[0], point[1])
			pixels.append(pixel)
			vertices.append(_foreground_vertex(pixel, texture, camera))
			uv.append(pixel / Vector2(texture.get_size()))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = Geometry2D.triangulate_polygon(pixels)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		part.mesh = mesh


func _foreground_vertex(pixel: Vector2, texture: Texture2D, camera: Camera3D) -> Vector3:
	var upper := get_node("Upper") as Sprite3D
	var split := float(_settings["split_y"])
	var size := float(_settings["pixel_size"])
	var upper_bottom := upper.position.y - split * size * upper.scale.y * 0.5
	var vertex := Vector3(
		(pixel.x - texture.get_width() * 0.5) * size,
		upper_bottom + (split - pixel.y) * size * upper.scale.y,
		_settings["body_depth"]
	)
	# Move along the viewing ray, preserving exact screen alignment with the body.
	var ray := vertex - to_local(camera.global_position)
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		ray = global_basis.inverse() * camera.global_basis.z
	if not is_zero_approx(ray.z):
		vertex += ray * ((float(_settings["foreground_depth"]) - vertex.z) / ray.z)
	return vertex


func ray_hit(origin: Vector3, direction: Vector3) -> float:
	if not is_visible_in_tree():
		return INF
	var local_origin := to_local(origin)
	var local_direction := global_basis.inverse() * direction
	if is_zero_approx(local_direction.z):
		return INF
	var texture: Texture2D = _textures[_pose]
	var nearest := INF
	for node_name in ["Upper", "Lower"]:
		var sprite := get_node(node_name) as Sprite3D
		var distance := (sprite.position.z - local_origin.z) / local_direction.z
		if distance < 0:
			continue
		var point := local_origin + local_direction * distance
		var atlas := sprite.texture as AtlasTexture
		var relative := (point - sprite.position) / sprite.scale
		var pixel := Vector2(relative.x, -relative.y) / sprite.pixel_size + atlas.region.size * 0.5
		if Rect2(Vector2.ZERO, atlas.region.size).has_point(pixel):
			if _opaque(pixel + atlas.region.position):
				nearest = minf(nearest, (to_global(point) - origin).length())
	if _pose == "study":
		_process(0.0)
		for part in get_node("Foreground").get_children():
			var arrays: Array = part.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for offset in range(0, indices.size(), 3):
				var a := vertices[indices[offset]]
				var b := vertices[indices[offset + 1]]
				var c := vertices[indices[offset + 2]]
				var point: Variant = Geometry3D.ray_intersects_triangle(
					local_origin, local_direction, a, b, c
				)
				if point == null:
					continue
				var bary := _barycentric(point, a, b, c)
				var sample := (
					uv[indices[offset]] * bary.x
					+ uv[indices[offset + 1]] * bary.y
					+ uv[indices[offset + 2]] * bary.z
				)
				if _opaque(sample * Vector2(texture.get_size())):
					nearest = minf(nearest, (to_global(point) - origin).length())
	return nearest


func _opaque(pixel: Vector2) -> bool:
	if _hit_image == null:
		_hit_image = (_textures[_pose] as Texture2D).get_image()
		if _hit_image.is_compressed():
			_hit_image.decompress()
	var bounds := Rect2(Vector2.ZERO, _hit_image.get_size())
	return (
		bounds.has_point(pixel)
		and (
			_hit_image.get_pixel(int(pixel.x), int(pixel.y)).a
			>= float(_settings["alpha_threshold"])
		)
	)


func _barycentric(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var denominator := ab.dot(ab) * ac.dot(ac) - ab.dot(ac) * ab.dot(ac)
	var v := (ac.dot(ac) * ap.dot(ab) - ab.dot(ac) * ap.dot(ac)) / denominator
	var w := (ab.dot(ab) * ap.dot(ac) - ab.dot(ac) * ap.dot(ab)) / denominator
	return Vector3(1.0 - v - w, v, w)
