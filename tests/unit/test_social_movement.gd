extends GutTest
## 真实行为入口的空间 / 移动互斥回归；不以气泡是否显示代替行为合法性。


func _core() -> SimCore:
	var core := SimCore.from_npc(12345, 8, ConfigLoader.new().load_all())
	core.set_interaction_geometry([], Rect2(-10, -10, 20, 20))
	for i in range(core.node_count()):
		core._sleeping[i] = false
		core._busy_until[i] = 0
		core.set_position(i, 0, 0)
	return core


func test_npc_chat_cannot_start_across_the_room() -> void:
	var core := _core()
	core.set_position(1, 8, 0)
	var affinity := core.affinity(0, 1)
	core._do_chat(0, 1)
	assert_eq(core.session_of(0), -1, "远处不能成立聊天")
	assert_false(core.is_busy(0), "非法聊天不占用")
	assert_eq(core.affinity(0, 1), affinity, "非法聊天不结算")


func test_npc_join_cannot_bypass_distance() -> void:
	var core := _core()
	core.set_position(1, 8, 0)
	core._do_join_chat(0, 1, 0.0)
	assert_eq(core.session_of(0), -1, "旧加入入口也不能远程聊天")
	assert_false(core.is_busy(0), "非法加入不占用")


func test_walking_actor_cannot_start_or_receive_chat() -> void:
	for mover in [0, 1]:
		var core := _core()
		core.set_position(1, 0.5, 0)
		core.set_moving(mover, true)
		core._do_chat(0, 1)
		assert_eq(core.session_of(0), -1, "聊天双方都必须停止移动")


func test_player_cannot_chat_with_moving_target() -> void:
	var core := _core()
	core.set_moving(0, true)
	var preview := core.preview_player_interaction("chat", 0)
	assert_false(bool(preview.eligible), "玩家不能拉正在走动的 NPC 聊天")


func test_moving_actor_does_not_start_sleeping_at_phase_setup() -> void:
	var core := _core()
	core._probs["sleep"] = 100.0
	core.set_moving(0, true)
	core._roll_sleep()
	assert_false(core._sleeping[0], "正在走动时不能进入睡眠占用")


func test_nearby_stationary_chat_still_starts() -> void:
	var core := _core()
	core.set_position(1, 0.5, 0)
	core._do_chat(0, 1)
	assert_gte(core.session_of(0), 0, "近距离静止双方正常聊天")
	assert_true(core.is_busy(0))
	assert_true(core.is_busy(1))


func test_front_back_seated_neighbors_can_chat_but_not_sideways() -> void:
	var core := _core()
	core._seat_of[0] = "P1"
	core._seat_of[1] = "P5"
	core.set_position(0, 0, 0)
	core.set_position(1, 0, 1.6)
	core.call("set_seat_position", 0, Vector2.ZERO)
	core.call("set_seat_position", 1, Vector2(0, 1.6))
	# 前后相邻之间有课桌仍可转身说话；这不是离座后的通用穿桌特权。
	core.set_interaction_geometry([Rect2(-0.3, 0.6, 0.6, 0.4)], Rect2(-10, -10, 20, 20))
	assert_true(core.chat_pair_in_range(0, 1), "前后紧邻且都在本座位可转身聊天")
	core._seat_of[1] = "P2"
	assert_false(core.chat_pair_in_range(0, 1), "左右座位不享受前后例外")
	core._seat_of[1] = "P5"
	core.set_position(1, 4, 4)
	assert_false(core.chat_pair_in_range(0, 1), "离开座位后恢复实际距离判定")


func test_player_seated_front_back_neighbor_uses_same_rule() -> void:
	var core := _core()
	var me := core.node_count() - 1
	core._seat_of[me] = "P1"
	core._seat_of[0] = "P5"
	core.set_position(me, 0, 0)
	core.set_position(0, 0, 1.6)
	core.call("set_seat_position", me, Vector2.ZERO)
	core.call("set_seat_position", 0, Vector2(0, 1.6))
	var preview := core.preview_player_interaction("chat", 0)
	assert_true(bool(preview.in_range), "玩家和 NPC 使用同一座位规则")


func test_desk_blocks_chat_after_leaving_seats() -> void:
	var core := _core()
	core.set_interaction_geometry([Rect2(0.2, -0.3, 0.2, 0.6)], Rect2(-10, -10, 20, 20))
	core.set_position(1, 0.6, 0)
	core._do_chat(0, 1)
	assert_eq(core.session_of(0), -1, "近但隔桌且无前后座位例外时不能聊")


func test_roam_does_not_reserve_destination_while_chatting() -> void:
	var core := _core()
	core._do_chat(0, 1)
	var roam = load("res://scripts/game/classroom_roam.gd").new()
	autofree(roam)
	roam._core = core
	roam._actor_count = 1
	roam._player_index = -1
	var walker := ActorWalker.new()
	autofree(walker)
	roam._walkers = [walker]
	roam._point_positions = {"home": Vector3.ZERO, "away": Vector3(2, 0, 0)}
	roam._occupy("home", 0)
	roam.leave_probability = 1.0
	roam.log_roam = false
	roam._decide_batch()
	assert_eq(roam.occupant_of("home"), 0, "聊天期间不能离座并预占其他点")
	assert_eq(roam.occupant_of("away"), -1)
