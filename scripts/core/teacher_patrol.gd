class_name TeacherPatrol
extends RefCounted
## 非社交节点；状态和没收账本不进入任何关系矩阵。

var params: Dictionary = {}
var present := false
var visited := false
var leave_tick := -1
var confiscated: Array = []
var exemption_tokens: Array = []
var exempt_this_visit: Array = []


func configure(config: Dictionary, count: int) -> void:
	params = config
	confiscated.resize(count)
	confiscated.fill(0)
	exemption_tokens.resize(count)
	exemption_tokens.fill(0)
	exempt_this_visit.resize(count)
	exempt_this_visit.fill(false)


func begin_phase(c: SimCore) -> void:
	present = c._phase == "class"
	visited = false
	leave_tick = -1
	exempt_this_visit.fill(false)


func step(c: SimCore) -> void:
	if c._phase != "break":
		return
	if present and c._global_tick >= leave_tick:
		present = false
		c._emit("event_happened", {"kind": "teacher_left"})
	var tick: int = c._tick_in_phase + 1
	if visited or tick not in [int(params["visit_check_first"]), int(params["visit_check_second"])]:
		return
	if c._rng.random() >= float(params["visit_p"]):
		return
	visited = true
	present = true
	leave_tick = c._global_tick + int(params["stay_ticks"])
	c._emit("event_happened", {"kind": "teacher_arrived"})
	for i in range(c._n):
		if not c.is_present(i) or c._sleeping[i] or c._current_act[i] == "study":
			continue
		c._apply_event(i, i, "teacher_visit_stress")
		if c._busy_act[i] in ["listen_music", "eat_snack"]:
			c._emit("event_happened", {"kind": "teacher_caught", "i": i})
		catch_reader(c, i)


func catch_reader(c: SimCore, i: int) -> bool:
	if not present or c._phase != "break" or not c.is_present(i) or c._sleeping[i]:
		return false
	if c._busy_act[i] != "read_book" or c._book[i] <= 0 or exempt_this_visit[i]:
		return false
	if exemption_tokens[i] > 0:
		exemption_tokens[i] -= 1
		exempt_this_visit[i] = true
		c._emit("event_happened", {"kind": "book_confiscation_exempted", "i": i})
		return false
	var amount := mini(int(params["confiscate_books_per_catch"]), int(c._book[i]))
	c._book[i] -= amount
	confiscated[i] += amount
	# 没收独立于铃声打断，不发自然完成奖励或叠加铃声中断压力。
	c._current_act[i] = null
	c._busy_act[i] = null
	c._busy_phase[i] = -1
	c._busy_until[i] = c._global_tick
	c._in_conversation[i] = false
	c._stats["book_confiscations"] = int(c._stats.get("book_confiscations", 0)) + amount
	c._emit(
		"event_happened",
		{"kind": "book_confiscated", "i": i, "amount": amount,
		 "books": c._book[i], "confiscated_books": confiscated[i]}
	)
	return true


func multiplier(kind: String) -> float:
	if present and kind in ["tease", "roughhouse", "exclude"]:
		return float(params["suppress_behavior_mult"])
	return 1.0


func snapshot() -> Dictionary:
	return {"present": present, "visited": visited, "leave_tick": leave_tick}
