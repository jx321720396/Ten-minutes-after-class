extends GutTest
## SimCore：单日时间系统（480 tick）、同种子确定性、绑定组初始化与只读访问器。

var _tables: Dictionary


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()


func _core() -> SimCore:
	return SimCore.new(12345, 16, _tables)


## 按别名反查角色下标（名单顺序由洗牌决定，不固定 0/1/2）。
func _alias_idx(core: SimCore, alias: String) -> int:
	for i in range(core._chars.size()):
		if str(core._chars[i]["alias"]) == alias:
			return i
	return -1


func test_one_day_ticks() -> void:
	var core := _core()
	var total := core.run_day()
	assert_eq(total, 480, "单日总 tick = 480（课间 100×3 + 上课 90×2）")
	assert_eq(core.global_tick(), 480, "global_tick 累计 480")
	assert_eq(core.day(), 2, "结算后推进到第 2 天")
	assert_eq(core.node_count(), 16, "一局 16 名学生（2026-10-16 起没有玩家节点）")


func test_advance_tick_phase_day() -> void:
	# D11 单步推进：tick / phase / day 三种粒度
	var core := _core()
	core.advance_tick()
	assert_eq(core.global_tick(), 1, "advance_tick 推进 1 tick")
	assert_eq(core.phase_index(), 0, "仍在第一段")

	var core2 := _core()
	core2.advance_phase()
	assert_eq(core2.global_tick(), 100, "advance_phase 跑完第一段（课间 100 tick）")
	assert_eq(core2.phase_index(), 1, "进入第二段")

	var core3 := _core()
	var total := core3.advance_day()
	assert_eq(total, 480, "advance_day 单日 480 tick")
	assert_eq(core3.day(), 2, "结算后推进到第 2 天")


func test_advance_day_twice() -> void:
	# D11 跨天边界：连续两天推进游标正确复位
	var core := _core()
	core.advance_day()
	core.advance_day()
	assert_eq(core.global_tick(), 960, "两天累计 960 tick")
	assert_eq(core.day(), 3, "推进到第 3 天")


func test_event_sink_day_settled_and_behavior() -> void:
	# D11 缺口④：event_sink 回调注入，内核零 autoload 依赖
	var core := _core()
	var events: Array = []
	core.event_sink = func(e: Dictionary) -> void: events.append(e)
	core._do_chat(0, 1)  # 手动触发一次闲聊（结算走统一影响公式）
	core.run_day()
	assert_true(events.size() > 0, "应派发事件")
	assert_eq(events[0]["type"], "event_happened", "首条为 event_happened")
	assert_eq(events[-1]["type"], "day_settled", "末条为 day_settled")
	assert_eq(events[-1]["payload"]["day"], 1, "day_settled 结算第 1 天")


func test_deterministic_report() -> void:
	var a := _core()
	a.run_day()
	var b := _core()
	b.run_day()
	assert_eq(a.report(), b.report(), "同种子报告逐字节一致")


func test_couple_binding() -> void:
	# 随机名单下绑定组不一定入选，改用 seed 68（陈阳/林晚/佳豪均入选）验证绑定逻辑。
	var core := SimCore.new(68, 16, _tables)
	var a := _alias_idx(core, "陈阳")
	var b := _alias_idx(core, "林晚")
	assert_true(a >= 0 and b >= 0, "seed 68 名单包含陈阳与林晚")
	assert_almost_eq(core.affinity(a, b), 85.0, 0.001, "陈阳→林晚 好感 85")
	assert_almost_eq(core.affinity(b, a), 85.0, 0.001, "林晚→陈阳 好感 85")


func test_uniform_binding() -> void:
	var core := SimCore.new(68, 16, _tables)
	var g := _alias_idx(core, "佳豪")
	assert_true(g >= 0, "seed 68 名单包含佳豪")
	for j in range(core.node_count()):
		if j != g:
			assert_almost_eq(core.affinity(g, j), 50.0, 0.001, "佳豪→%d 好感 50" % j)


func test_accessors_bounds() -> void:
	var core := _core()
	assert_eq(core.affinity(0, 0), 0.0, "自反好感为 0")
	assert_eq(core.affinity(-1, 0), 0.0, "负索引为 0")
	assert_eq(core.affinity(0, 999), 0.0, "越界为 0")
	assert_eq(core.stress(core.node_count()), 0.0, "压力越界为 0")


func test_constructor_takes_npc_count() -> void:
	# 2026-10-12：入口直接收 npc_count —— 不再有难度档映射（difficulty.csv 已删除）
	assert_eq(SimCore.new(12345, 16).node_count(), 16, "16 名学生（内部自取 tables）")
	assert_eq(SimCore.new(12345, 99, _tables).node_count(), 16, "超出角色池的人数被夹到池人数（16）")
	assert_eq(SimCore.new(12345, 0, _tables).node_count(), 1, "人数下限 1（不静默造出空局）")
