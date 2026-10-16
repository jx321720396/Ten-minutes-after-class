extends GutTest
## D9：压力爆发 + 跨天衰减（§3.5 / §10.22 / §10.29）。
##
## 手算值与 tools/test_core.py §1–§4 逐条对齐。老师版已删除深/浅层敌对（_h_deep）、
## 信任（_t）与信念（_b_a）及性格倍率，相应回归用例一并移除。

var _tables: Dictionary


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()


func _core() -> SimCore:
	return SimCore.new(12345, 16, _tables)


func _n(core: SimCore) -> int:
	return core.node_count()


# ------------------------------------------------------------------ 手算例（§1 补齐）
func test_relation_modulation_upper_clamp() -> void:
	var core := _core()
	var a := core._a
	var h := core._h
	a[1] = 100.0
	h[1] = 0.0
	core._a = a
	core._h = h
	assert_almost_eq(core._m_relation(0, 1), 1.0, 0.001, "M(100,0) 上限 +1.0")


# ------------------------------------------------------------------ 负反馈专项（§2）
func test_negative_feedback_stronger_on_low_affinity() -> void:
	var core := _core()
	var a := core._a
	var h := core._h
	h[1] = 0.0
	core._h = h
	a[1] = 20.0
	core._a = a
	core._settled.clear()
	var b1 := core.affinity(0, 1)
	core._apply_event(0, 1, "topic_affinity")
	var d_low := core.affinity(0, 1) - b1
	a[1] = 90.0
	core._a = a
	core._settled.clear()
	var b2 := core.affinity(0, 1)
	core._apply_event(0, 1, "topic_affinity")
	var d_high := core.affinity(0, 1) - b2
	assert_true(d_low > d_high, "A=20 增量(%.3f) 应大于 A=90 增量(%.3f)" % [d_low, d_high])
	assert_true(d_high < 0.6, "A=90 增量被压到极小（%.3f < 0.6）" % d_high)


# ------------------------------------------------------------------ 事件去重（§3）
func test_apply_event_dedup_returns_false() -> void:
	var core := _core()
	core._apply_event(0, 1, "topic_affinity")
	var before := core.affinity(0, 1)
	var ok := core._apply_event(0, 1, "topic_affinity")  # 同日同相位 → 应被跳过
	assert_true(ok == false and core.affinity(0, 1) == before, "重复事件返回 false 且不改数值")


# ------------------------------------------------------------------ 不变式（§4）
func test_axes_within_range_after_day() -> void:
	var core := _core()
	core.run_day()
	var n := _n(core)
	var ok := true
	for i in range(n):
		for j in range(n):
			if i == j:
				continue
			ok = ok and core.affinity(i, j) >= 0.0 and core.affinity(i, j) <= 100.0
			ok = ok and core.hostility(i, j) >= 0.0 and core.hostility(i, j) <= 100.0
	assert_true(ok, "好感/敌对落在 [0,100]")


func test_stress_within_range_after_day() -> void:
	var core := _core()
	core.run_day()
	var n := _n(core)
	var ok := true
	for i in range(n):
		ok = ok and core.stress(i) >= 0.0 and core.stress(i) <= 100.0
	assert_true(ok, "压力落在 [0,100]")


func test_same_seed_same_result() -> void:
	var core1 := SimCore.new(12345, 16, _tables)
	var core2 := SimCore.new(12345, 16, _tables)
	core1.run_day()
	core2.run_day()
	assert_eq(core1.report(), core2.report(), "同种子同结果（可复现）")


# ------------------------------------------------------------------ 压力爆发（D9，§3.5）
func test_stress_burst_drops_stress_without_knot() -> void:
	var core := _core()
	core._probs["burst_p_max"] = 1.0  # 强制必爆（severity=1.0 → p=1.0，random()<1.0 恒真）
	var stress := core._stress
	stress[0] = 100.0
	core._stress = stress
	core._try_burst()
	assert_almost_eq(core._stress[0], 60.0, 0.001, "爆发后压力回落 40（100 → 60）")
	assert_eq(core._knot_days[0], 0, "心结不再由爆发给出（§5.3 改为崩溃时本人与正交邻座获得）")
	assert_eq(core._stats["bursts"], 1, "bursts 计数 +1")

