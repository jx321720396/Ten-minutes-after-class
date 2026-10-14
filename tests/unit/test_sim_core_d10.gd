extends GutTest
## D10：闲聊加入判定读真值 + 观察层（簇/孤立只读）。
##
## 老师版已删除 7 行为（调侃/举报/排挤/安慰/道歉/传纸条/观察）与信念 B / 透明度 / 深层敌对，
## 相应用例移除。观察层不再经透明度过滤，恒读真值 A/H、零写入。

var _tables: Dictionary


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()


func _core() -> SimCore:
	return SimCore.new(12345, 16, _tables)


func _n(core: SimCore) -> int:
	return core.node_count()


func _idx(core: SimCore, i: int, j: int) -> int:
	return i * core.node_count() + j


# ------------------------------------------------------------------ §4 不变式：tau > 0 / 决策读真值
func test_tau_never_nonpositive() -> void:
	var core := _core()
	var n := _n(core)
	for i in range(n):
		var stress := core._stress
		stress[i] = 100.0  # 触发压力放大分支（tau × tau_stress_mult）
		core._stress = stress
		assert_true(core._tau(i) >= 0.01, "tau 有下限 0.01（恒为正）")


func test_join_score_reads_truth_affinity() -> void:
	var core := _core()
	var n := _n(core)
	# i=0, j=1；设 j 无压力，使 score 只受真值 A[j][i] 影响
	var stress := core._stress
	stress[1] = 0.0
	core._stress = stress
	var a := core._a
	a[1 * n + 0] = 90.0  # 真值 A[j][i]=A[1][0]
	core._a = a
	var s1 := core._join_score(0, 1)
	a[1 * n + 0] = 20.0  # 改真值 → score 应变（判定读真值 §6.4）
	core._a = a
	var s2 := core._join_score(0, 1)
	assert_almost_eq(s1 - s2, 70.0, 1e-9, "join_score 读真值 A[j][i]（改真值 → score 变）")


func test_join_feedback_reads_truth() -> void:
	var core := _core()
	var n := _n(core)
	# i=0, j=1；设 j 无压力，使显示成功率只受真值 A[j][i] 影响
	var stress := core._stress
	stress[1] = 0.0
	core._stress = stress
	var a := core._a
	a[1 * n + 0] = 90.0  # 真值高 → 显示成功率应高
	core._a = a
	var p1: float = core._join_feedback(0, 1)["p"]
	a[1 * n + 0] = 10.0  # 改真值 → 显示成功率应变
	core._a = a
	var p2: float = core._join_feedback(0, 1)["p"]
	assert_true(p1 > p2, "join_feedback 读真值 A[j][i]（改真值 → 显示成功率变）")


func test_softmax_returns_valid_index() -> void:
	var core := _core()
	var idx := core._softmax([1.0, 2.0, 3.0], 1.0)
	assert_true(idx >= 0 and idx < 3, "softmax 返回有效下标")


# ------------------------------------------------------------------ 观察层（簇 / 孤立，只读）
func test_observer_cluster_readonly() -> void:
	var core := _core()
	var n := _n(core)
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
	var clusters := core.get_clusters(0)
	assert_true(clusters.size() >= 1, "存在 ≥1 个簇")
	assert_eq(clusters[0].size(), 3, "簇 0 有 3 人")
	assert_true(clusters[0].has(0) and clusters[0].has(1) and clusters[0].has(2), "0/1/2 成簇")
	assert_eq(core.affinity(0, 1), 90.0, "观察层不写好感矩阵")


func test_observer_isolated_detection() -> void:
	var core := _core()
	var n := _n(core)
	var a := core._a
	for i in range(n):
		for j in range(n):
			if i != j:
				a[i * n + j] = 50.0
	for i in range(n):
		if i != 3:
			a[i * n + 3] = 10.0  # 他人→3 很低，而 3→他人 正常 → 被孤立
	core._a = a
	var iso := core.get_isolated(0)
	assert_true(iso.has(3), "3 被识别为孤立者：%s" % str(iso))
