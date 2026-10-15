extends SceneTree
## Asset/material integration check, independent of simulation initialization.


func _initialize() -> void:
	var style: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/classroom_art.json")
	)
	if not style.get("node_material_overrides", {}).has("Podium/Lectern/Body"):
		push_error("Missing podium body material override")
		quit(1)
		return
	var room: Node3D = load("res://scenes/game/classroom3D.tscn").instantiate()
	assert(not room.has_node("Seats/P0"))
	var art = room.get_node("ClassroomArt")
	art._style = style
	art._room = room
	art._make_materials()
	art._apply_materials(room)
	var body: StandardMaterial3D = room.get_node("Podium/Lectern/Body").material_override
	assert(body.albedo_texture == null)
	assert(body.albedo_color.is_equal_approx(Color("#c1beb3")))
	assert(room.get_node("Podium/Lectern/Top").material_override != body)
	var fixture_count := 0
	for definition in style.lighting.lights:
		assert(room.has_node(definition.path))
		if "CeilingFixtures" in definition.path:
			fixture_count += 1
			assert(is_equal_approx(room.get_node(definition.path).position.y, 3.38))
	assert(fixture_count == 9)
	var ceiling: Node3D = (
		load("res://scenes/components/classroom_ceiling_recessed.tscn").instantiate()
	)
	assert(ceiling.find_children("LampDiffuser*", "MeshInstance3D", true, false).size() == 9)
	assert(ceiling.find_children("*Suspension*", "MeshInstance3D", true, false).is_empty())
	assert(ceiling.find_children("*", "CollisionObject3D", true, false).is_empty())
	var placed := false
	for placement in style.scene_details:
		placed = (
			placed or placement.scene == "res://scenes/components/classroom_ceiling_recessed.tscn"
		)
	assert(placed)
	ceiling.free()
	room.free()
	print(
		"PASS: deleted desk absent; matte podium body; nine aligned recessed lights; visual-only ceiling connected"
	)
	quit(0)
