extends GutTest
## SimCore：单日时间系统（480 tick）、同种子确定性、绑定组初始化与只读访问器。

var _tables: Dictionary


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()


func _core() -> SimCore:
	return SimCore.new(12345, 8, _tables)


func test_one_day_ticks() -> void:
	var core := _core()
	var total := core.run_day()
	assert_eq(total, 480, "单日总 tick = 480（课间 100×3 + 上课 90×2）")
	assert_eq(core.global_tick(), 480, "global_tick 累计 480")
	assert_eq(core.day(), 2, "结算后推进到第 2 天")
	assert_eq(core.node_count(), 9, "8 NPC + 1 老师节点")


func test_deterministic_report() -> void:
	var a := _core()
	a.run_day()
	var b := _core()
	b.run_day()
	assert_eq(a.report(), b.report(), "同种子报告逐字节一致")


func test_couple_binding() -> void:
	var core := _core()
	# 绑定组 couple 首位陈阳=0、林晚=1（RosterSelector 固定顺序）
	assert_almost_eq(core.affinity(0, 1), 85.0, 0.001, "陈阳→林晚 好感 85")
	assert_almost_eq(core.affinity(1, 0), 85.0, 0.001, "林晚→陈阳 好感 85")
	assert_almost_eq(core.trust(0, 1), 80.0, 0.001, "陈阳→林晚 信任 80")
	assert_almost_eq(core.trust(1, 0), 80.0, 0.001, "林晚→陈阳 信任 80")


func test_uniform_binding() -> void:
	var core := _core()
	# uniform 佳豪=2：对除自己外所有人好感固定 50
	for j in range(core.node_count()):
		if j != 2:
			assert_almost_eq(core.affinity(2, j), 50.0, 0.001, "佳豪→%d 好感 50" % j)


func test_accessors_bounds() -> void:
	var core := _core()
	assert_eq(core.affinity(0, 0), 0.0, "自反好感为 0")
	assert_eq(core.affinity(-1, 0), 0.0, "负索引为 0")
	assert_eq(core.affinity(0, 999), 0.0, "越界为 0")
	assert_eq(core.opacity(-1), 0.0, "透明度负索引为 0")
	assert_eq(core.stress(core.node_count()), 0.0, "压力越界为 0")
