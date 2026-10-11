class_name TimeFlow
extends Node
## 场景世界时间倍率：玩家行动时快进，事件可按拥有者临时持有正常速度。
## 每帧在世界消费者之前采样；内核仍逐 tick 运行，UI / 转笔演出保留真实 delta。

signal scale_changed(multiplier: float)

const CONFIG_TABLE := "rules/time_flow"
## 先于时钟、移动和表现消费者采样本帧速度（结构性处理顺序）。
const PROCESS_PRIORITY := -100

var _core: SimCore = null
var _clock: SimulationClock = null
var _normal_scale := 1.0
var _action_scale := 1.0
var _multiplier := 1.0
var _normal_owners: Dictionary = {}
var _study_seconds := 0.0
var _study_interval := 0.0
var _study_step := 0.0
var _frame_scale := 1.0


func _ready() -> void:
	process_priority = PROCESS_PRIORITY


func bind_sources(core: SimCore, clock: SimulationClock, tables: Dictionary = {}) -> bool:
	var config := tables if not tables.is_empty() else ConfigLoader.new().load_all()
	var params: Dictionary = {}
	for row in config.get(CONFIG_TABLE, {}).get("rows", []):
		params[str(row.get("param", ""))] = float(str(row.get("value", "0")))
	var normal := float(params.get("normal_scale", 0.0))
	var action := float(params.get("player_action_scale", 0.0))
	_study_interval = float(params.get("study_speed_interval_seconds", 0.0))
	_study_step = float(params.get("study_speed_step", 0.0))
	if (
		core == null
		or clock == null
		or not _valid_scales(normal, action)
		or not is_finite(_study_interval)
		or _study_interval <= 0.0
		or not is_finite(_study_step)
		or _study_step <= 0.0
	):
		_core = null
		_clock = null
		_set_multiplier(0.0)
		push_error("TimeFlow：需要有效内核与时钟，normal_scale 必须为 1，player_action_scale 必须为有限且不小于 1 的数。")
		return false
	_core = core
	_clock = clock
	_normal_scale = normal
	_action_scale = action
	_normal_owners.clear()
	_study_seconds = 0.0
	refresh()
	return true


func _valid_scales(normal: float, action: float) -> bool:
	return is_finite(normal) and is_finite(action) and normal == 1.0 and action >= normal


func _process(delta: float) -> void:
	refresh()
	if _world_stopped() or not _studying() or delta <= 0.0:
		return
	var before := _study_seconds
	_study_seconds += delta
	var world_seconds := _study_integral(_study_seconds) - _study_integral(before)
	refresh()
	if _normal_owners.is_empty():
		_frame_scale = world_seconds / delta


func _studying() -> bool:
	return (
		_core != null
		and bool(_core.time_snapshot().get("player_control", false))
		and _core.activity_of(_core.node_count() - 1) == "study"
	)


## 对跨越多个十秒边界的帧按分段倍率积分，避免整帧提前加速。
func _study_integral(seconds: float) -> float:
	var stages := floorf(seconds / _study_interval)
	var remainder := seconds - stages * _study_interval
	return (
		_normal_scale * seconds
		+ _study_step * (_study_interval * stages * (stages - 1.0) / 2.0 + stages * remainder)
	)


## 外部固定步长驱动也可在每帧开始显式采样；所有消费者随后使用同一倍率。
func refresh() -> void:
	var speed := _normal_scale
	if not _studying():
		_study_seconds = 0.0
	if _world_stopped():
		speed = 0.0
	elif _normal_owners.is_empty():
		var me := _core.node_count() - 1
		if bool(_core.time_snapshot().get("player_control", false)):
			if _studying():
				speed = _normal_scale + floorf(_study_seconds / _study_interval) * _study_step
			elif _core.is_busy(me):
				speed = _action_scale
	_set_multiplier(speed)
	_frame_scale = speed


func _world_stopped() -> bool:
	if _core == null or not is_instance_valid(_clock):
		return true
	if is_inside_tree() and get_tree().paused:
		return true
	return (
		_clock.is_paused() or str(_clock.snapshot().get("mode", "")) != SimulationClock.MODE_RUNNING
	)


func _set_multiplier(speed: float) -> void:
	if is_equal_approx(_multiplier, speed):
		return
	_multiplier = speed
	scale_changed.emit(speed)


func multiplier() -> float:
	return _multiplier


## delta 只缩放一次；暂停请求可在同一帧生效，不能多走一步。
func scale_delta(real_delta: float) -> float:
	if _world_stopped():
		return 0.0
	return maxf(real_delta, 0.0) * _frame_scale


## 同 owner 重复请求幂等，多个事件互不解除；正常速度锁不会冻结世界。
func request_normal_speed(owner: StringName) -> void:
	if owner == &"":
		return
	_normal_owners[owner] = true
	refresh()


func release_normal_speed(owner: StringName) -> void:
	_normal_owners.erase(owner)
	refresh()
