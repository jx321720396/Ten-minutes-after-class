extends GutTest
## SimCore：单日时间系统（480 tick）、同种子确定性、绑定组初始化与只读访问器。

var _tables: Dictionary


func before_each() -> void:
	_tables = ConfigLoader.new().load_all()


func _core() -> SimCore:
	return SimCore.from_npc(12345, 8, _tables)


## 随机名单下按别名反查角色下标（绑定组不再固定 0/1/2）。
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
	assert_eq(core.node_count(), 9, "8 NPC + 1 老师节点")


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
	core._do_chat(0, 1)   # 第一条事件：手动触发的闲聊
	core.run_day()
	assert_true(events.size() > 0, "应派发事件")
	assert_eq(events[0]["type"], "event_happened", "首条为 event_happened")
	assert_eq(events[0]["payload"]["kind"], "chat", "chat 事件")
	assert_eq(events[0]["payload"]["i"], 0, "chat 事件 i=0")
	assert_eq(events[0]["payload"]["j"], 1, "chat 事件 j=1")
	assert_eq(events[-1]["type"], "day_settled", "末条为 day_settled")
	assert_eq(events[-1]["payload"]["day"], 1, "day_settled 结算第 1 天")


func test_player_action_chat_and_validation() -> void:
	# D11 缺口③：玩家显式行动，来源固定玩家、目标指定。
	# 计划 §3.1：玩家交互必须过**真实空间判定**，先注入一间合法房间作为夹具。
	var core := _core()
	core.set_interaction_geometry([], Rect2(-4.0, -4.0, 8.0, 8.0))
	var me := 8   # 玩家 = n-1
	assert_false(core.player_action("chat", me)["ok"], "目标=玩家应拒绝")
	assert_false(core.player_action("chat", -1)["ok"], "目标 OOB 应拒绝")
	assert_false(core.player_action("bogus", 0)["ok"], "未知 kind 应拒绝")
	var events: Array = []
	core.event_sink = func(e: Dictionary) -> void: events.append(e)
	var before_a := core.affinity(0, me)
	var before_h := core.hostility(0, me)
	var r := core.player_action("chat", 0, "学习")
	assert_true(r["ok"], "chat 应成功")
	assert_eq(r["target"], 0, "target 回显")
	assert_eq(r["topic"], "学习", "topic 透传")
	assert_eq(events.size(), 2, "应派发 chat + player_interaction_started 两条通知")
	assert_eq(events[0]["payload"]["kind"], "chat", "事件 kind=chat")
	assert_eq(str(events[1]["payload"]["kind"]), "player_interaction_started", "第二条为开始通知")
	assert_eq(str(events[1]["payload"]["mode"]), "start", "发起新聊天 mode=start")
	assert_gt(int(events[1]["payload"]["request_id"]), 0, "开始通知带内核分配的请求编号")
	# 关系结算仍然走内核统一公式：目标→玩家的好感被改写，玩家自身效果摘要随之非空
	assert_gt(core.affinity(0, me), before_a, "目标→玩家：话题共鸣把好感推高")
	assert_gte(core.hostility(0, me), before_h, "敌对不被闲聊凭空抹掉")
	assert_gt(float(r["player_effects"]["affinity_delta"]), 0.0, "玩家自身效果摘要方向正确")
	assert_true(r.has("session_id"), "提交包带真实会话编号（供底部圈与线索）")
	var r2 := core.player_action("chat", 1)
	assert_false(r2["ok"], "玩家忙应拒绝第二次行动")
	assert_eq(r2.get("error"), "player_busy", "错误码 player_busy")


func test_deterministic_report() -> void:
	var a := _core()
	a.run_day()
	var b := _core()
	b.run_day()
	assert_eq(a.report(), b.report(), "同种子报告逐字节一致")


func test_couple_binding() -> void:
	# 随机名单下绑定组不一定入选，改用 seed 68（陈阳/林晚/佳豪均入选）验证绑定逻辑。
	var core := SimCore.from_npc(68, 8, _tables)
	var a := _alias_idx(core, "陈阳")
	var b := _alias_idx(core, "林晚")
	assert_true(a >= 0 and b >= 0, "seed 68 名单包含陈阳与林晚")
	assert_almost_eq(core.affinity(a, b), 85.0, 0.001, "陈阳→林晚 好感 85")
	assert_almost_eq(core.affinity(b, a), 85.0, 0.001, "林晚→陈阳 好感 85")
	assert_almost_eq(core.trust(a, b), 80.0, 0.001, "陈阳→林晚 信任 80")
	assert_almost_eq(core.trust(b, a), 80.0, 0.001, "林晚→陈阳 信任 80")


func test_uniform_binding() -> void:
	var core := SimCore.from_npc(68, 8, _tables)
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
	assert_eq(core.opacity(-1), 0.0, "透明度负索引为 0")
	assert_eq(core.stress(core.node_count()), 0.0, "压力越界为 0")


func test_constructor_signature_difficulty() -> void:
	# D11 缺口①：SimCore.new(seed, difficulty) 内部读表 + difficulty→npc_count 映射
	assert_eq(SimCore.new(12345, 1).node_count(), 9, "difficulty 1 → 8 NPC（内部自取 tables）")
	assert_eq(SimCore.new(12345, 2).node_count(), 17, "difficulty 2 → 16 NPC（内部自取 tables）")
	assert_eq(SimCore.from_npc(12345, 8, _tables).node_count(), 9, "from_npc 兼容入口 8 NPC")
	# difficulty 3（24 NPC）映射正确；满编构造需 25 座，seats.csv 现仅 17 座——待数据扩展后再跑完整构造
	var probe := SimCore.from_npc(12345, 8, _tables)
	assert_eq(probe._difficulty_npc_count(1, _tables), 8, "difficulty 1 映射 8")
	assert_eq(probe._difficulty_npc_count(2, _tables), 16, "difficulty 2 映射 16")
	assert_eq(probe._difficulty_npc_count(3, _tables), 24, "difficulty 3 映射 24")
