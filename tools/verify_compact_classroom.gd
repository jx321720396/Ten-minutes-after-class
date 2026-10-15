extends SceneTree


func _initialize() -> void:
	var room: Node3D = load("res://scenes/game/classroom3D.tscn").instantiate()
	if not is_equal_approx(room.get_node("Seats/P1").position.x, 2.46):
		push_error("Compact seat layout not connected")
		room.free()
		quit(1)
		return
	assert(room.get_node("Seats").get_child_count() == 16)
	for index in range(1, 17):
		var seat = room.get_node("Seats/P%d" % index)
		assert(is_equal_approx(seat.position.x, (1.5 - (index - 1) % 4) * 1.25 + 0.585))
		assert(is_equal_approx(seat.position.z, (1.5 - floorf((index - 1) / 4.0)) * 2.0))
		assert(is_equal_approx(seat.get_node("Desk/Top").mesh.size.x, 0.7392))
	var style = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/classroom_art.json"))
	var bags := 0
	for placement in style.scene_details:
		if str(placement.name).begins_with("DeskSideBag"):
			assert(placement.scene == "res://scenes/components/bag_left_hook.tscn")
			assert(room.has_node(placement.anchor_node))
			bags += 1
	assert(bags == 16)
	var bag: Node3D = load("res://scenes/components/bag_left_hook.tscn").instantiate()
	assert(bag.find_children("*", "MeshInstance3D", true, false).size() == 7)
	assert(bag.find_children("*", "CollisionObject3D", true, false).is_empty())
	bag.free()
	room.free()
	print("PASS: 16 compact seats, larger desks, 16 left-side hooked bags, no bag collision")
	quit(0)
