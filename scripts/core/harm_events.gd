class_name HarmEvents
extends RefCounted
## 伤害事件（《老师版规则合并稿》D07 / 主文档第十章）：只有「恶语攻击」与「推搡」两类。
##
## 条件：课间接触、发起者对目标敌对超过门槛、双方都不得处于学习锁定 / 办公室 / 崩溃；
## 每 10 秒检查一次，满足条件后**按固定概率随机触发**（概率与增量是合并稿明确「待定」的参数，
## 读 data/rules/harm.csv 的可运行初值）。
## 遍历顺序固定（发起者升序 → 目标升序），随机消耗与 tools/core_sim.py 保持同序，同种子可复现。
## 高敌对不保证必然发生伤害：普通拒绝、无意碰撞与正常打闹都不走这里。

var _aggression_threshold := 40.0
var _shove_threshold := 70.0
var _aggression_p := 0.05
var _shove_p := 0.05
var _aggression_stress := 5.0
var _aggression_hostility := 3.0
var _shove_stress := 10.0
var _shove_hostility := 5.0
var _shove_preferred := true
var _check_seconds := 10
var _friendly_cut := 2.0
var _mediate_threshold := 50.0
var _mediate_cut := 5.0
var _last_events: Array = []
## 每人每课间最多主动伤害一次（两类共用次数，§10）。
var _struck_this_phase: Array = []


func configure(table: Dictionary) -> void:
	_aggression_threshold = float(
		table.get("aggression_hostility_threshold", _aggression_threshold)
	)
	_shove_threshold = float(table.get("shove_hostility_threshold", _shove_threshold))
	_aggression_p = float(table.get("aggression_trigger_p", _aggression_p))
	_shove_p = float(table.get("shove_trigger_p", _shove_p))
	_aggression_stress = float(table.get("aggression_target_stress", _aggression_stress))
	_aggression_hostility = float(table.get("aggression_hostility_gain", _aggression_hostility))
	_shove_stress = float(table.get("shove_target_stress", _shove_stress))
	_shove_hostility = float(table.get("shove_hostility_gain", _shove_hostility))
	_shove_preferred = int(float(table.get("shove_preferred_when_both", 1))) == 1
	_check_seconds = int(float(table.get("check_seconds", _check_seconds)))
	_friendly_cut = float(table.get("friendly_chat_hostility_cut", _friendly_cut))
	_mediate_threshold = float(table.get("mediate_hostility_threshold", _mediate_threshold))
	_mediate_cut = float(table.get("mediate_hostility_cut", _mediate_cut))


## 段首重置「每课间一次」的计数（两类共用）。
func begin_phase(count: int) -> void:
	_struck_this_phase = []
	for _i in range(count):
		_struck_this_phase.append(false)


func check_seconds() -> int:
	return _check_seconds


func friendly_cut() -> float:
	return _friendly_cut


func mediate_threshold() -> float:
	return _mediate_threshold


func mediate_cut() -> float:
	return _mediate_cut


## 上一次检查触发的事件（表现层 / 简报只读）。
func last_events() -> Array:
	return _last_events


## 一次伤害检查（主循环每 check_seconds 调一次）；返回本次触发条数。
func check(core: Variant) -> int:
	_last_events = []
	# §369：伤害发生在「课间接触」。
	if str(core._current_phase_kind()) != "break":
		return 0
	var n := int(core.node_count())
	for i in range(n):
		if not _can_act(core, i):
			continue
		# §10：每人每课间最多主动伤害一次；老师制止后本课间不能再发起。
		if i < _struck_this_phase.size() and bool(_struck_this_phase[i]):
			continue
		if bool(core._is_stopped_by_teacher(i)):
			continue
		for j in range(n):
			if i == j or not _can_act(core, j):
				continue
			if not (core._shares_activity(i, j) or core._are_neighbors(i, j)):
				continue
			var hostility: float = float(core.hostility(i, j))
			var kind := ""
			if hostility > _shove_threshold:
				# 门槛更高的一类优先（合并稿的「两类同时满足时的选择方式」仍待确认）。
				kind = "shove"
			elif hostility > _aggression_threshold:
				kind = "aggression"
			if kind == "":
				continue
			var probability := _shove_p if kind == "shove" else _aggression_p
			if float(core._next_unit_random()) >= probability:
				continue
			_apply(core, i, j, kind)
			if i < _struck_this_phase.size():
				_struck_this_phase[i] = true
			break  # 一次只触发一种（两类共用次数）
	return _last_events.size()


## 参与伤害的资格（§372）：不得处于学习锁定、办公室或崩溃。
func _can_act(core: Variant, i: int) -> bool:
	if not bool(core.is_present(i)) or bool(core.is_broken(i)):
		return false
	if bool(core._is_in_office(i)):
		return false
	return not bool(core._is_study_locked(i))


func _apply(core: Variant, from_i: int, to_i: int, kind: String) -> void:
	if kind == "shove":
		core.add_stress(to_i, _shove_stress)
		core._add_hostility(to_i, from_i, _shove_hostility)
		# 推搡额外中断目标当前活动（恶语不中断）。
		core._interrupt_activity(to_i)
	else:
		core.add_stress(to_i, _aggression_stress)
		core._add_hostility(to_i, from_i, _aggression_hostility)
	_last_events.append(
		{"kind": kind, "from": from_i, "to": to_i, "tick": int(core.global_tick())}
	)
	# 霸凌判据要看「当天受到这些人中至少一人发起的伤害」→ 记到风险监控里。
	core._note_harm(from_i, to_i, kind)
