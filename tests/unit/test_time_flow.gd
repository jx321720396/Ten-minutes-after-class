extends GutTest
## 老师版世界速度：玩家在时间卡片上自选 1×/2×/3×（点一次循环换档），暂停只有时钟 hold 一条来源。
## 2026-10-16：删除学生版的「玩家占用型行为自动 3×」与「连续学习逐档加速」（玩家节点已不存在）。


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


func test_manual_speed_scales_ticks_and_countdown() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var core: SimCore = parts[0]
	var clock: SimulationClock = parts[1]
	var flow = parts[2]
	var me := core.node_count() - 1
	assert_eq(flow.multiplier(), 1.0, "默认 1×")
	# 2026-10-16：学生版的自动加速已删除 —— 学生（含末位）忙碌不再改变世界速度。
	core._do_chat(me, 0)
	flow.refresh()
	assert_eq(flow.multiplier(), 1.0, "学生忙碌不再自动加速")
	# 只有玩家自选档位才加速。
	assert_true(flow.set_speed(3.0), "可选择 3×")
	flow.refresh()
	clock.pump(1.0)
	assert_eq(core.global_tick(), 3, "自选 3× 时一真实秒推进 3 tick")
	assert_almost_eq(clock.snapshot().remaining_seconds, 97.0, 0.001)
	assert_true(core.is_busy(me), "倍速只改变播放，聊天仍有其原 tick 耗时")


func test_cycle_speed_walks_one_two_three_then_wraps() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var flow = parts[2]
	assert_eq(flow.multiplier(), 1.0)
	assert_eq(flow.cycle_speed(), 2.0, "点一次 → 2×")
	assert_eq(flow.cycle_speed(), 3.0, "再点一次 → 3×")
	assert_eq(flow.cycle_speed(), 1.0, "再点一次回到 1×")


func test_normal_speed_lock_overrides_player_choice() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var flow = parts[2]
	assert_true(flow.set_speed(3.0))
	flow.request_normal_speed(&"report")
	flow.refresh()
	assert_eq(flow.multiplier(), 1.0, "事件持有正常速度锁期间强制 1×")
	flow.release_normal_speed(&"report")
	flow.refresh()
	assert_eq(flow.multiplier(), 3.0, "释放后回到玩家自选档位")


func test_out_of_range_speed_is_rejected() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var flow = parts[2]
	assert_false(flow.set_speed(0.5), "低于 1× 拒绝")
	assert_false(flow.set_speed(4.0), "超过档位数拒绝")
	assert_eq(flow.multiplier(), 1.0, "被拒绝的设定不改变倍率")


func test_normal_speed_locks_are_owned_and_idempotent() -> void:
	var parts := _stack()
	if parts.is_empty():
		return
	var core: SimCore = parts[0]
	var clock: SimulationClock = parts[1]
	var flow = parts[2]
	# 2026-10-16：自动加速已删 —— 玩家自选 3× 后，事件锁仍按 1× 推进。
	assert_true(flow.set_speed(3.0))
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
	assert_eq(flow.multiplier(), 3.0, "最后一个锁释放即恢复玩家自选倍率（3×）")


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
	var flow = parts[2]
	assert_true(flow.set_speed(3.0))
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
