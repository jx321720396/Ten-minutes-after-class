extends GutTest
## SimCore 时间边界接口单测（时间组件 Task 1）。
##
## 依据：docs/superpowers/plans/2026-10-07-time-component.md §4；
##      主文档 §3.2（tick 定义）、§3.3（上课发酵层）；data/rules/phases.csv。
##
## 这里只验证「内核是唯一时间真值」的两个新接口：
##   · time_snapshot()         —— 只读快照，表现层据此显示与判定；
##   · finish_time_boundary()  —— 显式完成阶段边界，不推进任何 tick。
## 原有的 advance_tick/advance_phase/advance_day 采样语义（段末 snapshot 仍属上一段）必须保持不变。

const SEED := 20261007
const NPC_COUNT := 16
## 一天 = 3 段课间 100 + 2 段上课 90（phases.csv）
const TICKS_PER_DAY := 480


func _make_core() -> SimCore:
	var tables := ConfigLoader.new().load_all()
	return SimCore.from_npc(SEED, NPC_COUNT, tables)


func test_snapshot_initial_state() -> void:
	var core := _make_core()
	var snap: Dictionary = core.time_snapshot()
	assert_eq(snap["day"], 1, "开局是第 1 天")
	assert_eq(snap["phase_id"], "morning_break", "开局相位 = 上午课间")
	assert_eq(snap["kind"], "break", "kind 只区分课间/上课之外还需 phase_id 区分上午下午")
	assert_eq(snap["phase_index"], 0)
	assert_eq(snap["tick_in_phase"], 0)
	assert_eq(snap["tick_count"], 100, "上午课间 100 tick")
	assert_eq(snap["global_tick"], 0)
	assert_eq(snap["player_control"], true, "课间允许玩家操作")


func test_break_boundary_advances_phase_without_tick() -> void:
	var core := _make_core()
	for _i in range(100):
		core.advance_tick()
	var before: Dictionary = core.time_snapshot()
	assert_eq(before["global_tick"], 100)
	assert_eq(before["tick_in_phase"], 100)
	assert_eq(before["phase_id"], "morning_break", "段跑满时快照仍属上一段（既有对拍语义）")

	var result: Dictionary = core.finish_time_boundary()
	assert_true(result["changed"], "tick 已耗尽 → 边界应被完成")
	assert_false(result["day_settled"], "只跨段，未跨天")
	assert_eq(result["ended_day"], 0, "未跨天时 ended_day 为 0")

	var after: Dictionary = result["snapshot"]
	assert_eq(after["phase_id"], "morning_class", "推进到上午上课")
	assert_eq(after["kind"], "class")
	assert_eq(after["tick_in_phase"], 0, "新相位 tick 归零")
	assert_eq(after["tick_count"], 90, "上午上课 90 tick")
	assert_eq(after["global_tick"], 100, "边界本身不产生 tick")
	assert_eq(after["player_control"], false, "上课禁止玩家主动操作")

	var again: Dictionary = core.finish_time_boundary()
	assert_false(again["changed"], "未耗尽时重复调用不重复结算")
	assert_eq(again["snapshot"]["global_tick"], 100, "重复调用不推进")

	var third: Dictionary = core.finish_time_boundary()
	assert_false(third["changed"], "第三次同样无副作用")


func test_finish_boundary_is_noop_when_phase_not_exhausted() -> void:
	var core := _make_core()
	core.advance_tick()
	var result: Dictionary = core.finish_time_boundary()
	assert_false(result["changed"], "段未跑完 → changed = false")
	assert_eq(result["snapshot"]["tick_in_phase"], 1, "游标不动")
	assert_eq(result["snapshot"]["phase_id"], "morning_break")


func test_day_boundary_settles_exactly_once() -> void:
	var core := _make_core()
	var settled: Array = []
	core.event_sink = func(e: Dictionary) -> void:
		if e["type"] == "day_settled":
			settled.append(e["payload"])

	for _i in range(TICKS_PER_DAY):
		core.advance_tick()
	assert_eq(core.time_snapshot()["global_tick"], TICKS_PER_DAY, "一天正好 480 tick")

	var result: Dictionary = core.finish_time_boundary()
	assert_true(result["changed"])
	assert_true(result["day_settled"], "480 tick 跑满 → 跨天结算")
	assert_eq(result["ended_day"], 1, "结束的是第 1 天")
	assert_eq(settled.size(), 1, "day_settled 只发一次")
	assert_eq(int(settled[0]["day"]), 1, "事件载荷里的 day 是刚结束的那天")

	var after: Dictionary = result["snapshot"]
	assert_eq(after["day"], 2, "内核游标进入第 2 天")
	assert_eq(after["phase_index"], 0, "回到段 0")
	assert_eq(after["phase_id"], "morning_break")
	assert_eq(after["global_tick"], TICKS_PER_DAY, "跨天结算不增 tick")

	var again: Dictionary = core.finish_time_boundary()
	assert_false(again["changed"], "重复处理无效")
	assert_eq(settled.size(), 1, "不重复结算、不重复发事件")
	assert_eq(core.time_snapshot()["day"], 2, "不偷跑第 2 天的 tick")
	assert_eq(core.time_snapshot()["global_tick"], TICKS_PER_DAY)
