extends GutTest
## 真教室、真时钟、真导航驱动推进整段课间，检查聊天成员静止与真实范围。


func test_classroom_chat_and_movement_are_mutually_exclusive() -> void:
	var state = get_node("/root/GameState")
	state.start_game(20261007, 16)
	var scene = load("res://scenes/game/classroom3D.tscn").instantiate()
	add_child_autofree(scene)
	# 教室要等导航就绪后才把时钟与交互接上：按条件等待，别用固定帧数 ——
	# headless 下加载快慢不一，固定 20 帧会偶发「未接线」而整例失败。
	for frame in range(180):
		if scene.get_node("Roam")._clock != null:
			break
		await get_tree().physics_frame
	var core: SimCore = state.sim_core
	# D01：开局动力 = 压力（0–20）→ 全班落在「<30 的游戏状态」，整课间不会自主聊天。
	# 本用例验的是「聊天与走动互斥」，所以先把动力放进自由区（30–60）并重算段首状态。
	for i in range(core.node_count()):
		core._vitality[i] = 45.0
	core._begin_phase_state()
	var roam = scene.get_node("Roam")
	var clock: SimulationClock = scene.get_node("Clock")
	assert_not_null(roam._clock, "真实导航与时钟完成接线")
	# 进教室转场黑幕会 hold 时钟，并靠真实秒的 tween 退场；本用例不等真实倒计时，
	# 直接解绑它（内含 release）—— 否则 clock.pump() 全程被 is_paused() 挡掉，
	# 聊天与走动计数都会变成 0。
	scene.get_node("TransitionOverlay").bind_clock(null)
	assert_false(clock.is_paused(), "转场黑幕不再持有暂停锁")
	# 帧推进被冻结前先刷一次倍率：TimeFlow 的帧倍率是在时钟暂停时算出的 0，
	# 不刷新的话 clock.pump() 会把每一步 delta 缩成 0，tick 一步都不动。
	var flow: TimeFlow = scene.get_node("TimeFlow")
	flow.refresh()
	assert_eq(flow.multiplier(), 1.0, "课间无占用 → 世界一倍速")
	# 禁用自动帧推进，按固定步长调用同一生产组件，避免测试耗时等于真实课间。
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var violations: Array = []
	var seen_sessions := {}
	var moving_frames := 0
	for step in range(1000):
		roam._process(0.1)
		for walker in roam._walkers:
			if walker != null:
				walker._process(0.1)
		roam._sync_positions_to_core()
		clock.pump(0.1)
		for i in range(core.node_count() - 1):
			if core.is_moving(i):
				moving_frames += 1
		for session in core.get_active_sessions():
			var sid: int = int(session.session_id)
			# 距离上限只在会话**建立的那一刻**判定：内核建立时会校验距离，此后按 tick 走完
			# （§10.15）；相位归位等把成员瞬移带走不算「远距离聊天」——
			# 「有没有边走边聊」由上面的成员移动检查负责。
			var fresh := not seen_sessions.has(sid)
			seen_sessions[sid] = true
			for member in session.members:
				if roam._walkers[member].is_moving():
					violations.append("聊天成员仍在移动: %s" % member)
			if not fresh:
				continue
			for pair in session.links:
				var a: int = pair[0]
				var b: int = pair[1]
				# 独立上限：普通 1.2m 近距离，或原座位**同排前后紧邻**的 1.8m 例外（§10.15）。
				# 2026-10-16：通用加入（§9.1.4）允许「先成立活动、再走过去」，所以加入路径的成员
				# 距离可能一时偏大；这条断言只抓明显异常（双方都静止却隔了 3m 以上仍在同一场活动）。
				var gap: float = core.distance_between(a, b)
				var both_still: bool = not core.is_moving(a) and not core.is_moving(b)
				if gap <= 3.0 or not both_still:
					continue
				var sa: Array = core._seat_pos[core.seat_of(a)]
				var sb: Array = core._seat_pos[core.seat_of(b)]
				if not (sa[1] == sb[1] and absi(sa[0] - sb[0]) == 1 and gap <= 3.5):
					violations.append("远距离聊天: %s（%.2fm）" % [pair, gap])
		if not roam.is_break_phase():
			break
	assert_gt(seen_sessions.size(), 0, "确实发生聊天，不以关闭所有行为通过测试")
	# 2026-10-16：老师版内核决策不再产生「自主走动」（走位改由表现层 / 老师操作驱动），
	# 本用例保留「走动与聊天互斥」的核心判定，但不再强求整段课间必然出现走动帧。
	assert_eq(violations, [], "整段课间没有远程聊天或边聊边走")
	state.end_game()
