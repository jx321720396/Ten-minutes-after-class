class_name SimulationClock
extends Node
## 时间驱动（表现层）：把真实经过时间换算成整数模拟 tick。
##
## 依据：docs/superpowers/plans/2026-10-07-time-component.md §2、§4；主文档 §3.2（tick 定义）。
##
## 职责边界：
##   · **SimCore 是唯一玩法时间真值** —— 本组件只调用 `advance_tick()` 与
##     `finish_time_boundary()`，不自己维护日历，也不调用 `advance_phase()` 快进整段；
##   · 相位顺序 / tick 数 / 玩家权限一律从内核快照读回（`phases.csv`）；
##     实时标称时长与游戏内时长来自 `data/rules/time_presentation.csv`；
##     学期长度与每帧预算来自 `data/rules/time_runtime.csv`。
##
## 推进规则（计划 §4）：累计真实秒数，满一个 tick 间隔才推进；每帧最多补
## `max_ticks_per_frame` 个 tick，**积压保留、禁止跳 tick**；一旦跨过相位边界就停止本帧
## 批处理并清空累计，避免低帧率一帧跨掉整个可操作课间。暂停期间忽略 delta、恢复后不追赶。

signal time_updated(snapshot: Dictionary)
signal phase_changed(snapshot: Dictionary)
signal report_ready(ended_day: int)
signal term_finished(ended_day: int)

const MODE_RUNNING := "running"
const MODE_REPORT := "report"
const MODE_FINISHED := "finished"
## 时间状态存档版本（字段见 save_state）
const SAVE_VERSION := 1

const PRESENTATION_TABLE := "rules/time_presentation"
const RUNTIME_TABLE := "rules/time_runtime"
const PHASES_TABLE := "rules/phases"
const SETTLE_KIND := "settle"

var _core: SimCore = null
var _risk_attention := preload("res://scripts/game/risk_attention_snapshot.gd").new()
var _tables: Dictionary = {}
## phase_id → 实时标称时长（秒）
var _phase_seconds: Dictionary = {}
## phase_id → 人类可读阶段名
var _display_names: Dictionary = {}
var _accumulator := 0.0
var _mode := MODE_RUNNING
## 暂停拥有者集合（同名重复添加不累计，全部释放才恢复）
var _paused_by: Dictionary = {}
var _ended_day := 0
## 被辞退的原因（空串 = 正常进行）—— 由日末结算写入，快照输出给界面。
var _failure_reason := ""
var _term_days := 0
var _max_ticks_per_frame := 1
## 日末提示停留秒数（`rules/time_runtime` 的 `report_hold_seconds`；0 = 立刻自动进入次日）。
## 时钟只**暴露**这个数，不自己计时 —— 停留与自动进入由表现层 HUD 倒计时（`time_hud.gd`）。
var _report_hold_seconds := 0.0
var _time_flow: TimeFlow = null
var _attention_cfg: Dictionary = JSON.parse_string(
	FileAccess.get_file_as_string("res://data/ui/attention_card.json")
)


func _process(delta: float) -> void:
	pump(delta)


func bind_time_flow(flow: TimeFlow) -> void:
	if is_instance_valid(_time_flow) and _time_flow.scale_changed.is_connected(_on_scale_changed):
		_time_flow.scale_changed.disconnect(_on_scale_changed)
	_time_flow = flow
	if is_instance_valid(_time_flow):
		_time_flow.scale_changed.connect(_on_scale_changed)
	time_updated.emit(snapshot())


func _on_scale_changed(_multiplier: float) -> void:
	time_updated.emit(snapshot())


# ------------------------------------------------------------------ 绑定与配置
## 绑定内核并读取配置；配置不合格时返回 false 且保持未绑定（不静默用默认值）。
## tables 为空时自行用 ConfigLoader 读 data/（便于无头单测注入坏配置）。
func bind_core(core: SimCore, tables: Dictionary = {}) -> bool:
	_core = core
	_tables = tables if not tables.is_empty() else ConfigLoader.new().load_all()
	if not _load_config():
		_core = null
		return false
	_accumulator = 0.0
	_mode = MODE_RUNNING
	_paused_by.clear()
	_ended_day = 0
	_failure_reason = ""
	time_updated.emit(snapshot())
	return true


func _load_config() -> bool:
	_phase_seconds.clear()
	_display_names.clear()
	var error := _validate_config()
	if error.is_empty():
		return true
	push_error(error)
	return false


## 校验配置表：通过返回空串，否则返回可直接 push_error 的说明。
## 拆成几个小函数是为了守住 gdlint 的 max-returns 规则，同时让每条拒绝理由只存在一处。
func _validate_config() -> String:
	var presentation_rows: Array = _tables.get(PRESENTATION_TABLE, {}).get("rows", [])
	var phase_rows: Array = _tables.get(PHASES_TABLE, {}).get("rows", [])
	var runtime_rows: Array = _tables.get(RUNTIME_TABLE, {}).get("rows", [])
	if presentation_rows.is_empty() or phase_rows.is_empty() or runtime_rows.is_empty():
		return (
			"SimulationClock：缺少 %s / %s / %s 配置。"
			% [PRESENTATION_TABLE, PHASES_TABLE, RUNTIME_TABLE]
		)
	var runtime_error := _read_runtime(runtime_rows)
	if not runtime_error.is_empty():
		return runtime_error
	var presentation_error := _read_presentation(presentation_rows)
	if not presentation_error.is_empty():
		return presentation_error
	return _check_phases(phase_rows)


func _read_runtime(rows: Array) -> String:
	_term_days = int(_runtime_value(rows, "term_days", 0.0))
	_max_ticks_per_frame = int(_runtime_value(rows, "max_ticks_per_frame", 0.0))
	_report_hold_seconds = _runtime_value(rows, "report_hold_seconds", -1.0)
	if _term_days <= 0:
		return "SimulationClock：term_days 必须是正整数（当前 %d）。" % _term_days
	if _max_ticks_per_frame <= 0:
		return "SimulationClock：max_ticks_per_frame 必须是正整数（当前 %d）。" % _max_ticks_per_frame
	if not is_finite(_report_hold_seconds) or _report_hold_seconds < 0.0:
		return "SimulationClock：report_hold_seconds 必须是非负有限数（当前 %s）。" % _report_hold_seconds
	return ""


func _read_presentation(rows: Array) -> String:
	for row in rows:
		var phase_id := str(row.get("phase_id", ""))
		if phase_id.is_empty():
			return "SimulationClock：%s 有行缺 phase_id。" % PRESENTATION_TABLE
		if _phase_seconds.has(phase_id):
			return "SimulationClock：%s 相位重复：%s。" % [PRESENTATION_TABLE, phase_id]
		_phase_seconds[phase_id] = float(str(row.get("real_duration_seconds", "-1")))
		_display_names[phase_id] = str(row.get("display_name", phase_id))
	return ""


func _check_phases(rows: Array) -> String:
	for row in rows:
		var error := _check_phase_row(row)
		if not error.is_empty():
			return error
	if _phase_seconds.size() != rows.size():
		return "SimulationClock：%s 与 %s 的相位集合不一致。" % [PRESENTATION_TABLE, PHASES_TABLE]
	return ""


func _check_phase_row(row: Dictionary) -> String:
	var phase_id := str(row.get("phase_id", ""))
	var kind := str(row.get("kind", ""))
	if not _phase_seconds.has(phase_id):
		return "SimulationClock：%s 缺相位 %s（两张表必须一一对应）。" % [PRESENTATION_TABLE, phase_id]
	var seconds: float = _phase_seconds[phase_id]
	if kind == SETTLE_KIND:
		if seconds != 0.0:
			return "SimulationClock：结算相位 %s 的实时时长必须为 0。" % phase_id
		return ""
	if seconds <= 0.0:
		return "SimulationClock：活动相位 %s 的实时时长必须为正（当前 %s）。" % [phase_id, seconds]
	if int(str(row.get("tick_count", "0"))) <= 0:
		return "SimulationClock：活动相位 %s 的 tick_count 必须为正。" % phase_id
	return ""


func _runtime_value(rows: Array, key: String, fallback: float) -> float:
	for row in rows:
		if str(row.get("key", "")) == key:
			return float(str(row.get("value", fallback)))
	return fallback


# ------------------------------------------------------------------ 驱动
## 固定步长驱动（可测试入口）：`_process` 只是转调它。
func pump(delta_seconds: float) -> void:
	if _core == null or _mode != MODE_RUNNING or is_paused():
		return
	# 上课段硬跳过（2026-10-17 裁定）：黑幕退场 release 后，下一帧检测到 class 即整段跳过，
	# 只留全员固定学业收益 + 崩溃判定，随后 phase_changed 让转场黑幕切到「下课了」。
	if str(_core.time_snapshot()["kind"]) == "class":
		skip_class()
		return
	if delta_seconds <= 0.0:
		return
	if is_instance_valid(_time_flow):
		delta_seconds = _time_flow.scale_delta(delta_seconds)
	if delta_seconds <= 0.0:
		return
	_accumulator += delta_seconds
	var processed := 0
	while processed < _max_ticks_per_frame:
		var snapshot_before: Dictionary = _core.time_snapshot()
		var interval := _interval_of(snapshot_before)
		if interval <= 0.0:
			break
		if _accumulator < interval:
			break
		_accumulator -= interval
		_core.advance_tick()
		processed += 1
		var boundary: Dictionary = _core.finish_time_boundary()
		if bool(boundary["changed"]):
			# 边界：清空旧相位累计 + 本帧不再推进（下一相位下一帧开始）
			_accumulator = 0.0
			phase_changed.emit(snapshot())
			if bool(boundary["day_settled"]):
				_ended_day = int(boundary["ended_day"])
				_enter_report()
			break
		time_updated.emit(snapshot())


## 跳过当前课间剩余时间（快进）：把本段剩余 tick 一次性跑完，再走一次段末结算。
## 事件一个不少，同种子与实时跑完完全一致（复用 advance_tick，不另写结算）。
## 仅 running + 课间 + 玩家有控制权（player_control=1）时生效；上课／日末／暂停返回 false。
func skip_break_remaining() -> bool:
	if _core == null or _mode != MODE_RUNNING or is_paused():
		return false
	var before := _core.time_snapshot()
	if str(before["kind"]) != "break" or not bool(before["player_control"]):
		return false
	var remaining := int(before["tick_count"]) - int(before["tick_in_phase"])
	for _i in range(remaining):
		_core.advance_tick()
	var boundary := _core.finish_time_boundary()
	_accumulator = 0.0
	if bool(boundary["changed"]):
		phase_changed.emit(snapshot())
		if bool(boundary["day_settled"]):
			_ended_day = int(boundary["ended_day"])
			_enter_report()
	time_updated.emit(snapshot())
	return true


## 上课段黑幕跳过：内核硬跳过 class，并广播相位变化（供转场黑幕切到「下课了」）。
## 只在当前相位确为上课时生效；调用后游标已推进到下一段课间。
func skip_class() -> bool:
	if _core == null or _mode != MODE_RUNNING or is_paused():
		return false
	if str(_core.time_snapshot()["kind"]) != "class":
		return false
	_core.skip_class()
	_accumulator = 0.0
	phase_changed.emit(snapshot())
	time_updated.emit(snapshot())
	return true


## 考试演出结束后跑完当天原有 tick／边界，只发布最终成绩边界。
## 不调用 skip_class，避免给考试日额外发放普通上课收益。
func complete_exam_day() -> bool:
	if _core == null or _mode != MODE_RUNNING:
		return false
	var day := int(_core.time_snapshot().day)
	if not _core._exam.is_exam_day(day):
		return false
	while int(_core.time_snapshot().day) == day:
		_core.advance_tick()
		_core.finish_time_boundary()
	_accumulator = 0.0
	_ended_day = day
	_enter_report()
	time_updated.emit(snapshot())
	return true


## 暂停：按拥有者集合管理，可重入；同名重复添加不累计，最后一个释放才恢复。
func hold(who: StringName) -> void:
	_paused_by[who] = true


func release(who: StringName) -> void:
	_paused_by.erase(who)


func is_paused() -> bool:
	return not _paused_by.is_empty()


## 查某个拥有者是否正持着 hold（教程测试用：只关心自己的冻结，不牵连转场等其他持有者）。
func is_held_by(who: StringName) -> bool:
	return _paused_by.has(who)


## 日末简报「继续」：仅 report 状态可用；清空累计真实时间，进入下一天。
## 表现层在日末停留（`report_hold_seconds`）结束后**自动**调用它（`time_hud.gd`），
## 玩家也可按空格提前进入；第 30 天结束时 mode 为 finished，本方法拒绝。
func continue_after_report() -> bool:
	if _mode != MODE_REPORT or is_held_by(&"outcome_screen"):
		return false
	_mode = MODE_RUNNING
	_accumulator = 0.0
	_ended_day = 0
	time_updated.emit(snapshot())
	return true


## 玩家在时间卡片上点一次：循环 1× → 2× → 3× → 1×。
## 老师版没有自动加速，倍率只由这里（或 set_speed）改变；暂停另有时钟 hold 一条来源。
func cycle_time_scale() -> float:
	if not is_instance_valid(_time_flow):
		return 1.0
	var scale := float(_time_flow.cycle_speed())
	time_updated.emit(snapshot())
	return scale


## 当前可选档位数（1× … N×），供界面按需展示。
func time_scale_options() -> int:
	return int(_time_flow.speed_options()) if is_instance_valid(_time_flow) else 1


## 老师命令进行中的临时快进锁（「快进」按钮）；转发给 TimeFlow，scale_changed 会自动刷新 HUD。
func request_fast_forward(owner: StringName) -> void:
	if is_instance_valid(_time_flow):
		_time_flow.request_fast_forward(owner)


func release_fast_forward(owner: StringName) -> void:
	if is_instance_valid(_time_flow):
		_time_flow.release_fast_forward(owner)


## 只读快照：内核时间字段 + 时钟自身状态（mode / paused / remaining_seconds / progress / ended_day）。
func snapshot() -> Dictionary:
	var out: Dictionary = {}
	if _core != null:
		out = _core.time_snapshot().duplicate()
	else:
		out = {
			"day": 0,
			"phase_id": "",
			"kind": "",
			"phase_index": 0,
			"tick_in_phase": 0,
			"tick_count": 0,
			"global_tick": 0,
			"player_control": false,
		}
	out["mode"] = _mode
	out["paused"] = is_paused()
	out["time_scale"] = _time_flow.multiplier() if is_instance_valid(_time_flow) else 1.0
	# 日末简报 / 学期结束期间**不计时**：剩余与进度一律归零，别显示下一天的倒计时
	var running := _mode == MODE_RUNNING
	out["remaining_seconds"] = _remaining_seconds(out) if running else 0.0
	out["progress"] = _progress(out) if running else 0.0
	out["ended_day"] = _ended_day
	out["failure_reason"] = _failure_reason
	out["term_days"] = _term_days
	out["report_hold_seconds"] = _report_hold_seconds
	out["player_grade"] = int(_core.grade(_core.node_count() - 1)) if _core != null else 0
	out.merge(_class_grade_snapshot())
	out.merge(_attention_snapshot())
	if _core != null:
		out["risk_attention"] = _risk_attention.build(_core, _tables)
	out["volume"] = _core.volume() if _core != null else 0.0
	for row in _tables.get("rules/environment", {}).get("rows", []):
		if row["param"] in ["volume_max", "volume_threshold"]:
			out[row["param"]] = float(row["value"])
	out["display_name"] = _display_name_of(str(out.get("phase_id", "")))
	var day := int(out.get("day", 0))
	out["is_exam_day"] = running and _core != null and _core._exam.is_exam_day(day)
	if bool(out["is_exam_day"]):
		out["display_name"] = "考试"
		out["player_control"] = false
	if _core != null and _core.has_method("exam_banner"):
		out["exam_banner"] = _core.exam_banner(day) if running else ""
		out["exam_report"] = _core.exam_report(_ended_day) if not running else ""
	else:
		out["exam_banner"] = ""
		out["exam_report"] = ""
	return out


## 只读班级成绩（2026-10-16 起本局全部节点都是学生，无需再排除玩家）。
func _class_grade_snapshot() -> Dictionary:
	var total := 0.0
	var pressure_total := 0.0
	var motivation_total := 0.0
	var gain_total := 0.0
	var count := 0
	if _core != null:
		for index in range(_core.node_count()):
			total += _core.grade(index)
			pressure_total += _core.stress(index)
			motivation_total += _core.vitality(index)
			gain_total += _core.gain_today(index)
			count += 1
	var first_day := 0
	for row in _tables.get("rules/exam", {}).get("rows", []):
		if str(row.get("param", "")).begins_with("exam_day_"):
			var candidate := int(row.get("value", 0))
			if candidate > 0 and (first_day == 0 or candidate < first_day):
				first_day = candidate
	var maximum := 0.0
	for row in _tables.get("rules/kernel_params", {}).get("rows", []):
		if str(row.get("param", "")) == "grade_max":
			maximum = float(row.get("value", 0.0))
	return {
		"student_count": count,
		"class_average_grade": total / count if count > 0 else null,
		"class_average_pressure": pressure_total / count if count > 0 else null,
		"class_average_motivation": motivation_total / count if count > 0 else null,
		"class_average_academic_gain": gain_total / count if count > 0 else null,
		"grade_max": maximum,
		"first_exam_day": first_day,
	}


## 只读活动与高压名单；不把敌对或普通娱乐推断成争吵。
func _attention_snapshot() -> Dictionary:
	if _core == null:
		return {}
	var students: Array = []
	var counts := {"study": 0, "entertainment": 0, "other": 0}
	for index in range(_core.node_count()):
		var pressure := _core.stress(index)
		if pressure >= float(_attention_cfg.warning_pressure):
			students.append({"index": index, "name": _core.alias(index), "pressure": pressure})
		var activity := _core.activity_of(index)
		var kind := "other"
		if _core.is_present(index) and not _core.is_moving(index):
			if activity in _attention_cfg.study_activities:
				kind = "study"
			elif activity in _attention_cfg.entertainment_activities:
				kind = "entertainment"
		counts[kind] += 1
	students.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if is_equal_approx(float(a.pressure), float(b.pressure)):
				return int(a.index) < int(b.index)
			return float(a.pressure) > float(b.pressure)
	)
	return {"high_pressure_students": students, "activity_counts": counts}


## 存档字段（计划 §6）：mode / ended_day / 相位游标 / 配置指纹。
## ⚠️ 时间游标单独保存**不能**恢复同种子局 —— 完整恢复需要内核的完整序列化（属存档任务）。
## 本组件只保证「日末简报边界」可安全恢复：恢复后先显示同一日简报，点继续才开下一天。
func save_state() -> Dictionary:
	var cursor: Dictionary = _core.time_snapshot() if _core != null else {}
	return {
		"version": SAVE_VERSION,
		"config_fingerprint": _config_fingerprint(),
		"mode": _mode,
		"ended_day": _ended_day,
		"accumulator": 0.0 if _mode != MODE_RUNNING else _accumulator,
		"cursor": cursor,
	}


## 恢复时间状态：接受「版本与配置指纹一致」的运行中（running）与日末简报（report）快照，
## 以及期末（finished）。恢复须在 bind_core 之后调用（snapshot 要读 _core）。
## running 恢复 _accumulator（相位内真实秒累计），report/finished 清空累计。
func restore_state(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("SimulationClock：存档版本不一致，拒绝恢复时间状态。")
		return false
	if str(data.get("config_fingerprint", "")) != _config_fingerprint():
		push_warning("SimulationClock：配置指纹不一致，拒绝恢复时间状态。")
		return false
	var mode := str(data.get("mode", MODE_RUNNING))
	_ended_day = int(data.get("ended_day", 0))
	if mode == MODE_REPORT:
		_mode = MODE_REPORT
		_accumulator = 0.0
	elif mode == MODE_RUNNING:
		_mode = MODE_RUNNING
		_accumulator = float(data.get("accumulator", 0.0))
	elif mode == MODE_FINISHED:
		_mode = MODE_FINISHED
		_accumulator = 0.0
	else:
		push_warning("SimulationClock：未知 mode（%s），拒绝恢复时间状态。" % mode)
		return false
	time_updated.emit(snapshot())
	return true


## 配置指纹：相位呈现表 + 运行时参数的内容摘要（phases 由内核读，不重复纳入）。
func _config_fingerprint() -> String:
	var presentation_rows: Array = _tables.get(PRESENTATION_TABLE, {}).get("rows", [])
	var runtime_rows: Array = _tables.get(RUNTIME_TABLE, {}).get("rows", [])
	var parts := PackedStringArray()
	for row in presentation_rows:
		parts.append(
			"p:%s:%s" % [str(row.get("phase_id", "")), str(row.get("real_duration_seconds", ""))]
		)
	for row in runtime_rows:
		parts.append("r:%s:%s" % [str(row.get("key", "")), str(row.get("value", ""))])
	return "\n".join(parts).sha256_text()


## 阶段显示名（HUD 用）：取 time_presentation 的 display_name，缺省回退 phase_id。
func display_name_of(phase_id: String) -> String:
	return _display_name_of(phase_id)


func _display_name_of(phase_id: String) -> String:
	return str(_display_names.get(phase_id, phase_id))


## 当前相位的一个 tick 折合多少真实秒（课间 1 秒、上课 1/6 秒）；结算相位为 0。
func _interval_of(snapshot_data: Dictionary) -> float:
	var phase_id := str(snapshot_data.get("phase_id", ""))
	var ticks := int(snapshot_data.get("tick_count", 0))
	if ticks <= 0:
		return 0.0
	var seconds: float = _phase_seconds.get(phase_id, 0.0)
	if seconds <= 0.0:
		return 0.0
	return seconds / float(ticks)


func _remaining_seconds(snapshot_data: Dictionary) -> float:
	var interval := _interval_of(snapshot_data)
	if interval <= 0.0:
		return 0.0
	var ticks_left := float(
		int(snapshot_data.get("tick_count", 0)) - int(snapshot_data.get("tick_in_phase", 0))
	)
	var fractional := clampf(_accumulator, 0.0, interval)
	return maxf(0.0, ticks_left * interval - fractional)


func _progress(snapshot_data: Dictionary) -> float:
	var total := float(int(snapshot_data.get("tick_count", 0)))
	if total <= 0.0:
		return 0.0
	var interval := _interval_of(snapshot_data)
	var fractional := 0.0 if interval <= 0.0 else clampf(_accumulator / interval, 0.0, 1.0)
	var done := float(int(snapshot_data.get("tick_in_phase", 0)))
	return clampf((done + fractional) / total, 0.0, 1.0)


func _enter_report() -> void:
	# 辞退终止（§11.4）：任一次考核不达标或出现退学时，老师被辞退 —— 世界立刻停在日末，
	# 并带上触发判据说明原因；此时不再继续下一天。
	if _core != null:
		var failure: String = str(_core._failure_reason())
		if failure != "":
			_failure_reason = failure
			_mode = MODE_FINISHED
			term_finished.emit(_ended_day)
			report_ready.emit(_ended_day)
			return
	if _ended_day >= _term_days:
		_mode = MODE_FINISHED
		term_finished.emit(_ended_day)
		return
	_mode = MODE_REPORT
	report_ready.emit(_ended_day)
