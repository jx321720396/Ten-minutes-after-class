extends GutTest
## D03：老师面板的「去教室」入口必须真的调用内核命令 —— 每个课间首次到场全班压力 +5，
## 同一课间重复进入不再生效。此前该入口只切换视图、没有调用命令，看起来可用却不产生任何效果。


func test_enter_classroom_ui_applies_pressure_once_per_break() -> void:
	var state = get_node("/root/GameState")
	state.start_game(20261016, 16)
	var room = load("res://scenes/game/classroom3D.tscn").instantiate()
	room.get_node("Roam").enabled = false
	add_child_autofree(room)
	for frame in range(180):
		if room.has_node("OfficeHub"):
			break
		await get_tree().physics_frame
	room.get_node("Clock").hold(&"enter_classroom_test")
	var hub = room.get_node("OfficeHub")
	var core = state.sim_core
	var before := 0.0
	for index in range(core.node_count()):
		before += core.stress(index)
	hub._on_teacher_action("classroom")
	var after := 0.0
	for index in range(core.node_count()):
		after += core.stress(index)
	assert_gt(after, before, "去教室入口必须调用内核命令并全班加压（D03）")
	hub._on_teacher_action("classroom")
	var again := 0.0
	for index in range(core.node_count()):
		again += core.stress(index)
	assert_almost_eq(again, after, 0.001, "同一课间重复进入不再生效（D03）")
	state.end_game()
