extends GutTest
## D9：压力爆发 + 跨天衰减 + 深/浅层敌对（§3.5 / §10.22 / §10.29）+ 信念遗忘回归。
##
## 补齐 test_core.py §1–§4 中 D8 尚未覆盖的手算例与不变式（§3.5/§3.6 的 do_report/do_tease
## 方向断言依赖 D10 行为决策，留待 D10 接入）。手算值与 tools/test_core.py 逐条对齐。

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


# ------------------------------------------------------------------ 手算例（§1 补齐）
func test_personality_multiplier_lower_clamp() -> void:
	var core := _core()
	var row := {"w_e": "-1.0", "w_s": "-1.0", "w_f": "-1.0", "w_j": "-1.0"}
	_set_dims0(core, 100.0, 100.0, 100.0, 100.0)   # 1 + (−4) = −3 → 钳到下限
	assert_almost_eq(core._mult_personality(row, 0), 0.1, 0.001, "全负权重 → 下限 0.1 生效")


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
	_set_dims0(core, 100.0, 50.0, 50.0, 50.0)   # 倍率 1.2
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
	_set_dims0(core, 100.0, 50.0, 50.0, 50.0)
	core._apply_event(0, 1, "topic_affinity")
	var before := core.affinity(0, 1)
	var ok := core._apply_event(0, 1, "topic_affinity")   # 同日同相位 → 应被跳过
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
			ok = ok and core.trust(i, j) >= 0.0 and core.trust(i, j) <= 100.0
	assert_true(ok, "所有关系轴落在 [0,100]")


func test_stress_within_range_after_day() -> void:
	var core := _core()
	core.run_day()
	var n := _n(core)
	var ok := true
	for i in range(n):
		ok = ok and core.stress(i) >= 0.0 and core.stress(i) <= 100.0
	assert_true(ok, "压力落在 [0,100]")


func test_same_seed_same_result() -> void:
	var core1 := SimCore.new(12345, 8, _tables)
	var core2 := SimCore.new(12345, 8, _tables)
	core1.run_day()
	core2.run_day()
	assert_eq(core1.report(), core2.report(), "同种子同结果（可复现）")


# ------------------------------------------------------------------ 压力爆发（D9，§3.5）
func test_stress_burst_drops_stress_and_sets_knot() -> void:
	var core := _core()
	core._probs["burst_p_max"] = 1.0          # 强制必爆（severity=1.0 → p=1.0，random()<1.0 恒真）
	var stress := core._stress
	stress[0] = 100.0
	core._stress = stress
	core._try_burst()
	assert_almost_eq(core._stress[0], 60.0, 0.001, "爆发后压力回落 40（100 → 60）")
	assert_eq(core._knot_days[0], 6, "severity=1.0 → 心结 3×(1+1)=6 天")
	assert_eq(core._stats["bursts"], 1, "bursts 计数 +1")


func test_spread_knot_contagion_prefers_strong_relations() -> void:
	var core := _core()
	var a := core._a
	a[1] = 90.0                              # node 0 → 1 关系最鲜明（|90−0|=90）
	core._a = a
	core._spread_knot(0, 0.0)                # severity=0 → days_eff=3，pool 只取 ratio=0.25 里的最强关系
	assert_eq(core._knot_days[1], 3, "关系最鲜明者被波及（心结 3 天）")
	assert_eq(core._knot_days[2], 0, "泛泛之交不受波及")


# ------------------------------------------------------------------ 跨天衰减 + 深/浅层敌对（D9，§10.22/§10.29）
func test_cross_day_decay_separates_deep_and_surface_hostility() -> void:
	var core := _core()
	var n := _n(core)
	var idx := 1                              # (0,1)
	var a := core._a
	var h := core._h
	var hd := core._h_deep
	var t := core._t
	var stress := core._stress
	a[idx] = 100.0
	h[idx] = 50.0
	hd[idx] = 20.0
	t[idx] = 80.0
	stress[0] = 50.0
	core._a = a
	core._h = h
	core._h_deep = hd
	core._t = t
	core._stress = stress
	core._settle_day()
	# decay_a_no_interact=0.86 / deep_decay=0.995 / decay_h=0.95 / decay_t=0.93 / retain_s=0.735
	assert_almost_eq(core._a[idx], 86.0, 0.0001, "好感无互动衰减 ×0.86")
	assert_almost_eq(core._h_deep[idx], 19.9, 0.0001, "深层 ×0.995")
	var h_expected := 19.9 + maxf(0.0, 50.0 - 19.9) * 0.95
	assert_almost_eq(core._h[idx], h_expected, 0.0001, "总敌对 = 深层 + 表层×0.95")
	assert_true(core._h[idx] >= core._h_deep[idx] - 1e-9, "深层是底线（H ≥ H_deep）")
	assert_almost_eq(core._t[idx], 74.4, 0.0001, "信任 ×0.93")
	assert_almost_eq(core._stress[0], 36.75, 0.0001, "压力 ×0.735")


func test_cross_day_decay_preserves_deep_as_floor() -> void:
	var core := _core()
	var n := _n(core)
	var idx := 1
	var h := core._h
	var hd := core._h_deep
	h[idx] = 10.0                              # 总敌对 < 深层（表层为负 → 夹到 0）
	hd[idx] = 20.0
	core._h = h
	core._h_deep = hd
	core._settle_day()
	assert_almost_eq(core._h[idx], core._h_deep[idx], 0.0001, "表层夹到 0：H 退到深层底线")


# ------------------------------------------------------------------ 信念遗忘回归（D9，§18.9）
func test_belief_decay_pulls_toward_prior() -> void:
	var core := _core()
	var idx := 1                              # (0,1)
	var ba := core._b_a
	ba[idx] = 80.0
	core._b_a = ba
	core._settle_day()
	# lambda_b=0.02 / prior_a=40 → 80 + 0.02×(40−80) = 79.2
	assert_almost_eq(core._b_a[idx], 79.2, 0.0001, "信念向先验缓慢回落")
