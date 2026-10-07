class_name RosterSelector
extends RefCounted
## 本局角色抽取（主文档 §11.5 的「正式版」——替换参考实现里的随机抽人 TODO）。
##
## 目标：从 24 名种子中抽出 `target` 人，满足
##   ① 强制纳入所有绑定组成员（couple / uniform，见 characters/bindings.csv）
##   ② 覆盖 MBTI 四维极性（E/N/F/P 各维的「高 / 低」两侧都至少有一人）
## 填充策略：贪心——每步挑「覆盖最多尚未覆盖极性槽」的人；同分按 id 升序取第一。
##
## 注意（D8 待定）：本类**不消费随机数**，故同一种子下名单固定、跨种子也不变。
## 这是当前的最简实现；是否要在「同分候选」里引入 RNG 打散以换取跨种子名单多样性，
## 需与策划确认，并与 tools/core_sim.py 同步（否则对拍名单不一致）。

const _DIMS := ["e", "n", "f", "p"]


## 返回选中的角色行（Array[Dictionary]），顺序 = 绑定组成员（按绑定表行序）+ 贪心补齐。
func select(seeds: Array, bindings: Array, target: int, neutral: float) -> Array:
	var by_alias := {}
	for row in seeds:
		by_alias[str(row["alias"])] = row

	# ① 绑定组成员（from 与 to 中出现的非 * 别名，按绑定表行序去重）
	var forced_aliases: Array = []
	for b in bindings:
		var f := str(b["from"])
		var t := str(b["to"])
		if f != "" and f != "*" and not forced_aliases.has(f):
			forced_aliases.append(f)
		if t != "" and t != "*" and not forced_aliases.has(t):
			forced_aliases.append(t)

	var selected: Array = []
	var chosen := {}
	for a in forced_aliases:
		var row = by_alias.get(a)
		if row != null:
			selected.append(row)
			chosen[a] = true

	# ② 极性覆盖 + 贪心补齐
	var covered := {}
	for row in selected:
		_mark(covered, row, neutral)

	while selected.size() < target:
		var best = null
		var best_new := -1
		for row in seeds:
			var alias := str(row["alias"])
			if chosen.has(alias):
				continue
			var new_slots := _new_slots(covered, row, neutral)
			if new_slots > best_new:
				best_new = new_slots
				best = row
		if best == null:
			break
		selected.append(best)
		chosen[str(best["alias"])] = true
		_mark(covered, best, neutral)

	return selected


func _slot_keys(row: Dictionary, neutral: float) -> Array:
	var keys: Array = []
	for d in _DIMS:
		var v := float(str(row.get(d, "")))
		if v > neutral:
			keys.append("%s_high" % d)
		elif v < neutral:
			keys.append("%s_low" % d)
		else:
			keys.append("")
	return keys


func _mark(covered: Dictionary, row: Dictionary, neutral: float) -> void:
	for k in _slot_keys(row, neutral):
		if k != "":
			covered[k] = true


func _new_slots(covered: Dictionary, row: Dictionary, neutral: float) -> int:
	var count := 0
	for k in _slot_keys(row, neutral):
		if k != "" and not covered.has(k):
			count += 1
	return count
