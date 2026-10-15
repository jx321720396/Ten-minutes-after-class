extends RefCounted
## Refine only clicks that actually intersect a seated pose. Other picks keep their old path.


static func pick(
	poses: Dictionary,
	actors: Array[Node3D],
	camera: Camera3D,
	origin: Vector3,
	direction: Vector3,
	blocker_layer: int,
	limit: float
) -> Dictionary:
	var nearest := INF
	var selected := -1
	for index in poses:
		var distance: float = poses[index].ray_hit(origin, direction)
		if distance < nearest and distance <= limit:
			nearest = distance
			selected = int(index)
	if poses.is_empty():
		return {"handled": false}
	for index in range(actors.size()):
		var sprite := actors[index].get_node_or_null("Sprite") as Sprite3D
		if sprite == null or not sprite.is_visible_in_tree():
			continue
		var distance := _standing_hit(sprite, camera, origin, direction)
		if distance < nearest:
			nearest = distance
			selected = index
	if selected < 0:
		return {"handled": true, "index": -1}
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * nearest, blocker_layer
	)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	return {"handled": true, "index": selected if hit.is_empty() else -1}


static func _standing_hit(
	sprite: Sprite3D, camera: Camera3D, origin: Vector3, direction: Vector3
) -> float:
	var right := Vector3(camera.global_basis.x.x, 0, camera.global_basis.x.z).normalized()
	var normal := right.cross(Vector3.UP)
	var point: Variant = Plane(normal, sprite.global_position).intersects_ray(origin, direction)
	if point == null:
		return INF
	var relative: Vector3 = point - sprite.global_position
	var size := Vector2(sprite.texture.get_size())
	var pixel := Vector2(relative.dot(right), -relative.y) / sprite.pixel_size + size * 0.5
	if not Rect2(Vector2.ZERO, size).has_point(pixel):
		return INF
	if sprite.flip_h:
		pixel.x = size.x - pixel.x - 1
	if sprite.flip_v:
		pixel.y = size.y - pixel.y - 1
	var image := sprite.texture.get_image()
	if image.is_compressed():
		image.decompress()
	if image.get_pixel(int(pixel.x), int(pixel.y)).a < sprite.alpha_scissor_threshold:
		return INF
	return (point - origin).length()
