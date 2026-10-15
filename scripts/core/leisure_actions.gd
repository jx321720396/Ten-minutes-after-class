class_name LeisureActions
extends RefCounted
## P0-3 无持久引用的状态动作：所有状态与 RNG 仍归 SimCore 所有。


static func start_leisure(c: SimCore, i: int, kind: String) -> bool:
	if not SimCore.LEISURE_KINDS.has(kind) or not c._allowed(kind) or not c._can_interact_with(i):
		return false
	if kind == "read_book" and c._book[i] <= 0:
		return false
	if c.is_player(i) and kind == "eat_snack":
		if c._snacks_remaining <= 0:
			return false
		c._snacks_remaining -= 1
	c._occupy(i, i, kind)
	c._stats[kind] = int(c._stats.get(kind, 0)) + 1
	if kind == "read_book":
		c._teacher.catch_reader(c, i)
	return true


static func leave_class(c: SimCore) -> void:
	c._term_record.end_state("study")
	c._term_record.begin_state("leave_class")
	var me := c._n - 1
	for j in c._neighbor_idx[me]:
		c._apply_event(j, me, "leave_absence")
	c._leave_count += 1
	c._player_absent = true
	c._current_act[me] = "leave_class"
	var snap := c.time_snapshot()
	c._busy_until[me] = c._global_tick + int(snap["tick_count"]) - int(snap["tick_in_phase"])
	c._player_invitations.expire()


static func class_affinity_settle(c: SimCore) -> void:
	for i in range(c._n):
		if c._sleeping[i] or not c.is_present(i):
			continue
		for j in c._neighbor_idx[i]:
			if not c._sleeping[j] and c.is_present(j):
				c._a[i * c._n + j] = c._clamp100(
					c._a[i * c._n + j] + float(c._p["class_affinity_gain"])
				)
	c._term_record.capture(c, "class_affinity")


static func action_error(c: SimCore, kind: String, me: int) -> String:
	# 自指行为（学习 / 睡觉）：不看对象，只看自己能不能做
	if c._sleeping[me] or c._global_tick < c._busy_until[me] or c.is_moving(me):
		return "player_busy"
	if not c._allowed(kind):
		return "phase_not_allowed"
	if kind == "study" and not c.in_own_seat(me):
		return "not_in_seat"
	if kind == "read_book" and c._book[me] <= 0:
		return "no_book"
	if kind == "eat_snack" and c._snacks_remaining <= 0:
		return "no_snacks"
	if kind == "leave_class" and c._leave_count >= int(c._absence["max_per_break"]):
		return "absence_limit"
	return ""


static func select_roster(pool: Array, npc_count: int, leisure: Dictionary) -> Array:
	var selected: Array = []
	# 持书配额是单值（rules/leisure.csv 的 book_count）；不得超过本局人数，否则下面会选出超过 npc_count 的人
	var book_count := mini(int(leisure.get("book_count", 0)), npc_count)
	var with_books: Array = []
	var without_books: Array = []
	for ch in pool:
		if str(ch["book"]) == "1" and with_books.size() < book_count:
			with_books.append(ch)
		elif str(ch["book"]) == "0" and without_books.size() < npc_count - book_count:
			without_books.append(ch)
	for ch in pool:
		if with_books.has(ch) or without_books.has(ch):
			selected.append(ch)
	return selected
