extends GutTest


func _core(npc: int = 16) -> SimCore:
	var tables := ConfigLoader.new().load_all()
	return SimCore.new(12345, npc, tables)


func test_start_does_not_relieve_stress_and_completion_only_once() -> void:
	for kind in SimCore.LEISURE_KINDS:
		var c := _core()
		var me := c.node_count() - 1
		c._book[me] = 1
		c._stress[me] = 20.0
		assert_true(bool(c.player_action(kind, -1).get("ok", false)))
		assert_eq(c.stress(me), 20.0)
		assert_false(c._can_interact_with(me))
		assert_eq(str(c.player_action("study", -1).get("error", "")), "player_busy")
		c._global_tick = int(c._busy_until[me]) - 1
		c._settle_finished_actions()
		assert_eq(c.stress(me), 20.0)
		c._global_tick += 1
		c._settle_finished_actions()
		var relief := float(c._leisure[str(SimCore.LEISURE_KINDS[kind]) + "_relief"])
		assert_eq(c.stress(me), 20.0 - relief)
		c._settle_finished_actions()
		assert_eq(c.stress(me), 20.0 - relief)


func test_bell_interruption_and_exact_completion_are_exclusive() -> void:
	for exact in [false, true]:
		var c := _core()
		var me := c.node_count() - 1
		c._global_tick = 70 if exact else 71
		c._stress[me] = 20.0
		assert_true(bool(c.player_action("listen_music", -1).get("ok", false)))
		c._global_tick = 100
		c._end_phase()
		assert_eq(c.stress(me), 18.0 if exact else 20.5)
		c._end_phase()
		assert_eq(c.stress(me), 18.0 if exact else 20.5)
		assert_false(c.is_busy(me))
		assert_eq(c.activity_of(me), "")


func test_inventory_gates_and_npc_snacks_unlimited() -> void:
	var c := _core()
	var me := c.node_count() - 1
	assert_eq(str(c.player_action("read_book", -1).get("error", "")), "no_book")
	assert_eq(int(c.inventory_of(me)["books"]), 0)
	for _i in range(5):
		assert_true(bool(c.player_action("eat_snack", -1).get("ok", false)))
		c._global_tick = int(c._busy_until[me])
		c._settle_finished_actions()
	assert_eq(int(c.inventory_of(me)["snacks"]), 0)
	assert_eq(str(c.player_action("eat_snack", -1).get("error", "")), "no_snacks")
	assert_true(c._start_leisure(0, "eat_snack"))
	assert_eq(int(c.inventory_of(me)["snacks"]), 0)


func test_book_roster_quotas_and_seed_facts() -> void:
	# 一局固定 16 名 NPC：持书 NPC 数 = rules/leisure.csv 的 book_count（5 = 池内 book=1 的人）
	var c := _core()
	var count := 0
	for i in range(c.node_count() - 1):
		count += int(c.inventory_of(i)["books"])
		assert_eq(int(c.inventory_of(i)["books"]), int(str(c._chars[i]["book"])))
	assert_eq(count, 5, "持书 NPC 数 = book_count")


func test_class_rejects_all_four_actions() -> void:
	var c := _core()
	c.advance_phase()
	for kind in ["listen_music", "eat_snack", "read_book", "leave_class"]:
		assert_eq(str(c.player_action(kind, -1).get("error", "")), "phase_not_allowed")


func test_absence_freezes_player_and_runs_npc_ticks() -> void:
	var c := _core()
	c.advance_tick()
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	assert_true(clock.bind_core(c))
	clock.set_process(false)
	var me := c.node_count() - 1
	c._stress[me] = 20.0
	assert_true(bool(c.player_action("leave_class", -1).get("ok", false)))
	assert_false(c.is_present(me))
	assert_false(c._can_interact_with(me))
	assert_false(c.get_player_invitation().size() > 0)
	var a := c._a.duplicate()
	var h := c._h.duplicate()
	var g := c.grade(me)
	c._volume = 100.0
	c._stress_drip()
	for i in range(c.node_count()):
		assert_eq(c.affinity(i, me), float(a[i * c.node_count() + me]))
		assert_eq(c.affinity(me, i), float(a[me * c.node_count() + i]))
		assert_eq(c.hostility(i, me), float(h[i * c.node_count() + me]))
	assert_eq(c.stress(me), 20.0)
	var events_before := int(c._stats["events"])
	assert_true(clock.skip_absent_break())
	assert_eq(c.global_tick(), 100)
	assert_eq(str(c.time_snapshot()["kind"]), "class")
	assert_eq(c.tick_in_phase(), 0)
	assert_true(c.is_present(me))
	assert_eq(c.grade(me), g)
	assert_eq(c.stress(me), 20.0)
	assert_gt(int(c._stats["events"]), events_before)
	assert_false(clock.skip_absent_break())


func test_leave_cost_is_incoming_neighbor_affinity_via_uif() -> void:
	var c := _core()
	var expected := _core()
	var me := c.node_count() - 1
	for j in c._neighbor_idx[me]:
		expected._apply_event(j, me, "leave_absence")
	assert_true(bool(c.player_action("leave_class", -1).get("ok", false)))
	assert_eq(c._a, expected._a)
	assert_eq(c._h, expected._h)


func test_class_affinity_is_neighbor_only_and_skips_sleepers() -> void:
	var c := _core()
	c._sleeping[0] = true
	var before := c._a.duplicate()
	c._class_affinity_settle()
	for i in range(c.node_count()):
		for j in range(c.node_count()):
			var expected := float(before[i * c.node_count() + j])
			if i != 0 and j != 0 and c._neighbor_idx[i].has(j):
				expected = minf(100.0, expected + 0.2)
			assert_eq(c.affinity(i, j), expected)


func test_public_badge_and_inventory_button_follow_state() -> void:
	var c := _core()
	var me := c.node_count() - 1
	var badge := BehaviorBadgePresenter.new()
	add_child_autofree(badge)
	badge.bind_core(c)
	assert_true(bool(c.player_action("listen_music", -1).get("ok", false)))
	badge._sync()
	assert_eq(badge.activity_badge_text(me), "在听音乐")
	c._global_tick = int(c._busy_until[me])
	c._settle_finished_actions()
	badge._sync()
	assert_eq(badge.activity_badge_text(me), "")
	var bar := PlayerActionBar.new()
	add_child_autofree(bar)
	bar.refresh(
		{
			&"eat_snack": {"ok": true, "label": "吃零食（4）"},
			&"read_book": {"ok": false, "reason": "你还没有课外书。", "books": 0}
		}
	)
	assert_eq(bar.button_text_of(&"eat_snack"), "吃零食（4）")
	assert_true(bar.button_disabled_of(&"read_book"))


func test_leave_last_break_enters_report_without_next_day_tick() -> void:
	var c := _core()
	for _i in range(4):
		c.advance_phase()
	c.finish_time_boundary()
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	assert_true(clock.bind_core(c))
	clock.set_process(false)
	assert_true(bool(c.player_action("leave_class", -1).get("ok", false)))
	assert_true(clock.skip_absent_break())
	assert_eq(c.global_tick(), 480)
	assert_eq(str(clock.snapshot()["mode"]), "report")
	assert_eq(c.tick_in_phase(), 0)
