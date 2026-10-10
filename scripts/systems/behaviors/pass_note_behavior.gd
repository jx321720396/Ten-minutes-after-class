extends RefCounted
## pass_note（§8.6 纸条链，2026-10-10）：写纸条 + 拿到纸条后的处理。
##
## 分工（与 chat_behavior 同构）：**本组件只做行为逻辑**；纸条的状态（活跃纸条、
## 持有者、已经手集合）由内核持有，组件通过 `BehaviorContext` 读写。
##
## Python 参考实现：`tools/core_sim.py` 的 `do_pass_note` / `settle_note` /
## `pick_note_target` / `process_notes` —— **两套内核必须同种子逐位一致**，
## 因此这里的随机数调用顺序与次数与参考实现严格对齐（见各函数注释里的「消耗 RNG」）。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")
## 话术模板数（`X 喜欢 Y` / `X 讨厌 Y` / `X 很好` / `X 很坏`，§8.6 第 1 条）。
const TEMPLATE_COUNT := 4
## 「被说者 X」的权重分母：`w(X) ∝ 1 + |A − H| / 50`（§8.6 第 1 条）。
const WEIGHT_SCALE := 50.0


## 写纸条（§8.6）：i 写一张纸条投给 j（座位相邻或已走近的人）。
##
## - 被说者 X：态度越极端（无论好坏）越可能被写进去
## - 话术：i 对 X 的净态度决定好话 / 坏话；模板随机
## - **纸条到达不占用接收者**（硬规则）—— 只占写纸条的人自己的时间；
##   接收者的「看不看 / 销毁 / 继续传」在 `handle_receipt` 里处理。
## 消耗 RNG：choices（挑 X）+ random（挑模板）= 2 次。
func execute(context: Context, i: int, j: int, _options: Dictionary = {}) -> void:
	var n := context.node_count()
	var cands: Array = []
	var weights: Array = []
	for k in range(n):
		if k == i:
			continue
		cands.append(k)
		weights.append(1.0 + absf(context.affinity(i, k) - context.hostility(i, k)) / WEIGHT_SCALE)
	if cands.is_empty():
		return
	var target := context.weighted_pick(cands, weights)
	var tone := 1 if context.affinity(i, target) >= context.hostility(i, target) else -1
	var template := int(context.random() * float(TEMPLATE_COUNT))
	context.note_create(i, target, tone, template, j)
	context.occupy(i, i, "pass_note")
	context.increment_stat("notes_written")
	context.emit_event(
		"event_happened", {"kind": "pass_note", "i": i, "j": j, "target": target, "tone": tone}
	)


## 一次「拿到纸条」的完整处理（§8.6 第 2–3 条）：看不看 → 结算 → 去向（销毁 / 继续传）。
##
## - **不看**：不占用时间、不打断当前行为（接收者可能正在闲聊）
## - **看**：占 10 tick 并立即结算（只改「收件人对被说者 X」的态度）
## - 去向一律走 §4.5 的 `continue` 判定；走到头（没有下一个接收者）即销毁
## 消耗 RNG：random（看不看）+ random（继不继传）+ [继传时] randbelow（挑人）。
func handle_receipt(context: Context, note_id: int) -> bool:
	var note := context.note_row(note_id)
	if note.is_empty():
		return false
	var holder := int(note["holder"])
	var read_chance := context.choice_prob("pass_note", "read", holder)
	if context.random() < read_chance:
		settle(context, holder, int(note["target"]), int(note["tone"]))
		context.occupy(holder, holder, "pass_note")
		context.increment_stat("notes_read")
	var forward_chance := context.choice_prob("pass_note", "continue", holder)
	if context.random() < forward_chance:
		var next_holder := pick_next(context, holder, note["seen"])
		if next_holder >= 0:
			context.note_pass_on(note_id, holder, next_holder)
			context.occupy(holder, holder, "pass_note")
			return true
	context.note_destroy(note_id)
	context.increment_stat("notes_destroyed")
	return true


## 读纸条的结算（§8.6 第 4 条）：**只改变收件人对被说者 X 的态度**。
##
## 方向按收件人对 X 的现有态度（净态度 A − H）分档；每条效果 base = 1，
## 强度走统一影响公式。**不消耗 RNG。**
func settle(context: Context, holder: int, target: int, tone: int) -> void:
	var net := context.affinity(holder, target) - context.hostility(holder, target)
	var key := ""
	if net < 0.0:
		key = "note_bad_to_hostile" if tone < 0 else "note_good_to_hostile"
	else:
		key = "note_good_to_friendly" if tone > 0 else "note_bad_to_friendly"
	context.apply_event(holder, target, key)


## 挑下一个接收者（§8.6 第 3 条）：优先**座位相邻**且没拿过这张纸条的人；
## 没有相邻候选则退化为任意可交互的人（离线模型里近似「已走近」）。
##
## 无候选返回 -1（纸条走到头 → 销毁）。消耗 RNG：randbelow = 1 次。
func pick_next(context: Context, holder: int, seen: Array) -> int:
	var pool: Array = []
	for k in context.neighbors_of(holder):
		if k != holder and not seen.has(k) and context.can_interact_with(k):
			pool.append(k)
	if pool.is_empty():
		for k in range(context.node_count()):
			if k != holder and not seen.has(k) and context.can_interact_with(k):
				pool.append(k)
	if pool.is_empty():
		return -1
	return int(pool[context.rand_below(pool.size())])
