extends GutTest
## 观察（§10.3.1）：玩家独有的**只读**行为 —— 零副作用是硬约束，必须逐条钉住。

const NODES := 8


func _core(seed_num: int = 12345) -> SimCore:
	return SimCore.from_npc(seed_num, NODES, ConfigLoader.new().load_all())


func test_observe_is_registered_and_player_only() -> void:
	var c := _core()
	assert_true(c._behavior_registry.has_behavior(&"observe"), "观察组件已注册")
	assert_true(SimCore.PLAYER_KINDS.has("observe"), "玩家可用")
	assert_false(c._behavior_registry.has_behavior(&"ask_help"), "已删除的求助不在注册表")


func test_observe_emits_truth_plus_belief_clues() -> void:
	var c := _core()
	var me := int(c.node_count()) - 1
	var events: Array = []
	c.event_sink = func(e: Dictionary) -> void: events.append(e)
	c._do_observe(me, 0)
	assert_eq(events.size(), 1, "一次观察一条事件")
	var payload: Dictionary = events[0].payload
	assert_eq(str(payload.kind), "observe")
	var clues: Array = payload.clues
	assert_gte(clues.size(), 3, "至少 2 条真实 + 1 条信念")
	var truth := 0
	var belief := 0
	for clue in clues:
		if bool(clue.get("belief", false)):
			belief += 1
		else:
			truth += 1
	assert_eq(truth, 2, "真实信息 2 条（O < 50 时不加 T）")
	assert_eq(belief, 1, "信念信息 1 条（他以为你怎么看他）")


func test_observe_has_no_side_effects_on_the_target() -> void:
	var c := _core()
	var me := int(c.node_count()) - 1
	var a0 := c.affinity(0, me)
	var h0 := c.hostility(0, me)
	var stress0 := c.stress(me)
	var target_busy := int(c._busy_until[0])
	c._do_observe(me, 0)
	assert_eq(c.affinity(0, me), a0, "不写对方对玩家的好感")
	assert_eq(c.hostility(0, me), h0, "不写敌对")
	assert_eq(c.stress(me), stress0, "观察不产生压力变化")
	assert_eq(int(c._busy_until[0]), target_busy, "不占用对象（对象不知情）")
	assert_gt(int(c._busy_until[me]), int(c._global_tick), "占用的是玩家自己的时间槽")


func test_observe_counts_its_stat_once_per_use() -> void:
	var c := _core()
	var me := int(c.node_count()) - 1
	assert_eq(int(c._stats.get("observes", 0)), 0, "开局没观察过")
	c._do_observe(me, 0)
	assert_eq(int(c._stats["observes"]), 1)


func test_observe_is_reachable_through_player_action() -> void:
	var c := _core()
	var me := int(c.node_count()) - 1
	var result: Dictionary = c.player_action("observe", 0)
	# 距离由场景几何决定，这里只钉住「要么成功、要么给出原因」——不能静默失败
	if bool(result.get("ok", false)):
		assert_gt(int(c._busy_until[me]), int(c._global_tick), "接了就占玩家自己的时间")
	else:
		assert_true(str(result.get("error", "")).length() > 0, "拒绝要给出原因")
