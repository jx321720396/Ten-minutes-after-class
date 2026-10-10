extends GutTest
## 行为组件的注册、旧入口兼容、RNG 与生命周期契约。

const REGISTRY_PATH := "res://scripts/systems/behaviors/behavior_registry.gd"
const EXPECTED := [
	&"chat",
	&"tease",
	&"report",
	&"roughhouse",
	&"exclude",
	&"comfort",
	&"apologize",
	&"pass_note",
	&"observe"
]


func test_all_behaviors_are_registered() -> void:
	assert_true(ResourceLoader.exists(REGISTRY_PATH), "独立行为注册表必须存在")
	if not ResourceLoader.exists(REGISTRY_PATH):
		return
	var c := SimCore.from_npc(12345, 16, ConfigLoader.new().load_all())
	var registry: Variant = c.get("_behavior_registry")
	assert_not_null(registry, "每局构建自己的行为组件")
	if registry == null:
		return
	assert_eq(registry.behavior_ids(), EXPECTED)
	for kind in EXPECTED:
		assert_true(registry.has_behavior(kind), str(kind))


func test_unknown_behavior_does_not_change_state_or_rng() -> void:
	var c := _core()
	var before := _digest(c)
	assert_false(c._behavior_registry.execute(&"missing_behavior", 0, 1))
	assert_eq(_digest(c), before, "未知行为不改变状态与随机数")


func test_registered_ids_are_a_read_only_copy() -> void:
	var c := _core()
	var ids: Array = c._behavior_registry.behavior_ids()
	ids.clear()
	assert_eq(c._behavior_registry.behavior_ids(), EXPECTED)


func test_component_dispatch_matches_all_compatibility_entries() -> void:
	for kind in EXPECTED:
		var old_entry := _core()
		var direct := _core()
		var old_events: Array = []
		var new_events: Array = []
		old_entry.event_sink = func(e: Dictionary): old_events.append(e)
		direct.event_sink = func(e: Dictionary): new_events.append(e)
		var options := {}
		match kind:
			&"chat":
				options = {"mode": "join", "roll": 0.0}
				old_entry._do_chat_join(0, 1, 0.0)
			&"tease":
				options = {"audience": [5, 2, 3, 4]}
				old_entry._do_tease(0, 1, options.audience)
			&"exclude":
				options = {"crowd": [0, 4, 2]}
				old_entry._do_exclude(0, 1, options.crowd)
			&"roughhouse":
				options = {"bystanders": [4, 2, 3]}
				old_entry._do_roughhouse(0, 1, options.bystanders)
			_:
				old_entry.call("_do_" + str(kind), 0, 1)
		assert_true(direct._behavior_registry.execute(kind, 0, 1, options))
		assert_eq(_digest(direct), _digest(old_entry), str(kind) + " 状态与 RNG 一致")
		assert_eq(new_events, old_events, str(kind) + " 通知顺序一致")


func test_pre_rolled_join_does_not_draw_again_and_keeps_event_order() -> void:
	var c := _core()
	var events: Array = []
	c.event_sink = func(e: Dictionary): events.append(e)
	var rng_before := var_to_bytes([c._rng._mt, c._rng._mti])
	c._do_chat_join(0, 1, 0.0)
	assert_eq(var_to_bytes([c._rng._mt, c._rng._mti]), rng_before)
	assert_eq(events.size(), 2)
	assert_eq(events[0].payload.kind, "chat")
	assert_eq(events[1].payload.mode, "join")
	assert_true(events[1].payload.accepted)


func test_default_join_consumes_exactly_one_roll() -> void:
	var c := _core()
	var expected := _core()
	expected._rng.random()
	c._do_chat_join(0, 1)
	assert_eq(
		var_to_bytes([c._rng._mt, c._rng._mti]),
		var_to_bytes([expected._rng._mt, expected._rng._mti])
	)


func test_context_uses_current_arrays_after_replacement() -> void:
	var c := _core()
	var replacement := c._a.duplicate()
	replacement[1] = 88.0
	c._a = replacement
	assert_eq(c._behavior_context.affinity(0, 1), 88.0, "上下文不缓存旧矩阵")
	c._do_chat(0, 1)
	assert_gt(c.affinity(0, 1), 88.0, "结算进入当前内核矩阵")


func test_components_do_not_keep_a_finished_core_alive() -> void:
	var c := _core()
	var reference: WeakRef = weakref(c)
	var registry: RefCounted = c._behavior_registry
	var context: RefCounted = c._behavior_context
	c = null
	assert_null(reference.get_ref(), "注册表和上下文不得强引用内核")
	assert_false(context.is_bound())
	assert_false(registry.execute(&"chat", 0, 1), "已结束会话明确拒绝执行")


func test_new_games_have_independent_components_and_state() -> void:
	var first := _core()
	var second := _core()
	var before := _digest(second)
	assert_ne(first._behavior_registry, second._behavior_registry)
	first._do_report(0, 1)
	assert_eq(_digest(second), before, "一个局的行为不污染另一个局")


func _core() -> SimCore:
	return SimCore.from_npc(12345, 16, ConfigLoader.new().load_all())


func _digest(c: SimCore) -> PackedByteArray:
	var values: Array = []
	for field in [
		"_a",
		"_h",
		"_h_deep",
		"_t",
		"_stress",
		"_b_a",
		"_b_h",
		"_b_t",
		"_current_act",
		"_in_conversation",
		"_busy_until",
		"_busy_phase",
		"_busy_act",
		"_stats",
		"_hurt_day",
		"_settled",
		"_day_events"
	]:
		values.append(c.get(field))
	values.append(c._rng._mt)
	values.append(c._rng._mti)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(values))
	return hashing.finish()
