extends GutTest
## 行为组件的注册、分发、RNG 与生命周期契约（老师版行为集：只 chat + roughhouse）。

const REGISTRY_PATH := "res://scripts/systems/behaviors/behavior_registry.gd"
const EXPECTED := [
	&"chat",
	&"roughhouse"
]


func test_all_behaviors_are_registered() -> void:
	assert_true(ResourceLoader.exists(REGISTRY_PATH), "独立行为注册表必须存在")
	if not ResourceLoader.exists(REGISTRY_PATH):
		return
	var c := SimCore.new(12345, 16, ConfigLoader.new().load_all())
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


func test_registry_dispatches_kept_behaviors() -> void:
	var c := _core()
	assert_true(c._behavior_registry.execute(&"chat", 0, 1), "闲聊走注册表分发")
	assert_true(c._behavior_registry.execute(&"roughhouse", 0, 1), "打闹走注册表分发")


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
	first._do_chat(0, 1)
	assert_eq(_digest(second), before, "一个局的行为不污染另一个局")


func _core() -> SimCore:
	return SimCore.new(12345, 16, ConfigLoader.new().load_all())


func _digest(c: SimCore) -> PackedByteArray:
	var values: Array = []
	for field in [
		"_a",
		"_h",
		"_stress",
		"_grade",
		"_current_act",
		"_in_conversation",
		"_busy_until",
		"_busy_phase",
		"_busy_act",
		"_last_finished",
		"_stats",
		"_settled"
	]:
		values.append(c.get(field))
	values.append(c._rng._mt)
	values.append(c._rng._mti)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(values))
	return hashing.finish()
