extends GutTest
## 同一真实时间的 tick 与移动必须共同缩放，事件锁不等于暂停。


func _stack() -> Array:
	var core := SimCore.from_npc(12345, 8, ConfigLoader.new().load_all())
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.bind_core(core)
	clock.set_process(false)
	var script = load("res://scripts/game/time_flow.gd")
	assert_not_null(script, "独立倍速组件必须存在")
	if script == null:
		return []
	var flow = script.new()
	add_child_autofree(flow)
	assert_true(flow.bind_sources(core, clock))
	flow.set_process(false)
	clock.call("bind_time_flow", flow)
	return [core, clock, flow]


func test_player_busy_scales_ticks_and_countdown_three_times() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var core: SimCore = parts[0]
	var clock: SimulationClock = parts[1]
	var flow = parts[2]
	var me := core.node_count() - 1
	assert_eq(flow.multiplier(), 1.0)
	# 真实行为服务给双方占用，倍速不依赖菜单的 Active 状态。
	core._do_chat(me, 0)
	flow.refresh()
	clock.pump(1.0)
	assert_eq(core.global_tick(), 3, "一真实秒按三倍推进内核")
	assert_almost_eq(clock.snapshot().remaining_seconds, 97.0, 0.001)
	assert_true(core.is_busy(me), "倍速只改变播放，聊天仍有其原 tick 耗时")


func test_walking_and_npc_busy_alone_keep_normal_speed() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var core: SimCore = parts[0]
	var flow = parts[2]
	core._do_chat(0, 1)
	flow.refresh()
	assert_eq(flow.multiplier(), 1.0, "NPC 单独忙碌不加速玩家空闲时间")
	core.set_moving(core.node_count() - 1, true)
	flow.refresh()
	assert_eq(flow.multiplier(), 1.0, "玩家走路不触发世界加速")
	core.set_moving(core.node_count() - 1, false)
	flow.refresh()
	assert_eq(flow.multiplier(), 1.0)


func test_normal_speed_locks_are_owned_and_idempotent() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var core: SimCore = parts[0]
	var clock: SimulationClock = parts[1]
	var flow = parts[2]
	core._do_chat(core.node_count() - 1, 0)
	flow.refresh()
	flow.request_normal_speed(&"event_a")
	flow.request_normal_speed(&"event_a")
	flow.request_normal_speed(&"event_b")
	clock.pump(1.0)
	assert_eq(core.global_tick(), 1, "事件锁按一倍推进，并不暂停")
	flow.release_normal_speed(&"event_a")
	assert_eq(flow.multiplier(), 1.0, "另一个事件仍持有")
	flow.release_normal_speed(&"unknown")
	assert_eq(flow.multiplier(), 1.0)
	flow.release_normal_speed(&"event_b")
	assert_eq(flow.multiplier(), 3.0, "最后一个锁释放即恢复自动倍率")


func test_pause_freezes_scaled_time_and_does_not_catch_up() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var core: SimCore = parts[0]
	var clock: SimulationClock = parts[1]
	var flow = parts[2]
	core._do_chat(core.node_count() - 1, 0)
	flow.request_normal_speed(&"event")
	clock.hold(&"pen")
	flow.refresh()
	assert_eq(flow.scale_delta(5.0), 0.0)
	clock.pump(5.0)
	assert_eq(core.global_tick(), 0)
	clock.release(&"pen")
	flow.refresh()
	clock.pump(1.0)
	assert_eq(core.global_tick(), 1, "恢复后只推进新的一秒")


func test_actor_movement_uses_the_same_multiplier() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var core: SimCore = parts[0]
	var flow = parts[2]
	core._do_chat(core.node_count() - 1, 0)
	flow.refresh()
	var actor := Node3D.new()
	var walker := ActorWalker.new()
	actor.add_child(walker)
	add_child_autofree(actor)
	walker.set_process(false)
	walker.ease_motion = false
	walker.call("bind_time_flow", flow)
	walker.walk_to(Vector3(6, 0, 0), 6.0)
	walker._process(1.0)
	assert_almost_eq(actor.position.x, 3.0, 0.001, "NPC 一真实秒走三倍距离")


func test_action_completion_restores_normal_speed() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var core: SimCore = parts[0]
	var clock: SimulationClock = parts[1]
	var flow = parts[2]
	var me := core.node_count() - 1
	core._do_chat(me, 0)
	for second in range(10):
		flow.refresh()
		clock.pump(1.0)
	flow.refresh()
	assert_eq(core.global_tick(), 30, "30 tick 聊天在十真实秒后完成")
	assert_false(core.is_busy(me))
	assert_eq(flow.multiplier(), 1.0, "完成后自动恢复正常速度")
	clock.pump(1.0)
	assert_eq(core.global_tick(), 31, "空闲一秒只推进一个 tick")


func test_hold_also_freezes_actor_motion() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var clock: SimulationClock = parts[1]
	var flow = parts[2]
	var actor := Node3D.new()
	var walker := ActorWalker.new()
	actor.add_child(walker)
	add_child_autofree(actor)
	walker.set_process(false)
	walker.bind_time_flow(flow)
	walker.walk_to(Vector3(6, 0, 0), 6.0)
	clock.hold(&"pen")
	walker._process(2.0)
	assert_eq(actor.position, Vector3.ZERO, "转笔 hold 冻结 NPC，不能趁玩家等待继续走")


func test_invalid_speed_config_is_rejected() -> void:
	var core := SimCore.from_npc(12345, 8, ConfigLoader.new().load_all())
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.bind_core(core)
	var script = load("res://scripts/game/time_flow.gd")
	var flow = script.new()
	add_child_autofree(flow)
	var bad := {
		"rules/time_flow":
		{
			"rows":
			[
				{"param": "normal_scale", "value": "1"},
				{"param": "player_action_scale", "value": "-3"},
			]
		}
	}
	assert_false(flow.bind_sources(core, clock, bad))
	assert_push_error("TimeFlow：需要有效内核与时钟")
	assert_eq(flow.scale_delta(1.0), 0.0, "坏配置不能静默让世界继续运行")


func test_report_and_term_end_override_normal_speed_locks() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var clock: SimulationClock = parts[1]
	var flow = parts[2]
	flow.request_normal_speed(&"event")
	for mode in [SimulationClock.MODE_REPORT, SimulationClock.MODE_FINISHED]:
		clock._mode = mode
		flow.refresh()
		assert_eq(flow.scale_delta(1.0), 0.0, "简报/结束期间不能被事件速度锁重新启动")


func test_class_phase_uses_normal_speed_even_with_old_player_occupancy() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var core: SimCore = parts[0]
	var flow = parts[2]
	core._phase_index = 1
	core._busy_until[core.node_count() - 1] = 100
	flow.refresh()
	assert_eq(flow.multiplier(), 1.0, "课堂按既有呈现时长，不叠加玩家行动倍率")
