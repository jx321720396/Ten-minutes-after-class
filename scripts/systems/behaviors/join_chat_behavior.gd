extends RefCounted
## join_chat：加入既有闲聊的判定与结算。两种调用形态共用同一套事件系数：
##
##   · **旧路径**（NPC 决策 / 玩家兼容别名）：`i` 请求 `j`，通过则执行一次双人闲聊；
##   · **群聊编排**（玩家加入，计划 §4.3）：options.mode = "group" 时按**一场活动**处理 ——
##     一次判定、新边各结算一次、全体占用与结束点对齐、拒绝不占用请求者。
##
## 为什么不让两种形态走同一段代码：旧路径的随机数、事件顺序与通知是既有基线，
## 动了它就是动了数值；玩家群聊是**行为新增**，单独成段并另做用例与基线记录。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")
const GROUP_MODE := "group"


func execute(context: Context, i: int, j: int, options: Dictionary = {}) -> void:
	if not context.can_chat_in_space(i, j):
		return
	if str(options.get("mode", "")) == GROUP_MODE:
		for member in _members(options, i):
			if not context.can_chat_in_space(i, int(member)):
				return
		_execute_group(context, i, j, options)
		return
	var roll: float = float(options.get("roll", -1.0))
	context.set_in_conversation(i, true)
	context.set_in_conversation(j, true)
	context.occupy(i, j, "join_chat", true)
	var p := context.join_probability(i, j)
	var choice: Variant = context.player_choice(i)
	if choice != null:
		p = 1.0 if bool(choice) else 0.0
		roll = 0.0
	elif roll < 0.0:
		roll = context.random()
	if roll < p:
		context.execute_behavior(&"chat", i, j)
		context.increment_stat("joins")
		context.increment_stat("join_accepts")
	else:
		context.apply_event(i, j, "reject_affinity")
		context.apply_event(i, j, "reject_hostility")
		context.apply_event(i, j, "reject_stress")
		context.observe(i, j, "affinity")
		context.increment_stat("joins")
		context.increment_stat("join_rejects")
		context.increment_stat("skipped_events")
	context.emit_event(
		"event_happened", {"kind": "join_chat", "i": i, "j": j, "accepted": roll < p}
	)


# ------------------------------------------------------------------ 群聊编排（玩家加入既有聊天）
## 一次判定（roll 由调用方预先掷出一次：一次合法加入只有一次接受判定）。
func _execute_group(context: Context, i: int, j: int, options: Dictionary) -> void:
	var session_id := int(options.get("session_id", -1))
	var members := _members(options, i)
	var roll: float = float(options.get("roll", -1.0))
	var p := context.join_probability(i, j)
	var choice: Variant = context.player_choice(i)
	if choice != null:
		p = 1.0 if bool(choice) else 0.0
		roll = 0.0
	elif roll < 0.0:
		roll = context.random()
	var accepted := roll < p
	context.set_in_conversation(i, true)
	for m in members:
		context.set_in_conversation(int(m), true)
	if accepted:
		_accept(context, i, j, session_id, members)
	else:
		_reject(context, i, j, members)
	context.increment_stat("joins")
	context.increment_stat("join_accepts" if accepted else "join_rejects")
	if not accepted:
		context.increment_stat("skipped_events")
	# 表现层只收到一个加入结果：不因多条关系边弹多次反馈
	(
		context
		. emit_event(
			"event_happened",
			{
				"kind": "chat",
				"i": i,
				"j": j,
				"mode": "join",
				"accepted": accepted,
				"session_id": session_id,
			}
		)
	)


## 接受：玩家与**每位原成员**各建立一条新聊天关系边（旧边不重算）；原成员之间不重算。
## 统一结束点 = max(原 end_tick, 当前 tick + chat.duration)，全体占用与之一致。
func _accept(context: Context, i: int, j: int, session_id: int, members: Array) -> void:
	for m in members:
		var other := int(m)
		context.apply_event(i, other, "topic_affinity")
		context.apply_event(i, other, "topic_trust")
		context.apply_event(other, i, "topic_affinity")
		context.apply_event(other, i, "topic_trust")
		context.observe(i, other, "affinity")
		context.observe(other, i, "affinity")
		context.increment_stat("chats")
	# 减压仍是「发起者单方」：玩家只减一次，不因群聊人数重复减
	context.apply_event(i, j, "topic_stress")
	var until := maxi(
		context.session_end_tick(session_id), context.global_tick() + context.duration_of("chat")
	)
	var all_members: Array = members.duplicate()
	all_members.append(i)
	all_members.sort()
	context.occupy_members(all_members, "chat", until, _sound_source(context, members, j), i)
	# 把玩家真正并入原会话（同一场活动只登记一次；结束点只后延不缩短）
	context.session_begin_or_join("chat", all_members, until)


## 拒绝：不占用请求者——加入失败不是物理活动，不应阻止玩家移动或发起新交互。
## 敌对反馈对**各原成员**分别执行（§10.7：A 对闲聊成员敌对值增加）。
func _reject(context: Context, i: int, j: int, members: Array) -> void:
	context.apply_event(i, j, "reject_affinity")
	for m in members:
		context.apply_event(i, int(m), "reject_hostility")
	context.apply_event(i, j, "reject_stress")
	context.observe(i, j, "affinity")


## 可加入的原成员（升序，不含请求者自己）。
func _members(options: Dictionary, self_id: int) -> Array:
	var out: Array = []
	var raw: Variant = options.get("members", [])
	if raw is Array:
		for m in raw:
			var idx := int(m)
			if idx >= 0 and idx != self_id and not out.has(idx):
				out.append(idx)
	out.sort()
	return out


## 音量按「场」计：沿用本场对话**已有的声源**，加入者不额外增加声源。
func _sound_source(context: Context, members: Array, fallback: int) -> int:
	for m in members:
		if str(context.current_act_of(int(m))) == "chat":
			return int(m)
	return fallback
