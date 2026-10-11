class_name NpcProfileData
extends RefCounted
## 只读呈现模型：只接收已获得的历史；不持有SimCore，不读取隐藏关系矩阵。

const AXES := ["affinity", "hostility", "trust"]


func build(records: Array, source: int, subject: int) -> Dictionary:
	var history: Array = []
	var encounters := {}
	var seen := {}
	for record in records:
		if not record is Dictionary or not _valid(record):
			continue
		if int(record.source) != source:
			continue
		var key := int(record.clue_id)
		if seen.has(key):
			continue
		seen[key] = true
		var copy: Dictionary = record.duplicate(true)
		var request := int(copy.get("request_id", key))
		if not encounters.has(request):
			encounters[request] = copy.duplicate(true)
			encounters[request]["count"] = 0
		encounters[request].count += 1
		if int(copy.subject) == subject:
			history.append(copy)
	history.sort_custom(_newer)
	var latest := {}
	for clue in history:
		if not latest.has(clue.axis):
			latest[clue.axis] = clue.duplicate(true)
	var chats: Array = encounters.values()
	chats.sort_custom(_newer)
	return {"latest": latest, "history": history, "encounters": chats}


func _valid(clue: Dictionary) -> bool:
	return (
		clue.has("clue_id")
		and clue.has("source")
		and clue.has("subject")
		and AXES.has(str(clue.get("axis", "")))
		and (clue.get("value") is float or clue.get("value") is int)
		and is_finite(float(clue.value))
	)


func _newer(a: Dictionary, b: Dictionary) -> bool:
	var a_tick := int(a.get("global_tick", 0))
	var b_tick := int(b.get("global_tick", 0))
	if a_tick == b_tick:
		return int(a.clue_id) > int(b.clue_id)
	return a_tick > b_tick
