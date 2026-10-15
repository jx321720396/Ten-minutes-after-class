extends RefCounted
## 按日隔离的观察记录。只收明确可见事件与共享笔记，不读取模拟矩阵。

const CONFIG := preload("res://scripts/ui/clue_board_settings.gd")
var state: Dictionary = {"days": {}, "sealed": {}}
var _config: Dictionary = CONFIG.read()


func record_event(payload: Dictionary, stamp: Dictionary, students: Array) -> void:
	var kind := str(payload.get("kind", ""))
	var day := int(stamp.get("day", 0))
	if not _config.public_events.has(kind) or day <= 0 or state.sealed.has(str(day)):
		return
	var a := int(payload.get("i", -1))
	var b := int(payload.get("j", -1))
	if a == b or not students.has(a) or not students.has(b):
		return
	var entry := stamp.duplicate(true)
	entry.merge({"kind": kind, "i": a, "j": b, "accepted": payload.get("accepted", true)}, true)
	var key := str(day)
	if not state.days.has(key):
		state.days[key] = []
	var entries: Array = state.days[key]
	for previous in entries:
		if (
			previous.kind == kind
			and int(previous.i) == a
			and int(previous.j) == b
			and int(previous.get("global_tick", -1)) == int(entry.get("global_tick", -1))
			and previous.accepted == entry.accepted
		):
			return
	entries.append(entry)


func page(day: int, notebook: Dictionary, students: Array) -> Dictionary:
	if state.sealed.has(str(day)):
		return state.sealed[str(day)].duplicate(true)
	var result := {"day": day, "people": [], "events": [], "judgments": []}
	for entry in state.days.get(str(day), []):
		if students.has(int(entry.i)) and students.has(int(entry.j)):
			result.events.append(entry.duplicate(true))
	var latest := {}
	for entry in notebook.get("history", []):
		if not _valid_judgment(entry, day, students):
			continue
		var key := "%s:%s:%s" % [entry.source, entry.subject, entry.axis]
		if str(entry.get("band", "")) == "unknown":
			latest.erase(key)
		else:
			latest[key] = entry.duplicate(true)
	result.judgments = latest.values()
	for entry in result.events:
		_add_person(result.people, int(entry.i))
		_add_person(result.people, int(entry.j))
	for entry in result.judgments:
		_add_person(result.people, int(entry.source))
		_add_person(result.people, int(entry.subject))
	result.people.sort()
	return result


func seal(day: int, notebook: Dictionary, students: Array) -> void:
	if not state.sealed.has(str(day)):
		state.sealed[str(day)] = page(day, notebook, students)


func _valid_judgment(entry: Dictionary, day: int, students: Array) -> bool:
	return (
		int(entry.get("day", 0)) == day
		and students.has(int(entry.get("source", -1)))
		and students.has(int(entry.get("subject", -1)))
		and int(entry.source) != int(entry.subject)
		and str(entry.get("axis", "")) in ["affinity", "hostility"]
	)


func _add_person(people: Array, index: int) -> void:
	if not people.has(index):
		people.append(index)
