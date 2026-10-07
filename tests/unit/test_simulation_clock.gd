extends GutTest
## SimulationClock 单测（时间组件 Task 2）。
##
## 依据：docs/superpowers/plans/2026-10-07-time-component.md §2（固定时序与换算）、§4（时钟接口与状态）。
## 覆盖：固定步长换算、不同 delta 切分的状态一致性、hold/release 嵌套暂停、
##       每帧预算与积压、边界同帧不再推进、进度与剩余秒数边界、配置校验拒绝坏表。

const SEED := 20261007
const NPC_COUNT := 16
const PRESENTATION := "rules/time_presentation"
const RUNTIME := "rules/time_runtime"


func _make_core() -> SimCore:
	return SimCore.from_npc(SEED, NPC_COUNT, ConfigLoader.new().load_all())


func _make_clock(core: SimCore) -> SimulationClock:
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	assert_true(clock.bind_core(core), "默认配置应通过校验并绑定成功")
	# 测试里手动 pump：关掉 _process 自动驱动，避免真实帧时间与断言相互干扰
	clock.set_process(false)
	return clock


## 跑若干个 pump 让内核推进到下一段（每个 pump 受每帧预算限制，故需多轮）。
func _pump_until_phase_change(clock: SimulationClock, core: SimCore) -> void:
	var phase_id := str(core.time_snapshot()["phase_id"])
	for _i in range(200):
		clock.pump(1.0)
		if str(core.time_snapshot()["phase_id"]) != phase_id:
			return
	fail_test("60 秒内未能跨过相位边界")


func test_first_tick_needs_full_interval() -> void:
	# 上午课间 = 100 tick / 100 秒 → 每 tick 1 秒
	var core := _make_core()
	var clock := _make_clock(core)
	clock.pump(0.4)
	assert_eq(core.time_snapshot()["global_tick"], 0, "不足一个 tick 间隔时不推进")
	clock.pump(0.6)
	assert_eq(core.time_snapshot()["global_tick"], 1, "累计满 1 秒推进 1 tick")


func test_class_interval_comes_from_presentation_table() -> void:
	var core := _make_core()
	var clock := _make_clock(core)
	_pump_until_phase_change(clock, core)
	var snap: Dictionary = core.time_snapshot()
	assert_eq(snap["phase_id"], "morning_class", "课间跑满后进入上午上课")
	assert_eq(snap["tick_count"], 90)
	assert_eq(snap["tick_in_phase"], 0, "边界后新相位 tick 归零（同帧不偷跑）")

	# 上课 = 90 tick / 15 秒 → 每 tick 1/6 秒；1/6 秒刚好推进一个 tick
	clock.pump(1.0 / 6.0)
	assert_eq(core.time_snapshot()["global_tick"], 101, "上课段 1/6 秒推进 1 tick")


func test_state_is_independent_of_delta_split() -> void:
	var core_a := _make_core()
	var clock_a := _make_clock(core_a)
	clock_a.pump(0.3)
	clock_a.pump(0.3)
	clock_a.pump(0.4)

	var core_b := _make_core()
	var clock_b := _make_clock(core_b)
	clock_b.pump(1.0)

	assert_eq(
		core_a.time_snapshot()["global_tick"],
		core_b.time_snapshot()["global_tick"],
		"同样的总时长，切分方式不影响推进结果"
	)
	assert_eq(core_a.report(), core_b.report(), "内核状态一致")


func test_hold_needs_all_owners_released() -> void:
	var core := _make_core()
	var clock := _make_clock(core)
	clock.hold(&"menu")
	clock.hold(&"pen_check")
	assert_true(clock.is_paused(), "任一拥有者持有即暂停")

	clock.pump(5.0)
	assert_eq(core.time_snapshot()["global_tick"], 0, "暂停期间不推进")

	clock.release(&"menu")
	assert_true(clock.is_paused(), "还有拥有者 → 仍暂停")
	clock.pump(5.0)
	assert_eq(core.time_snapshot()["global_tick"], 0)

	clock.release(&"pen_check")
	assert_false(clock.is_paused(), "最后一个拥有者释放后恢复")

	clock.release(&"pen_check")
	assert_false(clock.is_paused(), "重复释放无副作用")

	clock.pump(1.0)
	assert_eq(core.time_snapshot()["global_tick"], 1, "恢复后照常推进")


func test_paused_run_does_not_touch_kernel_or_rng() -> void:
	var core := _make_core()
	var clock := _make_clock(core)
	var before_affinity := core.affinity(0, 1)
	var before_opacity := core.opacity(0)
	clock.hold(&"menu")
	clock.pump(60.0)
	var snap: Dictionary = core.time_snapshot()
	assert_eq(snap["global_tick"], 0, "暂停不推进 tick")
	assert_eq(snap["day"], 1)
	assert_almost_eq(core.affinity(0, 1), before_affinity, 0.0001, "关系矩阵不变")
	assert_almost_eq(core.opacity(0), before_opacity, 0.0001, "透明度不变")


func test_frame_budget_keeps_backlog_without_skipping() -> void:
	var core := _make_core()
	var clock := _make_clock(core)
	# 每帧预算 8 tick：一次性给 10 秒也只推进 8 个 tick，剩余 2 秒积压
	clock.pump(10.0)
	assert_eq(core.time_snapshot()["global_tick"], 8, "单帧不超过预算")
	clock.pump(0.0)
	assert_eq(core.time_snapshot()["global_tick"], 8, "补 0 秒不推进")
	# 再给 2 秒：积压的 2 秒 + 新的 2 秒 = 4 tick，仍在预算内，逐 tick 推进不跳跃
	clock.pump(2.0)
	assert_eq(core.time_snapshot()["global_tick"], 12, "积压与新 delta 一起结算")
	assert_eq(core.time_snapshot()["tick_in_phase"], 12, "tick 连续推进、没有跳过")


func test_boundary_stops_batch_within_same_frame() -> void:
	var core := _make_core()
	var clock := _make_clock(core)
	var changed_phases: Array = []
	clock.phase_changed.connect(
		func(snap: Dictionary) -> void: changed_phases.append(snap["phase_id"])
	)

	# 一次给足 100 秒：同一帧内跑到课间末尾就必须停下，不能顺手推进上课段的 tick
	for _i in range(20):
		clock.pump(100.0)
		if str(core.time_snapshot()["phase_id"]) != "morning_break":
			break
	var snap: Dictionary = core.time_snapshot()
	assert_eq(snap["phase_id"], "morning_class", "跨过边界")
	assert_eq(snap["global_tick"], 100, "边界那一帧不产生新相位的 tick")
	assert_eq(snap["tick_in_phase"], 0)
	assert_eq(changed_phases.size(), 1, "phase_changed 只发一次")
	assert_eq(str(changed_phases[0]), "morning_class")


func test_progress_and_remaining_stay_bounded() -> void:
	var core := _make_core()
	var clock := _make_clock(core)
	var start: Dictionary = clock.snapshot()
	assert_eq(start["remaining_seconds"], 100.0, "开局剩余 = 课间整段 100 秒")
	assert_almost_eq(start["progress"], 0.0, 0.0001)
	assert_eq(start["mode"], "running")
	assert_false(start["paused"])

	clock.pump(0.5)
	var mid: Dictionary = clock.snapshot()
	assert_true(mid["progress"] > 0.0 and mid["progress"] < 1.0, "半秒后进度在 0~1 之间")
	assert_true(mid["remaining_seconds"] > 99.0 and mid["remaining_seconds"] <= 100.0, "剩余秒数不越界")

	clock.pump(200.0)
	var late: Dictionary = clock.snapshot()
	assert_true(late["progress"] >= 0.0 and late["progress"] <= 1.0, "进度恒在 0~1")
	assert_true(late["remaining_seconds"] >= 0.0, "剩余秒数不为负")


# ------------------------------------------------------------------ 配置校验
func _tables_with_presentation(rows: Array) -> Dictionary:
	var tables: Dictionary = ConfigLoader.new().load_all()
	tables[PRESENTATION] = {"name": PRESENTATION, "rows": rows}
	return tables


func _tables_with_runtime(rows: Array) -> Dictionary:
	var tables: Dictionary = ConfigLoader.new().load_all()
	tables[RUNTIME] = {"name": RUNTIME, "rows": rows}
	return tables


## 坏配置必须被拒绝：内核用默认配置构造（时钟只读快照），坏表只喂给 bind_core。
func _expect_bind_fails(tables: Dictionary, why: String, error_hint: String) -> void:
	var core := _make_core()
	var clock := SimulationClock.new()
	add_child_autofree(clock)
	clock.set_process(false)
	assert_false(clock.bind_core(core, tables), why)
	assert_push_error(error_hint, why)


func test_rejects_missing_phase_row() -> void:
	_expect_bind_fails(
		_tables_with_presentation([{"phase_id": "morning_break", "real_duration_seconds": "100"}]),
		"缺表项应被拒绝",
		"缺相位"
	)


func test_rejects_negative_duration() -> void:
	var rows: Array = ConfigLoader.new().get_table(PRESENTATION).get("rows", [])
	var broken: Array = []
	for row in rows:
		var copy: Dictionary = (row as Dictionary).duplicate()
		if str(copy["phase_id"]) == "morning_class":
			copy["real_duration_seconds"] = "-5"
		broken.append(copy)
	_expect_bind_fails(_tables_with_presentation(broken), "负时长应被拒绝", "必须为正")


func test_rejects_zero_tick_active_phase() -> void:
	var tables: Dictionary = ConfigLoader.new().load_all()
	var phase_rows: Array = []
	for row in tables["rules/phases"]["rows"]:
		var copy: Dictionary = (row as Dictionary).duplicate()
		if str(copy["phase_id"]) == "morning_break":
			copy["tick_count"] = "0"
		phase_rows.append(copy)
	tables["rules/phases"] = {"name": "rules/phases", "rows": phase_rows}
	_expect_bind_fails(tables, "活动相位 tick 数为 0 应被拒绝", "tick_count")


func test_rejects_bad_term_days() -> void:
	_expect_bind_fails(
		_tables_with_runtime([{"key": "term_days", "value": "0", "note": ""}]),
		"term_days 非正整数应被拒绝",
		"term_days"
	)
