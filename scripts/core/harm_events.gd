class_name HarmEvents
extends RefCounted
## 课间冲突（2026-10-18）：吵架 / 推搡 / 打架。
##
## 课间开始、学生选定活动之前判定一次。档位取双方敌对的较低值，
## 同一对人只进一档，每人只进一场。不改压力。只有打架记为伤害。

var _quarrel_min := 40.0
var _shove_min := 60.0
var _fight_min := 90.0
var _seconds := 20
var _quarrel_gain := 10.0
var _quarrel_mediate := 5.0
var _shove_gain := 15.0
var _shove_mediate := 10.0
var _fight_cut := 40.0
var _quarrel_cooldown := 4
var _shove_cooldown := 4
var _mediate_cut := 10.0
var _mediate_cooldown := 3
var _friendly_cut := 2.0
var _spot_x := -2.05
var _spot_z := 0.0
var _spot_gap := 0.8

var _active: Array = []
var _kind_of: Array = []
var _partner_of: Array = []
var _fight_count: Array = []
var _quarrel_until: Dictionary = {}
var _shove_until: Dictionary = {}
var _mediate_until: Dictionary = {}
var _break_serial := 0
var _last_events: Array = []


func configure(table: Dictionary) -> void:
	_quarrel_min = float(table.get("quarrel_min", _quarrel_min))
	_shove_min = float(table.get("shove_min", _shove_min))
	_fight_min = float(table.get("fight_min", _fight_min))
	_seconds = int(float(table.get("conflict_seconds", _seconds)))
	_quarrel_gain = float(table.get("quarrel_hostility_gain", _quarrel_gain))
	_quarrel_mediate = float(table.get("quarrel_mediate_gain", _quarrel_mediate))
	_shove_gain = float(table.get("shove_hostility_gain", _shove_gain))
	_shove_mediate = float(table.get("shove_mediate_gain", _shove_mediate))
	_fight_cut = float(table.get("fight_hostility_cut", _fight_cut))
	_quarrel_cooldown = int(float(table.get("quarrel_cooldown_breaks", _quarrel_cooldown)))
	_shove_cooldown = int(float(table.get("shove_cooldown_breaks", _shove_cooldown)))
	_mediate_cut = float(table.get("mediate_hostility_cut", _mediate_cut))
	_mediate_cooldown = int(float(table.get("mediate_cooldown_breaks", _mediate_cooldown)))
	_friendly_cut = float(table.get("friendly_chat_hostility_cut", _friendly_cut))
	_spot_x = float(table.get("conflict_spot_x", _spot_x))
	_spot_z = float(table.get("conflict_spot_z", _spot_z))
	_spot_gap = float(table.get("conflict_pair_gap", _spot_gap))


func begin_phase(count: int) -> void:
	_ensure(count)
	_active = []
	for i in range(count):
		_kind_of[i] = ""
		_partner_of[i] = -1


func friendly_cut() -> float:
	return _friendly_cut


func mediate_cut() -> float:
	return _mediate_cut


func last_events() -> Array:
	return _last_events


func active_kind(i: int) -> String:
	if i < 0 or i >= _kind_of.size():
		return ""
	return str(_kind_of[i])


func partner_of(i: int) -> int:
	if i < 0 or i >= _partner_of.size():
		return -1
	return int(_partner_of[i])


func fight_count_of(i: int) -> int:
	if i < 0 or i >= _fight_count.size():
		return 0
	return int(_fight_count[i])


func spot() -> Vector2:
	return Vector2(_spot_x, _spot_z)


func spot_gap() -> float:
	return _spot_gap


## 课间开始判定一次。考试日与非课间不判定，冷却按实际课间计数。
func begin_break(core: Variant) -> void:
	if str(core._current_phase_kind()) != "break" or bool(core._is_exam_only_day()):
		return
	_last_events = []
	_break_serial += 1
	_judge(core)


## 每秒推进进行中的冲突；到点按自然结束结算。
func tick(core: Variant) -> void:
	if str(core._current_phase_kind()) != "break" or _active.is_empty():
		return
	var finished: Array = []
	for item in _active:
		item["remaining"] = int(item["remaining"]) - 1
		if int(item["remaining"]) <= 0:
			finished.append(item)
	for item in finished:
		_settle(core, int(item["a"]), int(item["b"]), str(item["kind"]), false)


## 调解。返回 stopped / queued / fight / cooldown / invalid。
## stopped：立刻终止吵架或推搡，敌对按中断幅度结算，不再另减 10。
## queued：没有可终止的冲突，等命令走完再双方 −10。
## fight：打架不能终止。
func mediate(core: Variant, a: int, b: int) -> String:
	var n := int(core.node_count())
	if a < 0 or b < 0 or a == b or a >= n or b >= n:
		return "invalid"
	if _mediate_blocked(a, b):
		return "cooldown"
	var kind := _pair_active(a, b)
	if kind == "fight":
		return "fight"
	if kind == "quarrel" or kind == "shove":
		_settle(core, a, b, kind, true)
		return "stopped"
	return "queued"


## 调解命令结束的课间起，记三个课间冷却。进行中被终止的冲突不再减 10。
func finish_mediate(core: Variant, a: int, b: int, apply_cut: bool) -> void:
	if apply_cut:
		core._add_hostility(a, b, -_mediate_cut)
		core._add_hostility(b, a, -_mediate_cut)
	_mediate_until[_key(a, b)] = _break_serial + _mediate_cooldown


func export_state() -> Dictionary:
	return {
		"fight_count": _fight_count.duplicate(),
		"quarrel_until": _quarrel_until.duplicate(),
		"shove_until": _shove_until.duplicate(),
		"mediate_until": _mediate_until.duplicate(),
		"break_serial": _break_serial,
		"active": _active.duplicate(true),
		"kind_of": _kind_of.duplicate(),
		"partner_of": _partner_of.duplicate(),
	}


func restore_state(data: Dictionary) -> void:
	_fight_count = []
	for v in data.get("fight_count", []):
		_fight_count.append(int(v))
	_quarrel_until = data.get("quarrel_until", {}).duplicate()
	_shove_until = data.get("shove_until", {}).duplicate()
	_mediate_until = data.get("mediate_until", {}).duplicate()
	_break_serial = int(data.get("break_serial", 0))
	_active = data.get("active", []).duplicate(true)
	_kind_of = data.get("kind_of", []).duplicate()
	_partner_of = data.get("partner_of", []).duplicate()
	_last_events = []


func _ensure(count: int) -> void:
	while _kind_of.size() < count:
		_kind_of.append("")
		_partner_of.append(-1)
		_fight_count.append(0)
	if _kind_of.size() > count:
		_kind_of.resize(count)
		_partner_of.resize(count)
		_fight_count.resize(count)


func _judge(core: Variant) -> void:
	var n := int(core.node_count())
	_ensure(n)
	var taken: Array = []
	for _i in range(n):
		taken.append(false)
	var pairs: Array = []
	for i in range(n):
		if not _eligible(core, i):
			continue
		for j in range(i + 1, n):
			if not _eligible(core, j):
				continue
			var low := minf(float(core.hostility(i, j)), float(core.hostility(j, i)))
			var kind := _tier(low)
			if kind == "" or _cooled(kind, i, j):
				continue
			pairs.append({"a": i, "b": j, "kind": kind, "low": low, "rank": _rank(kind)})
	pairs.sort_custom(
		func(p: Dictionary, q: Dictionary) -> bool:
			if int(p["rank"]) != int(q["rank"]):
				return int(p["rank"]) > int(q["rank"])
			if float(p["low"]) != float(q["low"]):
				return float(p["low"]) > float(q["low"])
			if int(p["a"]) != int(q["a"]):
				return int(p["a"]) < int(q["a"])
			return int(p["b"]) < int(q["b"])
	)
	for pair in pairs:
		var a := int(pair["a"])
		var b := int(pair["b"])
		if bool(taken[a]) or bool(taken[b]):
			continue
		taken[a] = true
		taken[b] = true
		_start(core, a, b, str(pair["kind"]))


func _eligible(core: Variant, i: int) -> bool:
	return bool(core.is_present(i)) and not bool(core.is_broken(i))


func _tier(low: float) -> String:
	if low >= _fight_min:
		return "fight"
	if low >= _shove_min:
		return "shove"
	if low >= _quarrel_min:
		return "quarrel"
	return ""


func _rank(kind: String) -> int:
	match kind:
		"fight":
			return 3
		"shove":
			return 2
		"quarrel":
			return 1
	return 0


func _cooled(kind: String, a: int, b: int) -> bool:
	var until := 0
	match kind:
		"quarrel":
			until = int(_quarrel_until.get(_key(a, b), 0))
		"shove":
			until = int(_shove_until.get(_key(a, b), 0))
	return _break_serial < until


func _mediate_blocked(a: int, b: int) -> bool:
	return _break_serial < int(_mediate_until.get(_key(a, b), 0))


func _pair_active(a: int, b: int) -> String:
	if active_kind(a) != "" and partner_of(a) == b:
		return active_kind(a)
	return ""


func _start(core: Variant, a: int, b: int, kind: String) -> void:
	_active.append({"a": a, "b": b, "kind": kind, "remaining": _seconds})
	_kind_of[a] = kind
	_kind_of[b] = kind
	_partner_of[a] = b
	_partner_of[b] = a
	core._enter_conflict(a, kind)
	core._enter_conflict(b, kind)
	_last_events.append({"kind": kind, "from": a, "to": b, "tick": int(core.global_tick())})


func _settle(core: Variant, a: int, b: int, kind: String, mediated: bool) -> void:
	var kept: Array = []
	for item in _active:
		if int(item["a"]) == a and int(item["b"]) == b:
			continue
		kept.append(item)
	_active = kept
	if a < _kind_of.size():
		_kind_of[a] = ""
		_partner_of[a] = -1
	if b < _kind_of.size():
		_kind_of[b] = ""
		_partner_of[b] = -1
	core._leave_conflict(a)
	core._leave_conflict(b)
	var delta := 0.0
	match kind:
		"quarrel":
			delta = _quarrel_mediate if mediated else _quarrel_gain
			_quarrel_until[_key(a, b)] = _break_serial + _quarrel_cooldown
		"shove":
			delta = _shove_mediate if mediated else _shove_gain
			_shove_until[_key(a, b)] = _break_serial + _shove_cooldown
		"fight":
			delta = -_fight_cut
			_fight_count[a] = int(_fight_count[a]) + 1
			_fight_count[b] = int(_fight_count[b]) + 1
			core._note_harm(a, b, "fight")
	if delta != 0.0:
		core._add_hostility(a, b, delta)
		core._add_hostility(b, a, delta)


func _key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]
