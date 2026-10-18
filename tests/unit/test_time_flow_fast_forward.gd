extends GutTest

const TimeFlowScript := preload("res://scripts/game/time_flow.gd")


func _stack(fast_scale: float) -> Array:
	var core := SimCore.new(20261016, 16, ConfigLoader.new().load_all())
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.bind_core(core)
	clock.set_process(false)
	var flow := TimeFlowScript.new()
	add_child_autofree(flow)
	flow.set_process(false)
	# 只注入 rules/time_flow，把倍速锁死在用例期望值上，不耦合 data/ 里的实际 4×。
	var tables := {
		"rules/time_flow":
		{
			"rows":
			[
				{"param": "normal_scale", "value": "1"},
				{"param": "speed_options", "value": "3"},
				{"param": "fast_forward_scale", "value": str(fast_scale)},
			]
		}
	}
	flow.bind_sources(core, clock, tables)
	return [flow]


func test_request_fast_forward_sets_scale_and_release_restores() -> void:
	var flow: TimeFlow = _stack(4.0)[0]
	assert_eq(flow.multiplier(), 1.0, "初始为正常档 1×")
	flow.request_fast_forward(&"teacher_command")
	assert_eq(flow.multiplier(), 4.0, "快进锁生效为 fast_forward_scale")
	flow.release_fast_forward(&"teacher_command")
	assert_eq(flow.multiplier(), 1.0, "释放后还原到玩家自选档")


func test_normal_speed_lock_wins_over_fast_forward() -> void:
	var flow: TimeFlow = _stack(4.0)[0]
	flow.request_fast_forward(&"teacher_command")
	assert_eq(flow.multiplier(), 4.0)
	flow.request_normal_speed(&"event")
	assert_eq(flow.multiplier(), 1.0, "事件正常速度锁优先于快进")
	flow.release_normal_speed(&"event")
	assert_eq(flow.multiplier(), 4.0, "事件结束后快进恢复")
	flow.release_fast_forward(&"teacher_command")


func test_fast_forward_owner_is_idempotent() -> void:
	var flow: TimeFlow = _stack(4.0)[0]
	flow.request_fast_forward(&"a")
	flow.request_fast_forward(&"a")
	assert_eq(flow.multiplier(), 4.0)
	flow.release_fast_forward(&"a")
	assert_eq(flow.multiplier(), 1.0, "同一 owner 单次释放即全部解除")


func test_fast_forward_scale_comes_from_config() -> void:
	var flow: TimeFlow = _stack(7.0)[0]
	flow.request_fast_forward(&"x")
	assert_eq(flow.multiplier(), 7.0, "倍速读自 rules/time_flow 的 fast_forward_scale")
