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

const PRESENTATION_TABLE := "rules/time_presentation"
const RUNTIME_TABLE := "rules/time_runtime"
const PHASES_TABLE := "rules/phases"
const SETTLE_KIND := "settle"

var _core: SimCore = null
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
var _term_days := 0
var _max_ticks_per_frame := 1


func _process(delta: float) -> void:
	pump(delta)


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
	if _term_days <= 0:
		return "SimulationClock：term_days 必须是正整数（当前 %d）。" % _term_days
	if _max_ticks_per_frame <= 0:
		return "SimulationClock：max_ticks_per_frame 必须是正整数（当前 %d）。" % _max_ticks_per_frame
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


## 暂停：按拥有者集合管理，可重入；同名重复添加不累计，最后一个释放才恢复。
func hold(owner: StringName) -> void:
	_paused_by[owner] = true


func release(owner: StringName) -> void:
	_paused_by.erase(owner)


func is_paused() -> bool:
	return not _paused_by.is_empty()


## 日末简报「继续」：仅 report 状态可用；清空累计真实时间，进入下一天。
func continue_after_report() -> bool:
	if _mode != MODE_REPORT:
		return false
	_mode = MODE_RUNNING
	_accumulator = 0.0
	_ended_day = 0
	time_updated.emit(snapshot())
	return true


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
	out["remaining_seconds"] = _remaining_seconds(out)
	out["progress"] = _progress(out)
	out["ended_day"] = _ended_day
	out["term_days"] = _term_days
	out["display_name"] = _display_name_of(str(out.get("phase_id", "")))
	return out


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
	if _ended_day >= _term_days:
		_mode = MODE_FINISHED
		term_finished.emit(_ended_day)
		return
	_mode = MODE_REPORT
	report_ready.emit(_ended_day)
