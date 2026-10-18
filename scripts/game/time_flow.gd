class_name TimeFlow
extends Node
## 场景世界时间倍率（老师版）：由玩家在左上角时间卡片上自选 1× / 2× / 3×，点一次循环换档。
##
## - 每帧在世界消费者之前采样；内核仍**逐 tick** 运行，UI 与演出用真实 delta，不受倍率影响。
## - 暂停只有一条来源：时钟 hold（日末简报、学期结束等）或 `get_tree().paused`（打开百科全书）。
##   没有"暂停档"：按你的裁定，暂停不属于速度选项。
## - 事件（简报、转笔演出等）仍可按 owner 临时持有**正常速度**；锁期间强制 1×，不被自选档位覆盖。
## - 老师谈话进行中由表现层自动持有「快进」锁、临时加速到 fast_forward_scale，结束自动还原；优先级在正常速度锁之下、自选档之上。
##
## 2026-10-16 移除学生版残留：玩家占用型行为自动 3×、连续学习每 10 秒逐档加速（玩家节点已不存在，
## 旧逻辑实际绑在末位学生身上，会造成莫名三倍速且学习时不封顶）。

signal scale_changed(multiplier: float)

const CONFIG_TABLE := "rules/time_flow"
## 先于时钟、移动和表现消费者采样本帧速度（结构性处理顺序）。
const PROCESS_PRIORITY := -100

var _core: SimCore = null
var _clock: SimulationClock = null
var _normal_scale := 1.0
var _options := 3
var _player_scale := 1.0
var _multiplier := 1.0
var _normal_owners: Dictionary = {}
var _fast_forward_scale := 1.0
var _fast_forward_owners: Dictionary = {}
var _frame_scale := 1.0


func _ready() -> void:
	process_priority = PROCESS_PRIORITY


func bind_sources(core: SimCore, clock: SimulationClock, tables: Dictionary = {}) -> bool:
	var config := tables if not tables.is_empty() else ConfigLoader.new().load_all()
	var params: Dictionary = {}
	for row in config.get(CONFIG_TABLE, {}).get("rows", []):
		params[str(row.get("param", ""))] = float(str(row.get("value", "0")))
	var normal := float(params.get("normal_scale", 0.0))
	var options := int(params.get("speed_options", 0))
	var fast := float(params.get("fast_forward_scale", normal))
	if core == null or clock == null or not _valid_config(normal, options, fast):
		_core = null
		_clock = null
		_set_multiplier(0.0)
		push_error("TimeFlow：需要有效内核与时钟；normal_scale=1、speed_options≥1、fast_forward_scale≥1 且有限。")
		return false
	_core = core
	_clock = clock
	_normal_scale = normal
	_options = options
	_fast_forward_scale = fast
	_player_scale = _normal_scale
	_normal_owners.clear()
	_fast_forward_owners.clear()
	refresh()
	return true


func _valid_config(normal: float, options: int, fast: float) -> bool:
	return (
		is_finite(normal) and normal == 1.0 and options >= 1 and is_finite(fast) and fast >= normal
	)


func _process(_delta: float) -> void:
	refresh()


## 可选倍速档位数（1× … N×）。
func speed_options() -> int:
	return _options


## 玩家当前自选倍速。
func player_scale() -> float:
	return _player_scale


## 点一次时间卡片：1× → 2× → … → N× → 1×。
func cycle_speed() -> float:
	var next := int(_player_scale) + 1
	if next > _options:
		next = 1
	set_speed(float(next))
	return _player_scale


## 直接设定倍速；越界或非有限值忽略并返回 false。
func set_speed(scale: float) -> bool:
	if not is_finite(scale) or scale < _normal_scale or scale > float(_options):
		return false
	_player_scale = scale
	refresh()
	return true


## 每帧采样：暂停 → 0；事件持有正常速度锁 → 1×；快进锁 → 快进倍速；否则用玩家自选档位。
func refresh() -> void:
	var speed := _player_scale
	if _world_stopped():
		speed = 0.0
	elif not _normal_owners.is_empty():
		speed = _normal_scale
	elif not _fast_forward_owners.is_empty():
		speed = _fast_forward_scale
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


## 老师谈话进行中的临时快进锁（表现层自动持有）；同名 owner 幂等，多个 owner 互不解除。
## 优先级低于正常速度锁：事件（简报、演出等）期间强制 1×，不被快进覆盖。
func request_fast_forward(owner: StringName) -> void:
	if owner == &"":
		return
	_fast_forward_owners[owner] = true
	refresh()


func release_fast_forward(owner: StringName) -> void:
	_fast_forward_owners.erase(owner)
	refresh()
