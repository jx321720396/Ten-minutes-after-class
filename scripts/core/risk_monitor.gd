class_name RiskMonitor
extends RefCounted
## 风险判定、预警与失败（《老师版规则合并稿》D06 / 主文档第十一章）。
##
## 霸凌：至少 3 名其他学生对目标敌对 >50，且目标曾经打过一次架；
## 孤立：其他所有学生对目标好感 <20，且当天主动找伴被拒 ≥2 次、当天没有成功参加共同活动
##      （忙碌、满员不算关系拒绝）；退学：累计崩溃超过 3 次，或正式触发霸凌／孤立后再次崩溃。
## 第一天满足只预警，连续第二天才正式触发；中间一天不满足则重置连续计数；只统计实际事件，
## 初始关系差不直接触发；预警与正式触发本身不直接辞退。判据参数读 data/rules/risk.csv。

var _window := 2
var _earliest_day := 2
var _bully_threshold := 50.0
var _bully_min_enemies := 3
var _bully_daily_harm := 1
var _isolate_affinity := 20.0
var _isolate_rejects := 2
var _isolate_no_activity := true
var _dropout_limit := 3
var _dropout_after_risk := 1

var _breakdowns: Array = []
var _rejects_today: Array = []
var _activity_today: Array = []
var _harm_today: Array = []
var _ever_fought: Array = []
var _streak: Array = []
var _warned: Array = []
var _triggered: Array = []
var _triggered_kind: Array = []
var _breakdowns_at_trigger: Array = []
var _dropped: Array = []
var _events: Array = []


func configure(table: Dictionary, count: int) -> void:
	_window = int(float(table.get("window_days", _window)))
	_earliest_day = int(float(table.get("earliest_day", _earliest_day)))
	_bully_threshold = float(table.get("bully_hostility_threshold", _bully_threshold))
	_bully_min_enemies = int(float(table.get("bully_min_enemies", _bully_min_enemies)))
	_bully_daily_harm = int(float(table.get("bully_daily_harm_min", _bully_daily_harm)))
	_isolate_affinity = float(table.get("isolate_affinity_threshold", _isolate_affinity))
	_isolate_rejects = int(float(table.get("isolate_daily_rejects", _isolate_rejects)))
	_isolate_no_activity = int(float(table.get("isolate_require_no_activity", 1))) == 1
	_dropout_limit = int(float(table.get("dropout_breakdown_limit", _dropout_limit)))
	_dropout_after_risk = int(
		float(table.get("dropout_after_risk_breakdowns", _dropout_after_risk))
	)
	_breakdowns = _zeros(count, 0)
	_rejects_today = _zeros(count, 0)
	_activity_today = _zeros(count, false)
	_harm_today = _empty_lists(count)
	_ever_fought = _zeros(count, false)
	_streak = _zeros(count, 0)
	_warned = _zeros(count, false)
	_triggered = _zeros(count, false)
	_triggered_kind = _texts(count)
	_breakdowns_at_trigger = _zeros(count, 0)
	_dropped = _zeros(count, false)
	_events = []


# ------------------------------------------------------------------ 事件登记
func register_breakdown(i: int) -> void:
	if i >= 0 and i < _breakdowns.size():
		_breakdowns[i] = int(_breakdowns[i]) + 1


## 主动找伴被拒（忙碌、满员不算关系拒绝，调用方只登记真实的关系拒绝）。
func register_join_reject(i: int) -> void:
	if i >= 0 and i < _rejects_today.size():
		_rejects_today[i] = int(_rejects_today[i]) + 1


func register_activity(i: int) -> void:
	if i >= 0 and i < _activity_today.size():
		_activity_today[i] = true


## 只有打架记伤害。双方都算「曾经打过一次架」，不要求对手属于当天的敌对者。
func register_harm(from_i: int, to_i: int, kind: String) -> void:
	if kind != "fight":
		return
	for idx in [from_i, to_i]:
		if idx >= 0 and idx < _ever_fought.size():
			_ever_fought[idx] = true


# ------------------------------------------------------------------ 每日判定
## 一天结束时判定（在跨天结算里调用，day = 刚结束的那一天）。
func settle_day(core: Variant, day: int) -> void:
	_events = []
	# 2026-10-16 定稿：考试日跳过判定但**保留连续计数**（考试不能自动洗掉风险）。
	if bool(core._is_exam_only_day()):
		return
	var n := int(core.node_count())
	for i in range(n):
		if bool(_dropped[i]):
			continue
		var reason := _daily_reason(core, i)
		if reason == "":
			_streak[i] = 0
		else:
			_streak[i] = int(_streak[i]) + 1
			if int(_streak[i]) == 1:
				_warned[i] = true
				_events.append({"kind": "warn", "of": i, "reason": reason, "day": day})
			elif int(_streak[i]) >= _window and day >= _earliest_day and not bool(_triggered[i]):
				_triggered[i] = true
				_triggered_kind[i] = reason
				_breakdowns_at_trigger[i] = int(_breakdowns[i])
				_events.append({"kind": "trigger", "of": i, "reason": reason, "day": day})
		# 退学判据：累计崩溃超过 3 次；或正式触发风险后再崩溃一次。
		var quota: int = _dropout_limit + 1
		if bool(_triggered[i]):
			quota = mini(quota, int(_breakdowns_at_trigger[i]) + _dropout_after_risk)
		if int(_breakdowns[i]) >= quota:
			_dropped[i] = true
			_events.append({"kind": "dropout", "of": i, "day": day})
	for i in range(n):
		_rejects_today[i] = 0
		_activity_today[i] = false
		_harm_today[i] = []


## 当天是否满足霸凌／孤立之一；返回 "" / "bully" / "isolate"。
func _daily_reason(core: Variant, i: int) -> String:
	if _is_bullied(core, i):
		return "bully"
	if _is_isolated(core, i):
		return "isolate"
	return ""


func _is_bullied(core: Variant, i: int) -> bool:
	var n := int(core.node_count())
	var enemies: Array = []
	for j in range(n):
		if j == i:
			continue
		if float(core.hostility(j, i)) > _bully_threshold:
			enemies.append(j)
	if enemies.size() < _bully_min_enemies:
		return false
	return i >= 0 and i < _ever_fought.size() and bool(_ever_fought[i])


func _is_isolated(core: Variant, i: int) -> bool:
	var n := int(core.node_count())
	for j in range(n):
		if j == i:
			continue
		if float(core.affinity(j, i)) >= _isolate_affinity:
			return false
	if _isolate_no_activity and bool(_activity_today[i]):
		return false
	return int(_rejects_today[i]) >= _isolate_rejects


# ------------------------------------------------------------------ 只读查询
func is_dropped(i: int) -> bool:
	return i >= 0 and i < _dropped.size() and bool(_dropped[i])


func has_dropout() -> bool:
	for flag in _dropped:
		if bool(flag):
			return true
	return false


func warned_of(i: int) -> bool:
	return i >= 0 and i < _warned.size() and bool(_warned[i])


func triggered_of(i: int) -> bool:
	return i >= 0 and i < _triggered.size() and bool(_triggered[i])


func breakdowns_of(i: int) -> int:
	return int(_breakdowns[i]) if i >= 0 and i < _breakdowns.size() else 0


## 上一次每日判定产生的事件（预警 / 正式触发 / 退学），供简报与界面只读展示。
func last_events() -> Array:
	return _events


func snapshot() -> Dictionary:
	return {
		"breakdowns": _breakdowns.duplicate(),
		"streak": _streak.duplicate(),
		"warned": _warned.duplicate(),
		"triggered": _triggered.duplicate(),
		"triggered_kind": _triggered_kind.duplicate(),
		"dropped": _dropped.duplicate(),
	}


func _zeros(count: int, value: Variant) -> Array:
	var out: Array = []
	for _i in range(count):
		out.append(value)
	return out


func _empty_lists(count: int) -> Array:
	var out: Array = []
	for _i in range(count):
		out.append([])
	return out


func _texts(count: int) -> Array:
	var out: Array = []
	for _i in range(count):
		out.append("")
	return out


# ------------------------------------------------------------------ 存档
## 导出风险判定运行时状态（连续计数 / 当日证据 / 触发 / 退学）。_events 是瞬态，不存。
func export_state() -> Dictionary:
	return {
		"breakdowns": _breakdowns.duplicate(),
		"rejects_today": _rejects_today.duplicate(),
		"activity_today": _activity_today.duplicate(),
		"harm_today": _harm_today.duplicate(true),
		"ever_fought": _ever_fought.duplicate(),
		"streak": _streak.duplicate(),
		"warned": _warned.duplicate(),
		"triggered": _triggered.duplicate(),
		"triggered_kind": _triggered_kind.duplicate(),
		"breakdowns_at_trigger": _breakdowns_at_trigger.duplicate(),
		"dropped": _dropped.duplicate(),
	}


## 回填风险判定状态（读档用）。JSON 往返把 int / bool 变 float，逐个还原。
func restore_state(data: Dictionary) -> void:
	_breakdowns = _ints(data.get("breakdowns", []))
	_rejects_today = _ints(data.get("rejects_today", []))
	_activity_today = _bools(data.get("activity_today", []))
	_harm_today = []
	for bucket in data.get("harm_today", []):
		var items: Array = []
		for hit in bucket:
			items.append({"from": int(hit.get("from", -1)), "kind": str(hit.get("kind", ""))})
		_harm_today.append(items)
	_ever_fought = _bools(data.get("ever_fought", []))
	_streak = _ints(data.get("streak", []))
	_warned = _bools(data.get("warned", []))
	_triggered = _bools(data.get("triggered", []))
	_triggered_kind = _strs(data.get("triggered_kind", []))
	_breakdowns_at_trigger = _ints(data.get("breakdowns_at_trigger", []))
	_dropped = _bools(data.get("dropped", []))
	_events = []


func _ints(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(int(v))
	return out


func _bools(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(bool(v))
	return out


func _strs(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(str(v))
	return out
