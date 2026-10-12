extends SceneTree
## Bake portable GLBs into native visual-only scenes for the production art layer.

const CONFIG := "res://data/ui/classroom_window_blender.json"


func _initialize() -> void:
	var config_path := CONFIG
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--config="):
			config_path = argument.trim_prefix("--config=")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	for definition in config["assets"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_file(str(definition["source"]), state)
		if error != OK:
			quit(error)
			return
		var model := document.generate_scene(state)
		model.name = str(definition["name"])
		_own(model, model)
		var packed := PackedScene.new()
		error = packed.pack(model)
		if error == OK:
			error = ResourceSaver.save(packed, str(definition["scene"]))
		print("baked ", definition["scene"], ": ", error)
		model.free()
		if error != OK:
			quit(error)
			return
	quit()


func _own(node: Node, owner_node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if "glass" in str(node.name).to_lower():
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for index in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(index) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
