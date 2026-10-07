extends GutTest
## 时间组件 Task 4 单测：日末简报停留、学期结束、时间状态存档边界。
##
## 依据：docs/superpowers/plans/2026-10-07-time-component.md §4（mode）、§6（存档边界）、Task 4。
## 覆盖：日末进入 report 且时钟冻结、继续只进一天、30 天终止精确（14,400 tick / 29 次日报 /
## 1 次学期结束）、日末时间状态往返、坏存档载荷被拒。

const SEED := 20261007
const NPC_COUNT := 16
const TICKS_PER_DAY := 480
const TERM_DAYS := 30


func _make_stack() -> Array:
	var tables := ConfigLoader.new().load_all()
	var core := SimCore.from_npc(SEED, NPC_COUNT, tables)
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	assert_true(clock.bind_core(core, tables), "时钟应绑定成功")
	clock.set_process(false)
	return [core, clock]


## 推进到下一次状态变化（日末 report 或学期结束）
func _pump_until_state_change(clock: SimulationClock) -> void:
	for _i in range(TICKS_PER_DAY * 3):
		clock.pump(1.0)
		if str(clock.snapshot()["mode"]) != SimulationClock.MODE_RUNNING:
			return
	fail_test("超出预期 tick 仍未进入日末状态")


func test_day_end_enters_report_and_freezes_the_clock() -> void:
	var stack := _make_stack()
	var core: SimCore = stack[0]
	var clock: SimulationClock = stack[1]
	_pump_until_state_change(clock)

	var snap: Dictionary = clock.snapshot()
	assert_eq(str(snap["mode"]), SimulationClock.MODE_REPORT, "第 1 天结束进入 report")
	assert_eq(int(snap["ended_day"]), 1, "结束的是第 1 天")
	assert_eq(int(core.time_snapshot()["global_tick"]), TICKS_PER_DAY, "一天正好 480 tick")
	assert_eq(snap["remaining_seconds"], 0.0, "简报等待不计时")

	clock.pump(120.0)
	assert_eq(int(core.time_snapshot()["global_tick"]), TICKS_PER_DAY, "report 期间继续 pump 不推进内核")


func test_continue_enters_next_day_exactly_once() -> void:
	var stack := _make_stack()
	var core: SimCore = stack[0]
	var clock: SimulationClock = stack[1]
	_pump_until_state_change(clock)

	assert_true(clock.continue_after_report(), "日末可继续")
	assert_eq(str(clock.snapshot()["mode"]), SimulationClock.MODE_RUNNING)
	assert_eq(int(core.time_snapshot()["day"]), 2, "进入第 2 天")

	assert_false(clock.continue_after_report(), "非 report 状态再次请求无效")
	assert_eq(int(core.time_snapshot()["day"]), 2, "不会多进一天")


func test_term_ends_after_30_days() -> void:
	var stack := _make_stack()
	var core: SimCore = stack[0]
	var clock: SimulationClock = stack[1]
	# 用数组计数：GDScript 闭包按值捕获 int，数组才能跨 lambda 累积
	var reports: Array = []
	var finishes: Array = []
	clock.report_ready.connect(func(day: int) -> void: reports.append(day))
	clock.term_finished.connect(func(day: int) -> void: finishes.append(day))

	for _day in range(TERM_DAYS):
		_pump_until_state_change(clock)
		if str(clock.snapshot()["mode"]) == SimulationClock.MODE_REPORT:
			clock.continue_after_report()

	assert_eq(finishes.size(), 1, "term_finished 只发一次")
	assert_eq(int(finishes[0]), TERM_DAYS, "第 30 天结束")
	assert_eq(reports.size(), TERM_DAYS - 1, "前 29 天各发一次 report_ready")
	assert_eq(str(clock.snapshot()["mode"]), SimulationClock.MODE_FINISHED, "学期结束进入 finished")
	assert_eq(
		int(core.time_snapshot()["global_tick"]), TICKS_PER_DAY * TERM_DAYS, "30 天共 14,400 tick"
	)

	clock.pump(600.0)
	assert_eq(int(core.time_snapshot()["global_tick"]), TICKS_PER_DAY * TERM_DAYS, "结束后不运行第 31 天")
	assert_false(clock.continue_after_report(), "结束后继续请求失败")


func test_save_state_round_trip_at_day_end() -> void:
	var stack := _make_stack()
	var clock: SimulationClock = stack[1]
	_pump_until_state_change(clock)

	var saved: Dictionary = clock.save_state()
	assert_eq(str(saved["mode"]), SimulationClock.MODE_REPORT)
	assert_eq(saved["accumulator"], 0.0, "日末累计为零")
	assert_ne(str(saved["config_fingerprint"]), "", "带配置指纹")

	var tables := ConfigLoader.new().load_all()
	var restored: SimulationClock = SimulationClock.new()
	add_child_autofree(restored)
	restored.set_process(false)
	assert_true(restored.bind_core(SimCore.from_npc(SEED, NPC_COUNT, tables), tables))
	assert_true(restored.restore_state(saved), "同版本同配置的日末状态可恢复")

	var snap: Dictionary = restored.snapshot()
	assert_eq(str(snap["mode"]), SimulationClock.MODE_REPORT, "恢复后仍停在简报，不自动开下一天")
	assert_eq(int(snap["ended_day"]), 1)
	assert_eq(snap["remaining_seconds"], 0.0, "恢复后不计时")


func test_restore_rejects_bad_payload() -> void:
	var stack := _make_stack()
	var clock: SimulationClock = stack[1]
	var payload: Dictionary = clock.save_state()

	assert_false(clock.restore_state({}), "空载荷拒绝")
	assert_false(clock.restore_state({"version": 999}), "版本不符拒绝")

	var wrong_mode: Dictionary = payload.duplicate(true)
	wrong_mode["mode"] = SimulationClock.MODE_RUNNING
	assert_false(clock.restore_state(wrong_mode), "只有日末边界（report）可单独恢复")

	var wrong_config: Dictionary = payload.duplicate(true)
	wrong_config["config_fingerprint"] = "deadbeef"
	assert_false(clock.restore_state(wrong_config), "配置指纹不符拒绝")
