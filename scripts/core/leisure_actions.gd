class_name LeisureActions
extends RefCounted
## P0-3 无持久引用的状态动作：所有状态与 RNG 仍归 SimCore 所有。


static func start_leisure(c: SimCore, i: int, kind: String) -> bool:
	if not SimCore.LEISURE_KINDS.has(kind) or not c._allowed(kind) or not c._can_interact_with(i):
		return false
	if kind == "read_book" and c._book[i] <= 0:
		return false
	c._occupy(i, i, kind)
	c._stats[kind] = int(c._stats.get(kind, 0)) + 1
	if kind == "read_book":
		c._teacher.catch_reader(c, i)
	return true


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
