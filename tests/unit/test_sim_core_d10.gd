extends GutTest
## D10：7 行为决策与效果 + 观察层（簇/孤立只读）。
##
## 补齐 tools/test_core.py §3.5（举报作用对象）、§3.6（羞辱 hurt_day 方向）、
## §4（tau > 0 / 决策读信念 B 而非真值 A[j][i]）。行为函数接 _mark_hurt(施害者,受害者)，
## 观察层经透明度过滤、零写入。手算值与 tools/core_sim.py 逐条对齐。

var _tables: Dictionary


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()


func _core() -> SimCore:
	return SimCore.new(12345, 8, _tables)


func _n(core: SimCore) -> int:
	return core.node_count()


func _idx(core: SimCore, i: int, j: int) -> int:
	return i * core.node_count() + j


## 把 node 的 MBTI 四维设成 [e, n, f, p]（dims 为 dim-major）。
func _set_dims(core: SimCore, node: int, e: float, n_dim: float, f: float, p: float) -> void:
	var nn := _n(core)
	var dims := core._dims
	dims[node] = e
	dims[nn + node] = n_dim
	dims[2 * nn + node] = f
	dims[3 * nn + node] = p
	core._dims = dims


# ------------------------------------------------------------------ §3.5 举报作用对象
func test_report_affects_target_not_reporter() -> void:
	var core := _core()
	var n := _n(core)
	var reporter := 0
	var target := 2
	_set_dims(core, target, 50.0, 50.0, 50.0, 50.0)   # 四维中性 → M_personality = 1.0
	var stress := core._stress
	stress[reporter] = 0.0
	stress[target] = 0.0
	core._stress = stress
	var h := core._h
	h[_idx(core, reporter, target)] = 90.0
	core._h = h
	core._settled.clear()
	var h_ji_before := core._h[_idx(core, target, reporter)]
	core._do_report(reporter, target)
	# 效果落在被举报者身上：压力 +4.3、敌对记在「被举报者→举报者」+4.2（major → 深层）
	assert_almost_eq(core._stress[target], 4.3, 0.001, "被举报者压力 +4.3")
	assert_almost_eq(core._stress[reporter], 0.0, 0.001, "举报者不承担这份压力")
	assert_almost_eq(core._h[_idx(core, target, reporter)], h_ji_before + 4.2, 0.001, "敌对记在 被举报者→举报者")
	assert_almost_eq(core._h_deep[_idx(core, target, reporter)], 4.2, 0.001, "深层敌对记在 被举报者→举报者")
	assert_almost_eq(core._h_deep[_idx(core, reporter, target)], 0.0, 1e-9, "举报者一侧无深层")
	# 举报者对被举报者的敌对回落 5（§10.2）
	assert_almost_eq(core._h[_idx(core, reporter, target)], 85.0, 1e-9, "举报者对被举报者敌对回落 5")
	# hurt_day 记施害者视角
	assert_eq(core._hurt_day[_idx(core, reporter, target)], core.day(), "hurt_day 记 举报者→被举报者")
	assert_eq(core._hurt_day[_idx(core, target, reporter)], -999, "反向条目不被污染")


# ------------------------------------------------------------------ §3.6 羞辱 hurt_day 方向
func test_tease_humiliation_hurt_day_direction() -> void:
	var core := _core()
	var n := _n(core)
	var teaser := 0
	var target := 1
	var a := core._a
	var h := core._h
	a[_idx(core, teaser, target)] = 20.0   # 保证走嘲讽档（A < 25）
	h[_idx(core, teaser, target)] = 80.0   # 保证走嘲讽档（H ≥ 40）
	core._a = a
	core._h = h
	core._do_tease(teaser, target, [2, 3, 4])   # ≥3 人围观 → 当众羞辱
	assert_eq(core._hurt_day[_idx(core, teaser, target)], core.day(), "hurt_day 记 施害者→受害者")
	assert_eq(core._hurt_day[_idx(core, target, teaser)], -999, "反向不被污染")
	assert_eq(core._stats["humiliations"], 1, "当众羞辱计数 +1")
	assert_eq(core._stats["tease_fail"], 1, "嘲讽档计入 tease_fail")


# ------------------------------------------------------------------ §4 不变式：tau > 0 / 决策读信念
func test_tau_never_nonpositive() -> void:
	var core := _core()
	var n := _n(core)
	for i in range(n):
		var stress := core._stress
		stress[i] = 100.0   # 触发压力放大分支（tau × tau_stress_mult）
		core._stress = stress
		assert_true(core._tau(i) >= 0.01, "tau 有下限 0.01（恒为正）")
	# 极端高 P（弱 J）：tau 放大，仍被下限兜住
	var dims := core._dims
	dims[3 * n] = 100.0
	core._dims = dims
	assert_true(core._tau(0) >= 0.01, "高 P 者 tau 也 ≥ 0.01")


func test_join_score_reads_truth_not_belief() -> void:
	var core := _core()
	var n := _n(core)
	# i=0, j=1；设 j 无外向、无压力，使 score 只受真值 A[j][i] 影响
	var dims := core._dims
	dims[1] = 50.0            # E_j=50 → (E−50)×0.3 = 0
	core._dims = dims
	var stress := core._stress
	stress[1] = 0.0
	core._stress = stress
	var a := core._a
	a[1 * n + 0] = 90.0       # 真值 A[j][i]=A[1][0]
	core._a = a
	var s1 := core._join_score(0, 1)
	a[1 * n + 0] = 20.0       # 改真值 → score 应变（判定读真值 §6.4）
	core._a = a
	var s2 := core._join_score(0, 1)
	assert_almost_eq(s1 - s2, 70.0, 1e-9, "join_score 读真值 A[j][i]（改真值 → score 变）")
	core._b_a[0 * n + 1] = 90.0   # 改信念 B_A → score 不应变
	var s3 := core._join_score(0, 1)
	assert_almost_eq(s3, s2, 1e-9, "改信念 B_A 不影响 score（判定不读信念）")


func test_join_feedback_reads_belief_not_truth() -> void:
	var core := _core()
	var n := _n(core)
	# i=0, j=1；设 j 无外向、无压力，使显示成功率只受信念 B_A 影响
	var dims := core._dims
	dims[1] = 50.0
	core._dims = dims
	var stress := core._stress
	stress[1] = 0.0
	core._stress = stress
	core._b_a[0 * n + 1] = 90.0   # 信念高 → 显示成功率应高
	var p1: float = core._join_feedback(0, 1)["p"]
	core._b_a[0 * n + 1] = 10.0   # 改信念 → 显示成功率应变
	var p2: float = core._join_feedback(0, 1)["p"]
	assert_true(p1 > p2, "join_feedback 读信念 B_A（改信念 → 显示成功率变）")
	var a := core._a
	a[1 * n + 0] = 90.0           # 改真值 → 显示成功率不应变（展示不泄露真值 §10.32.3）
	core._a = a
	var p3: float = core._join_feedback(0, 1)["p"]
	assert_almost_eq(p3, p2, 1e-9, "改真值 A[j][i] 不影响显示成功率")


func test_softmax_returns_valid_index() -> void:
	var core := _core()
	var idx := core._softmax([1.0, 2.0, 3.0], 1.0)
	assert_true(idx >= 0 and idx < 3, "softmax 返回有效下标")


# ------------------------------------------------------------------ 信念观测（§11）
func test_observe_updates_belief_toward_truth() -> void:
	var core := _core()
	var n := _n(core)
	_set_dims(core, 1, 50.0, 50.0, 50.0, 50.0)  # 中性 → 外观偏差 0
	var o := core._o
	o[1] = 100.0                               # 全透明 → 无噪声
	core._o = o
	var t := core._t
	t[0 * n + 1] = 100.0                       # 全信任 → eta 满
	core._t = t
	var a := core._a
	a[1 * n + 0] = 100.0                       # 真值 j→i 好感 100
	core._a = a
	core._b_a[0 * n + 1] = 20.0                # 初始信念
	core._observe(0, 1, "affinity")
	# eta = 0.25 × (0.3 + 0.7×1.0) = 0.25；20 + 0.25×(100−20) = 40
	assert_almost_eq(core._b_a[0 * n + 1], 40.0, 0.001, "信念按 eta 向真值移动")


# ------------------------------------------------------------------ 观察层（簇 / 孤立，只读）
func test_observer_cluster_readonly() -> void:
	var core := _core()
	var n := _n(core)
	var o := core._o
	for j in range(n):
		o[j] = 100.0
	core._o = o
	var a := core._a
	for i in range(n):
		for j in range(n):
			if i != j:
				a[i * n + j] = 30.0
	for i in [0, 1, 2]:
		for j in [0, 1, 2]:
			if i != j:
				a[i * n + j] = 90.0
	core._a = a
	var clusters := core.get_clusters(4)
	assert_true(clusters.size() >= 1, "存在 ≥1 个簇")
	assert_eq(clusters[0].size(), 3, "簇 0 有 3 人")
	assert_true(clusters[0].has(0) and clusters[0].has(1) and clusters[0].has(2), "0/1/2 成簇")
	assert_eq(core.affinity(0, 1), 90.0, "观察层不写好感矩阵")


func test_observer_isolated_detection() -> void:
	var core := _core()
	var n := _n(core)
	var o := core._o
	for j in range(n):
		o[j] = 100.0
	core._o = o
	var a := core._a
	for i in range(n):
		for j in range(n):
			if i != j:
				a[i * n + j] = 50.0
	for i in range(n):
		if i != 3:
			a[i * n + 3] = 10.0   # 他人→3 很低，而 3→他人 正常 → 被孤立
	core._a = a
	var iso := core.get_isolated(4)
	assert_true(iso.has(3), "3 被识别为孤立者：%s" % str(iso))
