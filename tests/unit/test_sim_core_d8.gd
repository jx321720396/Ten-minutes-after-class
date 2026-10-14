extends GutTest
## D8：统一影响公式（round/sat/关系调制/事件写入）+ 涓流结算。
##
## 手算例与 tools/test_core.py §1–§2 逐条对拍（GDScript 侧，私有方法直调）。
## 老师版已删除性格倍率（mult_personality）与影响力传导（transmission）。

var _tables: Dictionary


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()


func _core() -> SimCore:
	return SimCore.new(12345, 16, _tables)


func _n(core: SimCore) -> int:
	return core.node_count()


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


func test_apply_event_chain() -> void:
	var core := _core()
	var a := core._a
	var h := core._h
	a[1] = 60.0
	h[1] = 0.0
	core._a = a
	core._h = h
	var before := core.affinity(0, 1)
	core._apply_event(0, 1, "topic_affinity")  # base=3 → 无性格倍率 → sat → ×负反馈
	assert_almost_eq(core.affinity(0, 1) - before, 1.1, 0.011, "话题共鸣增量 +1.1（软饱和/负反馈/round）")


func test_study_drip_raises_stress() -> void:
	var core := _core()
	core.run_day()
	var any_positive := false
	for i in range(_n(core)):
		if core.stress(i) > 0.0:
			any_positive = true
	assert_true(any_positive, "涓流结算后压力已上升（study drip）")
