extends GutTest
## D8：统一影响公式（round/sat/关系调制/性格倍率/事件写入）+ 传导 + 涓流结算。
##
## 手算例与 tools/test_core.py §1–§2 逐条对拍（GDScript 侧，私有方法直调）。

var _tables: Dictionary


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()


func _core() -> SimCore:
	return SimCore.new(12345, 8, _tables)


func _n(core: SimCore) -> int:
	return core.node_count()


## 把节点 0 的 MBTI 四维设成 [e, n, f, p]（dims 为 dim-major）。
func _set_dims0(core: SimCore, e: float, n: float, f: float, p: float) -> void:
	var nn := _n(core)
	var dims := core._dims
	dims[0] = e
	dims[nn] = n
	dims[2 * nn] = f
	dims[3 * nn] = p
	core._dims = dims


func test_round_to_tenth() -> void:
	var core := _core()
	assert_almost_eq(core._r1(0.75), 0.8, 0.001, "round(0.75) = 0.8")
	assert_almost_eq(core._r1(1.175), 1.2, 0.001, "round(1.175) = 1.2")
	assert_almost_eq(core._r1(0.04), 0.0, 0.001, "round(0.04) = 0.0（过小增量被舍去）")


func test_soft_saturation() -> void:
	var core := _core()
	assert_almost_eq(core._sat(5.7, "affinity"), 4.64, 0.01, "sat(5.7, U=25) ≈ 4.64")
	assert_almost_eq(core._sat(0.5, "affinity"), 0.49, 0.02, "sat(0.5) ≈ 0.49（小量近似直通）")


func test_relation_modulation() -> void:
	var core := _core()
	var a := core._a
	var h := core._h
	a[1] = 65.0
	h[1] = 0.0
	core._a = a
	core._h = h
	assert_almost_eq(core._m_relation(0, 1), 1.0, 0.001, "M(65,0) = +1.0")
	a[1] = 30.0
	h[1] = 45.0
	core._a = a
	core._h = h
	assert_almost_eq(core._m_relation(0, 1), -0.3, 0.001, "M(30,45) = −0.3（敌对压过好感 → 反转）")


func test_personality_multiplier() -> void:
	var core := _core()
	var row := {"w_e": "0.2", "w_s": "0", "w_f": "0", "w_j": "0"}
	_set_dims0(core, 85.0, 50.0, 50.0, 50.0)
	assert_almost_eq(core._mult_personality(row, 0), 1.14, 0.005, "E=85, w_E=+0.2 → 1.14")
	_set_dims0(core, 0.0, 50.0, 50.0, 50.0)
	assert_almost_eq(core._mult_personality(row, 0), 0.8, 0.001, "E=0 → 倍率 0.8（未下钳）")
	_set_dims0(core, 100.0, 50.0, 50.0, 50.0)
	assert_almost_eq(core._mult_personality(row, 0), 1.2, 0.001, "E=100 → 倍率 1.2（上限）")


func test_apply_event_chain() -> void:
	var core := _core()
	_set_dims0(core, 100.0, 50.0, 50.0, 50.0)   # 倍率 1.2
	var a := core._a
	var h := core._h
	a[1] = 60.0
	h[1] = 0.0
	core._a = a
	core._h = h
	var before := core.affinity(0, 1)
	core._apply_event(0, 1, "topic_affinity")   # base=3 → 3×1.2×1.0 → sat → ×负反馈
	assert_almost_eq(core.affinity(0, 1) - before, 1.2, 0.011, "话题共鸣增量 +1.2（含性格/软饱和/负反馈/round）")


func test_transmission_fires_twice_per_day() -> void:
	var core := _core()
	core.run_day()
	assert_true(core.report().contains("传导结算 2 次"), "传导每 240 tick 结算一次（一天 2 次）")


func test_study_drip_raises_stress() -> void:
	var core := _core()
	core.run_day()
	var any_positive := false
	for i in range(_n(core)):
		if core.stress(i) > 0.0:
			any_positive = true
	assert_true(any_positive, "涓流结算后压力已上升（study drip）")
