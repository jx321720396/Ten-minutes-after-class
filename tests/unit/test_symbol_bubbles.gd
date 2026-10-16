extends GutTest

const Presenter = preload("res://scripts/ui/chat_activity_bubble.gd")


func _presenter(core: SimCore) -> ChatActivityBubble:
	var view := Presenter.new()
	add_child_autofree(view)
	view.set_process(false)
	view.bind_core(core)
	return view


func test_public_activities_emit_for_player_and_npc() -> void:
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
	var view := _presenter(core)
	assert_true(view.has_method("emitter_kind"), "符号气泡需要按公开行为查询发射器")
	if not view.has_method("emitter_kind"):
		return
	for kind in ["study", "listen_music", "eat_snack", "read_book"]:
		core._current_act[0] = kind
		core._current_act[core.node_count() - 1] = kind
		view._process(0.1)
		assert_eq(view.emitter_kind(0), kind)
		assert_eq(view.emitter_kind(core.node_count() - 1), kind)
	core._current_act[0] = "chat"
	view._process(0.1)
	assert_eq(view.emitter_kind(0), "", "行为名不能伪造真实聊天")
	core._sessions.begin("chat", [0, 1], core.global_tick() + 30)
	view._process(0.1)
	assert_eq(view.emitter_kind(0), "chat")
	assert_eq(view.emitter_kind(1), "chat")
	view.hide_member(0)
	assert_false(view.has_bubble(0), "尚未揭晓的加入者不泄露")
	view.show_member(0)
	assert_true(view.has_bubble(0))


func test_particles_shrink_fall_fade_and_are_removed_on_stop() -> void:
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
	core._current_act[0] = "study"
	var view := _presenter(core)
	assert_true(view.has_method("particle_snapshot"))
	if not view.has_method("particle_snapshot"):
		return
	view._process(0.01)
	var first: Dictionary = view.particle_snapshot(0)[0]
	view._process(float(view._settings["lifetime_seconds"]) * 0.8)
	var later: Dictionary = view.particle_snapshot(0)[0]
	assert_lt(float(later["scale"]), float(first["scale"]))
	assert_lt(float(later["alpha"]), float(first["alpha"]))
	assert_lt(float(later["height"]), float(first["height"]))
	core._current_act[0] = ""
	view._process(0.01)
	assert_eq(view.particle_snapshot(0).size(), 0, "行为停止不残留")


func test_effect_does_not_consume_simulation_rng_and_hold_freezes_it() -> void:
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
	core._current_act[0] = "study"
	var before: PackedInt64Array = core._rng._mt.duplicate()
	var before_index: int = core._rng._mti
	var view := _presenter(core)
	assert_true(view.has_method("particle_snapshot"))
	if not view.has_method("particle_snapshot"):
		return
	view._process(0.1)
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.set_process(false)
	view.bind_clock(clock)
	clock.hold(&"test")
	var frozen: Array = view.particle_snapshot(0)
	view._process(1.0)
	assert_eq(view.particle_snapshot(0), frozen)
	assert_eq(core._rng._mt, before, "粒子不能改变模拟随机状态")
	assert_eq(core._rng._mti, before_index, "粒子不能消费模拟随机序列")


func test_particles_use_real_time_at_all_world_speeds_and_hold_still_freezes() -> void:
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
	var me := core.node_count() - 1
	core._current_act[me] = "study"
	core._busy_until[me] = core.global_tick() + 50
	var view := _presenter(core)
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.set_process(false)
	assert_true(clock.bind_core(core))
	var flow := TimeFlow.new()
	add_child_autofree(flow)
	flow.set_process(false)
	assert_true(flow.bind_sources(core, clock))
	view.bind_clock(clock)
	view.bind_time_flow(flow)
	view._process(0.01)
	view._process(0.2)
	var age: float = view._bubbles[me]["particles"][0]["age"]
	assert_almost_eq(age, 0.2, 0.0001, "三倍速仍按现实时间播放")
	for speed in [1.0, 2.0, 3.0]:
		assert_true(flow.set_speed(speed), "玩家自选档位可用")
		flow.refresh()
		var previous_age: float = view._bubbles[me]["particles"][0]["age"]
		view._process(0.2)
		assert_almost_eq(
			float(view._bubbles[me]["particles"][0]["age"]) - previous_age,
			0.2,
			0.0001,
			"改变世界倍速不改变粒子时钟"
		)
	assert_eq(view.particle_snapshot(me).size(), 2, "生成间隔也不受倍速影响")
	clock.hold(&"test")
	var frozen := view.particle_snapshot(me)
	view._process(1.0)
	assert_eq(view.particle_snapshot(me), frozen, "保留暂停与 hold 冻结")
	clock.release(&"test")
	flow.refresh()
	view._process(100.0)
	assert_eq(view.particle_snapshot(me).size(), 1, "大步长不补喷历史粒子")
	for step in range(200):
		view._process(0.1)
		assert_lte(view.particle_snapshot(me).size(), int(view._settings["max_per_actor"]))


func test_switching_activity_and_rebinding_clears_old_particles() -> void:
	var core := SimCore.new(12345, 16, ConfigLoader.new().load_all())
	core._current_act[0] = "study"
	var view := _presenter(core)
	view._process(0.1)
	assert_gt(view.particle_snapshot(0).size(), 0)
	core._current_act[0] = "read_book"
	view._process(0.0)
	assert_eq(view.emitter_kind(0), "read_book")
	assert_eq(view.particle_snapshot(0).size(), 0)
	view.bind_core(null)
	view._process(0.1)
	assert_eq(view._bubbles.size(), 0)
