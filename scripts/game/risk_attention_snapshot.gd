extends RefCounted
## 仅将内核已结算风险转换为界面数据；不重新判定风险、不消费随机数。

var _source_id := 0
var _observed: Dictionary = {}


func build(core: SimCore, tables: Dictionary) -> Dictionary:
	if core.get_instance_id() != _source_id:
		_source_id = core.get_instance_id()
		_observed.clear()
	var result := {"bully": [], "isolate": [], "broken": []}
	var rules := {}
	for row in tables.get("rules/risk", {}).get("rows", []):
		rules[str(row.param)] = float(row.value)
	result["rules"] = rules
	var risk: Dictionary = core._risk_snapshot()
	var events: Array = core._risk.last_events() if core._risk != null else []
	for event in events:
		if event.get("kind") in ["warn", "trigger"]:
			_observed[int(event.of)] = event.duplicate(true)
	for index in range(core.node_count()):
		var entry := {
			"index": index,
			"name": core.alias(index),
			"pressure": core.stress(index),
			"breakdowns": int(risk.get("breakdowns", [])[index]),
			"streak": int(risk.get("streak", [])[index]),
			"formal": bool(risk.get("triggered", [])[index]),
			"dropped": bool(risk.get("dropped", [])[index]),
			"reason": str(risk.get("triggered_kind", [])[index]),
			"day": 0,
		}
		# 考试日事件列表会清空，只在观察层保留已读结算记录，不修改内核。
		if not entry.formal and entry.streak == 0:
			_observed.erase(index)
		var observed: Dictionary = _observed.get(index, {})
		if not entry.formal:
			entry.reason = str(observed.get("reason", ""))
		entry.day = int(observed.get("day", 0))
		if not entry.dropped:
			if (entry.formal or entry.streak > 0) and result.has(entry.reason):
				result[entry.reason].append(entry.duplicate())
			if core.is_broken(index):
				result.broken.append(entry.duplicate())
	return result
