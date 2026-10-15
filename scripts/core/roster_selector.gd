class_name RosterSelector
extends RefCounted
## 本局角色抽取（主文档 §11.5 的「正式版」——替换参考实现里的随机抽人 TODO）。
##
## 老师版（2026-10-14）：删除 MBTI 四维极性覆盖，只保留绑定组成员强制纳入；
##   剩余席位按 seeds 表行序补齐（不消费随机数，同名单跨种子稳定）。
##   本类当前未被内核装配路径引用（内核走 LeisureActions.select_roster），保留供后续接入。


## 返回选中的角色行（Array[Dictionary]），顺序 = 绑定组成员（按绑定表行序）+ 行序补齐。
func select(seeds: Array, bindings: Array, target: int, _neutral: float) -> Array:
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

	# ② 剩余席位按 seeds 表行序补齐
	for row in seeds:
		if selected.size() >= target:
			break
		var alias := str(row["alias"])
		if chosen.has(alias):
			continue
		selected.append(row)
		chosen[alias] = true

	return selected
