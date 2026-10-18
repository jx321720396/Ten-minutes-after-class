class_name LeisureActions
extends RefCounted
## P0-3 无持久引用的状态动作：所有状态与 RNG 仍归 SimCore 所有。


static func start_leisure(c: SimCore, i: int, kind: String, ignore_book: bool = false) -> bool:
	if not SimCore.LEISURE_KINDS.has(kind) or not c._allowed(kind) or not c._can_interact_with(i):
		return false
	# 共享娱乐（2026-10-19）：加入者无需自带书 —— 一起看同一本。
	if kind == "read_book" and not ignore_book and c._book[i] <= 0:
		return false
	c._occupy(i, i, kind)
	c._stats[kind] = int(c._stats.get(kind, 0)) + 1
	if kind == "read_book":
		c._teacher.catch_reader(c, i)
	return true


## 课间活动效果表（rules/leisure_effects.csv，2026-10-18）：每种娱乐有自己的减压率与附加收益。
static func build_effects(tables: Dictionary) -> Dictionary:
	var out := {}
	for row in tables.get("rules/leisure_effects", {}).get("rows", []):
		var key := str(row.get("behavior", "")).strip_edges()
		if key.is_empty():
			continue
		out[key] = {
			"stress_per_unit": float(str(row.get("stress_per_unit", "0"))),
			"grade_once": float(str(row.get("grade_once", "0"))),
			"vitality_once": float(str(row.get("vitality_once", "0"))),
		}
	return out


## 某活动每 10 秒的压力率（效果表缺失时回落到旧的统一 relief_per_unit）。
static func stress_per_unit(c: SimCore, behavior: String) -> float:
	var effect: Dictionary = c._leisure_effects.get(behavior, {})
	if effect.is_empty():
		return -float(c._acts["relief_per_unit"])
	return float(effect.get("stress_per_unit", 0.0))


## 活动自然完成时的一次性附加效果（学业／动力）。
static func apply_finished_bonus(c: SimCore, i: int) -> void:
	var act := str(c._busy_act[i])
	if act.is_empty() or act == "sleep":
		return
	var effect: Dictionary = c._leisure_effects.get(act, {})
	if effect.is_empty():
		return
	var grade := float(effect.get("grade_once", 0.0))
	if grade != 0.0:
		c._gain_today[i] += grade
	var vitality := float(effect.get("vitality_once", 0.0))
	if vitality != 0.0:
		c.add_vitality(i, vitality)


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
