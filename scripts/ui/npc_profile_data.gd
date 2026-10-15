class_name NpcProfileData
extends RefCounted
## 独立观察笔记：只接收已获知消息，不持有内核，不写真实矩阵。

const AXES := ["affinity", "hostility"]
var state: Dictionary = {"current": {}, "history": [], "seen": {}}


func mark(source: int, subject: int, axis: String, band: String, stamp: Dictionary) -> void:
	if source == subject or not AXES.has(axis):
		return
	var entry := stamp.duplicate(true)
	entry.merge(
		{"source": source, "subject": subject, "axis": axis, "band": band, "origin": "guess"}, true
	)
	_append(entry)
	if band == "unknown":
		state.current.erase(_key(source, subject, axis))


func build(records: Array, source: int, subject: int) -> Dictionary:
	var incoming: Array = []
	for record in records:
		if record is Dictionary:
			incoming.append(record.duplicate(true))
	incoming.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				int(a["clue_id"] if a.has("clue_id") else 0)
				< int(b["clue_id"] if b.has("clue_id") else 0)
			)
	)
	for clue in incoming:
		if (
			not AXES.has(str(clue.get("axis", "")))
			or not clue.has("clue_id")
			or not clue.has("source")
			or not clue.has("subject")
		):
			continue
		if not (clue.get("value") is float or clue.get("value") is int):
			continue
		if not is_finite(float(clue.value)):
			continue
		var id := str(clue.clue_id)
		if state.seen.has(id):
			continue
		state.seen[id] = true
		clue.origin = "known"
		_append(clue)
	var latest := {}
	for axis in AXES:
		var key := _key(source, subject, axis)
		if state.current.has(key):
			latest[axis] = state.current[key].duplicate(true)
	var history: Array = []
	for entry in state.history:
		if int(entry.source) == source and int(entry.subject) == subject:
			history.push_front(entry.duplicate(true))
	return {"latest": latest, "history": history}


func _append(entry: Dictionary) -> void:
	state.current[_key(int(entry.source), int(entry.subject), str(entry.axis))] = entry.duplicate(
		true
	)
	state.history.append(entry.duplicate(true))


func _key(source: int, subject: int, axis: String) -> String:
	return "%d:%d:%s" % [source, subject, axis]
