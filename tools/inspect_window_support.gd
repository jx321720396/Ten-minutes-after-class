extends SceneTree


func _initialize() -> void:
	call_deferred("inspect")


func inspect() -> void:
	root.get_node("GameState").start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	await process_frame
	room.get_node("Clock").hold(&"support_inspect")
	for frame in range(4):
		await process_frame
	for mesh in room.find_children("*", "MeshInstance3D", true, false):
		var path := str(room.get_path_to(mesh))
		if (
			"WindowPlant" in path
			or ("WarmWindowTall" in path and "sill" in str(mesh.name).to_lower())
			or path == "Room/RightWall/Lower"
			or path == "Seats/P1/Desk/Top"
		):
			print(path, " bounds=", mesh.global_transform * mesh.get_aabb())
	quit(0)
