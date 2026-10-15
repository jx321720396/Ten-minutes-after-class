extends SceneTree


func _initialize() -> void:
	call_deferred("verify")


func verify() -> void:
	root.get_node("GameState").start_game(20261015, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	root.add_child(room)
	await process_frame
	room.get_node("Clock").hold(&"plant_support_check")
	for frame in range(4):
		await process_frame
	var group = room.get_node("ClassroomArt/SceneDetails")
	var failed := false
	for index in range(3):
		var plant = group.get_node("WindowPlant" + ["A", "B", "C"][index])
		var pot = plant.get_node("pot")
		var sill = group.get_node("WarmWindowTall%d/Window_sill" % (index + 1))
		var body: AABB = pot.global_transform * pot.get_aabb()
		var support: AABB = sill.global_transform * sill.get_aabb()
		var supported := (
			body.position.x >= support.position.x
			and body.end.x <= support.end.x
			and body.position.z >= support.position.z
			and body.end.z <= support.end.z
			and is_equal_approx(body.position.y, support.end.y)
		)
		print(plant.name, " supported=", supported)
		failed = failed or not supported
	quit(1 if failed else 0)
