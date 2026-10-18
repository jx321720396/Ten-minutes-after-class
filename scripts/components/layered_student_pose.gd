extends Node3D
## Pure presentation: one continuous pose texture supplies body and desk-side arms.

var _settings: Dictionary
var _base_settings: Dictionary
var _binding: Dictionary
var _pose := "stand"
var _requested_pose := "stand"
var _group_back := false
var _seat: Node3D

## 已应用的贴图（pose → Texture2D）；读盘由 AssetPreloader 在后台完成。
var _textures: Dictionary = {}
## pose → 贴图路径（configure 时登记，不读盘）。
var _texture_paths: Dictionary = {}
var _camera_transform := Transform3D.IDENTITY
var _projection := Vector3.ZERO
var _seat_transform := Transform3D.IDENTITY
var _hit_image: Image


func bind_seat(seat: Node3D) -> void:
	if _seat == seat:
		return
	_seat = seat
	_pose = "stand"


func configure(settings: Dictionary, binding: Dictionary) -> void:
	_settings = settings.duplicate(true)
	_settings.merge(binding.get("layout", {}), true)
	_base_settings = _settings.duplicate(true)
	_binding = binding
	_pose = "stand"
	_requested_pose = "stand"
	_group_back = false
	_hit_image = null
	_textures.clear()
	_texture_paths.clear()
	for key in ["study", "idle", "idle_back"]:
		if binding.has(key):
			_texture_paths[key] = str(binding[key])
	AssetPreloader.request_textures(_texture_paths.values())
	visible = false


func pose_for(
	activity: String, _kind: String, at_home: bool, _moving: bool, present: bool
) -> String:
	# Position decides sitting; a queued/blocked walk must not stand someone up at their desk.
	if not present or not at_home:
		return "stand"
	if activity == "study":
		return "study"
	return "idle" if _binding.has("idle") else "stand"


## 应用姿势；返回 false = 贴图仍在后台加载，调用方应保持原表现（下一帧再试）。
## non_blocking=true（游戏内）不等待线程加载；默认阻塞，保持单测与旧的同步语义。
func show_pose(value: String, non_blocking: bool = false) -> bool:
	_requested_pose = value
	if value == "idle" and _group_back and _binding.has("idle_back"):
		value = "idle_back"
	visible = value != "stand"
	if not visible or value == _pose:
		return true
	var path := str(_texture_paths.get(value, ""))
	var texture: Texture2D = (
		null if path.is_empty() else AssetPreloader.texture(path, not non_blocking)
	)
	if texture == null:
		if value == "idle_back" and _pose == "idle":
			return true
		return false
	_pose = value
	_settings = _base_settings.duplicate(true)
	if value == "idle_back":
		_settings.merge(_binding.get("idle_back_layout", {}), true)
	if value in ["idle", "idle_back"] and is_instance_valid(_seat):
		var anchor := _seat.get_node_or_null("SitPoint") as Node3D
		if anchor != null:
			_settings["body_depth"] = _seat.to_local(anchor.global_position).z
		if value == "idle_back":
			var cushion := _seat.get_node_or_null("Chair/Seat") as MeshInstance3D
			if cushion != null:
				var top := _seat.to_local(cushion.to_global(cushion.get_aabb().end)).y
				var split := float(_settings["split_y"])
				var lower := (texture.get_height() - split) * float(_settings["pixel_size"])
				_settings["lower_height_gain"] = top - float(_settings["floor_y"]) - lower
	_textures[value] = texture
	_hit_image = null
	_build_body(texture)
	_build_foreground(texture)
	_update_foreground()
	get_node("Foreground").visible = value == "study"
	return true


func set_group_back(value: bool, non_blocking: bool = true) -> bool:
	_group_back = value
	return show_pose(_requested_pose, non_blocking)


## 坐姿贴图是否已就绪（stand / 未绑定视为就绪）。
func texture_ready(value: String) -> bool:
	if value == "stand":
		return true
	var path := str(_texture_paths.get(value, ""))
	if path.is_empty():
		return true
	return AssetPreloader.is_ready(path)


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
