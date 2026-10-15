extends SceneTree
## Read-only runtime snapshot to glTF, for Blender review only.

const OUT = "res://docs/art/concepts/ceiling_preview_20261015/"
var snapshot: Node3D
var counts = {"meshes": 0, "multimesh_instances": 0, "sprites": 0, "lights": 0}

func _initialize():
	call_deferred("capture")

func capture():
	root.get_node("GameState").start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	current_scene = room
	await process_frame
	room.get_node("Clock").hold(&"blender_export")
	room.get_node("ClassroomArt").set_camera_follow_enabled(false)
	for frame in range(12):
		await process_frame
	snapshot = Node3D.new()
	snapshot.name = "CurrentClassroomSnapshot"
	root.add_child(snapshot)
	collect(room)
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	var err = document.append_from_scene(snapshot, state)
	if err == OK:
		err = document.write_to_filesystem(state, OUT + "current_classroom.glb")
	counts["export_error"] = err
	counts["seed"] = 20261015
	counts["source"] = "scenes/game/classroom3D.tscn (runtime snapshot)"
	var file = FileAccess.open(OUT + "export_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(counts, "\t"))
	print(JSON.stringify(counts))
	quit(err)

func add_mesh(source: Mesh, transform: Transform3D, title: String, override_material: Material = null):
	var node = MeshInstance3D.new()
	node.name = title.validate_node_name()
	node.mesh = source
	node.transform = transform
	node.material_override = override_material
	snapshot.add_child(node)
	counts["meshes"] += 1
	return node

func collect(node: Node):
	if node is Node3D and not node.is_visible_in_tree():
		return
	if node is MeshInstance3D and node.mesh != null:
		if node.material_override is ShaderMaterial:
			return # Godot-only contact shadow and effects are not portable geometry.
		for surface in range(node.mesh.get_surface_count()):
			if node.get_active_material(surface) is ShaderMaterial:
				return
		var copy = add_mesh(node.mesh, node.global_transform, str(node.get_path()), node.material_override)
		for surface in range(node.mesh.get_surface_count()):
			copy.set_surface_override_material(surface, node.get_surface_override_material(surface))
	elif node is MultiMeshInstance3D and node.multimesh != null:
		var mm = node.multimesh
		var amount = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		for index in range(amount):
			add_mesh(mm.mesh, node.global_transform * mm.get_instance_transform(index), str(node.name) + str(index), node.material_override)
			counts["multimesh_instances"] += 1
	elif node is Sprite3D and node.texture != null:
		var image = node.texture.get_image()
		if image == null:
			return
		if node.region_enabled:
			image = image.get_region(Rect2i(node.region_rect))
		var material = StandardMaterial3D.new()
		material.albedo_texture = ImageTexture.create_from_image(image)
		material.albedo_color = node.modulate
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.3
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mesh = QuadMesh.new()
		mesh.size = Vector2(image.get_width(), image.get_height()) * node.pixel_size
		mesh.center_offset = Vector3(node.offset.x, node.offset.y, 0) * node.pixel_size
		mesh.material = material
		var transform = node.global_transform
		if node.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
			transform.basis = current_scene.get_node("Camera3D").global_basis.orthonormalized().scaled(node.global_basis.get_scale())
		add_mesh(mesh, transform, str(node.get_path()))
		counts["sprites"] += 1
	elif node is Light3D or node is Camera3D:
		var copy = node.duplicate(0)
		snapshot.add_child(copy)
		copy.global_transform = node.global_transform
		if node is Light3D:
			counts["lights"] += 1
	for child in node.get_children():
		collect(child)
