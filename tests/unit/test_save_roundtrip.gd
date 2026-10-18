extends GutTest
## 存档最小闭环：内核序列化往返、续推一致性、随机流恢复、配置指纹。

var _tables: Dictionary


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()


func _core(seed_value: int = 12345) -> SimCore:
	return SimCore.new(seed_value, 16, _tables)


## 模拟真实存档：export → JSON 序列化 → 解析 → 新建内核 → restore。
func _roundtrip(core: SimCore) -> SimCore:
	var text := JSON.stringify({"core": SimCoreSerializer.export_state(core)})
	var parsed: Dictionary = JSON.parse_string(text)
	var rebuilt := SimCore.new(int(core.seed()), int(core.node_count()), _tables)
	assert_true(SimCoreSerializer.restore_state(rebuilt, parsed["core"]), "内核恢复应成功")
	return rebuilt


func _assert_core_equal(a: SimCore, b: SimCore, label: String) -> void:
	var n := int(a.node_count())
	for i in range(n):
		for j in range(n):
			assert_almost_eq(
				a.affinity(i, j), b.affinity(i, j), 1e-9, "%s affinity(%d,%d)" % [label, i, j]
			)
			assert_almost_eq(
				a.hostility(i, j), b.hostility(i, j), 1e-9, "%s hostility(%d,%d)" % [label, i, j]
			)
		assert_almost_eq(a.stress(i), b.stress(i), 1e-9, "%s stress(%d)" % [label, i])
		assert_almost_eq(a.grade(i), b.grade(i), 1e-9, "%s grade(%d)" % [label, i])
		assert_almost_eq(a.vitality(i), b.vitality(i), 1e-9, "%s vitality(%d)" % [label, i])
		assert_almost_eq(a.gain_today(i), b.gain_today(i), 1e-9, "%s gain_today(%d)" % [label, i])
	assert_eq(a.global_tick(), b.global_tick(), "%s global_tick" % label)
	assert_eq(a.day(), b.day(), "%s day" % label)
	assert_eq(a.phase_index(), b.phase_index(), "%s phase_index" % label)
	assert_eq(a.tick_in_phase(), b.tick_in_phase(), "%s tick_in_phase" % label)


func test_rng_roundtrip() -> void:
	var a := MtRandom.new(99)
	for _i in range(8):
		a.random()
	# 快照 a 的当前状态 → 恢复进 b，之后两者后续随机序列应逐点一致。
	var b := MtRandom.new(0)
	b.restore_state(a.export_state())
	var draws_a: Array = []
	var draws_b: Array = []
	for _i in range(8):
		draws_a.append(a.random())
		draws_b.append(b.random())
	assert_eq(draws_a, draws_b, "恢复后随机序列一致")


func test_export_restore_mid_break() -> void:
	var a := _core()
	for _i in range(50):
		a.advance_tick()
	var b := _roundtrip(a)
	_assert_core_equal(a, b, "课间中途往返")


func test_continue_consistency() -> void:
	var a := _core()
	for _i in range(50):
		a.advance_tick()
	var b := _roundtrip(a)
	for _i in range(30):
		a.advance_tick()
		b.advance_tick()
	_assert_core_equal(a, b, "续推")


func test_cross_day_roundtrip() -> void:
	var a := _core()
	a.run_day()
	var b := _roundtrip(a)
	_assert_core_equal(a, b, "跨天往返")


func test_restore_rejects_wrong_seed() -> void:
	var a := _core()
	for _i in range(20):
		a.advance_tick()
	var rebuilt := SimCore.new(99999, 16, _tables)
	assert_false(
		SimCoreSerializer.restore_state(rebuilt, SimCoreSerializer.export_state(a)), "seed 不符应拒绝"
	)


func test_restore_rejects_wrong_version() -> void:
	var a := _core()
	var exported: Dictionary = SimCoreSerializer.export_state(a)
	exported["version"] = 999
	var rebuilt := _core()
	assert_false(SimCoreSerializer.restore_state(rebuilt, exported), "版本不符应拒绝")


func test_config_fingerprint_stable() -> void:
	var tables2 := ConfigLoader.new().load_all()
	assert_eq(
		SimCoreSerializer.config_fingerprint(_tables),
		SimCoreSerializer.config_fingerprint(tables2),
		"配置指纹跨加载稳定"
	)
