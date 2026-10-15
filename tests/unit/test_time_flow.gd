extends GutTest
## 同一真实时间的 tick 与移动必须共同缩放，事件锁不等于暂停。


func _stack() -> Array:
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
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
	# 先完成惰性段首初始化，再隔离自主决策，避免首 tick 覆盖测试状态。
	core._begin_phase()
	for i in range(core.node_count()):
		core._phase_state[i] = "broken"
	core._do_chat(me, 0)
	# 聊天时长带抖动（base × uniform[0.8,1.2]），所以按「忙不忙」推进，不写死 30 tick。
	var guard := 0
	while core.is_busy(me) and guard < 40:
		flow.refresh()
		clock.pump(1.0)
		guard += 1
	flow.refresh()
	assert_lt(guard, 40, "聊天应在保护上限前完成，不能拖到铃响")
	assert_lt(core.global_tick(), 100, "必须在当前课间内观察聊天完成")
	assert_false(core.is_busy(me), "聊天完成后不再占用")
	assert_eq(flow.multiplier(), 1.0, "完成后自动恢复正常速度")
	var tick_after := core.global_tick()
	clock.pump(1.0)
	assert_eq(core.global_tick(), tick_after + 1, "空闲一秒只推进一个 tick")


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
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
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


func test_study_survives_ticks_and_increases_grade() -> void:
	var parts := _stack()
	var core: SimCore = parts[0]
	var me := core.node_count() - 1
	core._do_study(me)
	for tick in range(12):
		core.advance_tick()
	assert_eq(core.activity_of(me), "study")
	assert_gt(core.grade(me), 250.0)
	core.set_moving(me, true)
	assert_eq(core.activity_of(me), "")


func test_study_speed_uses_real_seconds_without_cap_and_resets() -> void:
	var parts := _stack()
	var core: SimCore = parts[0]
	var clock: SimulationClock = parts[1]
	var flow: TimeFlow = parts[2]
	var me := core.node_count() - 1
	core._do_study(me)
	flow.refresh()
	assert_eq(flow.multiplier(), 1.0)
	for stage in range(1, 6):
		flow._process(10.0)
		assert_eq(flow.multiplier(), float(stage + 1))
		assert_almost_eq(flow.scale_delta(10.0), float(stage * 10), 0.001)
	clock.hold(&"test")
	flow._process(30.0)
	assert_eq(flow.multiplier(), 0.0)
	clock.release(&"test")
	flow.refresh()
	assert_eq(flow.multiplier(), 6.0)
	# 起身离开座位：清掉学习占用（_do_study 会把 busy_until 覆盖到整段末）
	core.set_moving(me, true)
	core._busy_until[me] = 0
	flow.refresh()
	assert_eq(flow.multiplier(), 1.0)
	core.set_moving(me, false)
	core._do_study(me)
	assert_eq(core.activity_of(me), "study", "回到学习态")
	# TimeFlow 的提速依赖时钟继续推进后再刷新；此处只验证内核状态与「移动清学习」的语义。


func test_study_accelerates_clock_and_grade_together() -> void:
	var parts := _stack()
	var core: SimCore = parts[0]
	var clock: SimulationClock = parts[1]
	var flow: TimeFlow = parts[2]
	var me := core.node_count() - 1
	# 段首状态决定结算口径：这里明确把该生设为学习状态（其余隔离），避免被动力推断成游戏状态。
	core._begin_phase()
	for i in range(core.node_count()):
		core._phase_state[i] = "broken"
	core._phase_state[me] = "study"
	var gain_before := core.gain_today(me)
	core._do_study(me)
	for second in range(20):
		flow._process(1.0)
		clock.pump(1.0)
	assert_eq(core.global_tick(), 30)
	# D02：学习先记「今日学业收益」，跨天由 _settle_day 并入成绩（成绩当天不变）。
	assert_eq(core.phase_state_of(me), "study", "推进后仍保留学习段首状态")
	assert_almost_eq(core.gain_today(me), gain_before + 1.0, 0.0001, "30 tick 完成一个学习单位")
	assert_eq(flow.multiplier(), 3.0)


func test_bell_stops_study_and_speed_without_reverting_grade() -> void:
	var parts := _stack()
	var core: SimCore = parts[0]
	var flow: TimeFlow = parts[2]
	var me := core.node_count() - 1
	core._do_study(me)
	for tick in range(100):
		core.advance_tick()
	var earned := core.grade(me)
	core.finish_time_boundary()
	flow.refresh()
	assert_eq(core.activity_of(me), "")
	assert_eq(core.grade(me), earned)
	assert_eq(flow.multiplier(), 1.0)


func test_large_frame_integrates_each_speed_stage() -> void:
	var parts := _stack()
	var core: SimCore = parts[0]
	var flow: TimeFlow = parts[2]
	var me := core.node_count() - 1
	core._do_study(me)
	flow._process(25.0)
	assert_almost_eq(flow.scale_delta(25.0), 45.0, 0.001)
	assert_eq(flow.multiplier(), 3.0)
