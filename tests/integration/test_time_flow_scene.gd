extends GutTest
## 真教室验证配置、动态人物、时钟和 HUD 都接入同一倍速组件。


func test_real_classroom_chat_scales_world_and_normal_event_restores_it() -> void:
	var state = get_node("/root/GameState")
	state.start_game(20261009, 16)
	var scene = load("res://scenes/game/classroom3D.tscn").instantiate()
	scene.get_node("Roam").enabled = false
	add_child_autofree(scene)
	# 同上：等接线完成再冻结帧推进（固定帧数在 headless 下会偶发跑在接线之前）。
	for frame in range(180):
		if scene.get_node("Roam")._clock != null:
			break
		await get_tree().physics_frame
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var core: SimCore = state.sim_core
	var clock: SimulationClock = scene.get_node("Clock")
	var flow: TimeFlow = scene.get_node("TimeFlow")
	# 进教室转场黑幕会 hold 时钟，并靠真实秒的 tween 退场；本用例不等真实倒计时，
	# 直接解绑它（内含 release）—— 否则倍率恒为 0、NPC 不走、HUD 显示「已暂停」。
	scene.get_node("TransitionOverlay").bind_clock(null)
	assert_false(clock.is_paused(), "转场黑幕不再持有暂停锁")
	# 完成段首设置，之后创建真实合法聊天；夹具只挪位置、解除睡眠与占用。
	clock.pump(1.0)
	var me := core.node_count() - 1
	for index in [me, 0]:
		var sid := core.session_of(index)
		if sid >= 0:
			core._sessions.end(sid)
		core._sleeping[index] = false
		core._busy_until[index] = 0
		core.set_moving(index, false)
	var stand: Vector3 = scene.get_node("StandPoints/BACK_MID").global_position
	var player_actor: Node3D = scene.get_node("Actors").actor_for(me)
	var target: Node3D = scene.get_node("Actors").actor_for(0)
	player_actor.global_position = stand
	target.global_position = stand + Vector3(0.6, 0, 0)
	core.set_position(me, stand.x, stand.z)
	core.set_position(0, target.position.x, target.position.z)
	assert_true(core.chat_pair_in_range(me, 0), "真实几何中的聊天必须成立")
	core._do_chat(me, 0)
	flow.refresh()
	assert_eq(flow.multiplier(), 3.0)
	var hud: TimeHUD = scene.get_node("TimeHUD")
	assert_true(hud.title_line().contains("×3"), "HUD 显示世界正在三倍速运行")
	var tick_before := core.global_tick()
	var remaining_before := float(clock.snapshot().remaining_seconds)
	clock.pump(1.0)
	assert_eq(core.global_tick() - tick_before, 3)
	assert_almost_eq(remaining_before - clock.snapshot().remaining_seconds, 3.0, 0.001)
	# 真实场景生成的 NPC Walker 已注入倍率；这里用其既有直线接口独立量测播放速率。
	var npc: Node3D = scene.get_node("Actors").actor_for(2)
	var walker: ActorWalker = npc.get_node("Walker")
	npc.global_position = Vector3.ZERO
	walker.ease_motion = false
	walker.walk_to(Vector3(6, 0, 0), 6.0)
	walker._process(1.0)
	assert_almost_eq(npc.position.x, 3.0, 0.001, "教室动态 NPC 已接入同一倍率")
	flow.request_normal_speed(&"story_event")
	assert_eq(flow.multiplier(), 1.0)
	assert_false(hud.title_line().contains("×3"))
	tick_before = core.global_tick()
	clock.pump(1.0)
	assert_eq(core.global_tick() - tick_before, 1, "事件期间回到一倍，世界照常运行")
	flow.release_normal_speed(&"story_event")
	assert_eq(flow.multiplier(), 3.0)
	clock.hold(&"pen")
	var frozen_position := npc.position
	walker._process(1.0)
	assert_eq(npc.position, frozen_position, "hold 冻结世界，正常速度接口不能覆盖暂停")
	assert_eq(Engine.time_scale, 1.0, "场景倍速不修改引擎全局状态")
	state.end_game()
