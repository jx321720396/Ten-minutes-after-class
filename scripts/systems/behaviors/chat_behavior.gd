extends RefCounted
## chat：闲聊（主行为）—— **发起新聊天**与**加入已有聊天**是同一个行为的两种参与方式。
##
## 依据：主文档 §8.5（闲聊）、§8.7（加入闲聊，原「搭话」）、§8.21（「加入」是通用参与操作）。
## **2026-10-10 合并**：原独立行为 `join_chat` 已并入本组件（行为表、阈值键、事件卡同步合并），
## 不再有独立的 `join_chat` 标识；**数值、耗时与事件系数一律未动**（同种子逐 tick 对拍不变）。
##
## 三条路径（共用同一套事件系数与数据）：
##   · **发起**（默认）：i 与 j 聊一场；真实会话登记走 `begin_or_join` —— 同一场闲聊只登记一次，
##     已有会话则并入而不是另开一场（该登记不消耗随机数、不改矩阵，只让底部圈与「能不能加入」
##     有真实成员来源）；
##   · **加入**（`options.mode = "join"`）：i 请求 j，通过则并入原会话（`roll` 可由调用方预掷，
##     保证三拍展示一致）；被拒走 `reject_*` 三轴反噬，且**不占用请求者**；
##   · **群聊编排**（`options.mode = "group"`，玩家加入既有闲聊）：按**一场活动**处理 ——
##     一次判定、新边各结算一次、全体占用与结束点对齐、拒绝不占用请求者。
##
## 为什么三条路径不写成一段：发起 / 加入 / 群聊的**随机数顺序、事件顺序与通知**都是既有基线，
## 动它就是动数值（硬闸门：Python 与 GDScript 同种子逐 tick 对拍）。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")
const MODE_START := "start"
const MODE_JOIN := "join"
const MODE_GROUP := "group"


func execute(context: Context, i: int, j: int, options: Dictionary = {}) -> void:
	match str(options.get("mode", MODE_START)):
		MODE_GROUP:
			if not _group_space_ready(context, i, options):
				return
			_execute_group(context, i, j, options)
		MODE_JOIN:
			_execute_join(context, i, j, options)
		_:
			_execute_start(context, i, j)


# ------------------------------------------------------------------ 发起新聊天
## 发起：双向好感 / 信任、发起者压力 −，并登记真实会话。
func _execute_start(context: Context, i: int, j: int) -> void:
	if not context.can_chat_in_space(i, j):
		return
	context.set_in_conversation(i, true)
	context.set_in_conversation(j, true)
	context.occupy(i, j, "chat", true)
	context.apply_event(i, j, "topic_affinity")
	context.apply_event(i, j, "topic_trust")
	context.apply_event(i, j, "topic_stress")
	context.apply_event(j, i, "topic_affinity")
	context.apply_event(j, i, "topic_trust")
	context.observe(i, j, "affinity")
	context.observe(j, i, "affinity")
	context.increment_stat("chats")
	# 真实成立点：结束点取双方占用里更晚的那个（占用时长是累积的，不是覆盖的）
	var until := maxi(context.busy_until_of(i), context.busy_until_of(j))
	context.session_begin_or_join("chat", [i, j], until)
	context.emit_event("event_happened", {"kind": "chat", "i": i, "j": j})


# ------------------------------------------------------------------ 加入既有聊天（原 join_chat）
## 加入：**只有一次接受判定**（`roll` 由调用方预掷时不再掷）；通过则委托发起路径并入原会话。
## 被拒不占用请求者 —— 加入失败不是物理活动，不该阻止他移动或发起别的交互。
func _execute_join(context: Context, i: int, j: int, options: Dictionary) -> void:
	if not context.can_chat_in_space(i, j):
		return
	var roll: float = float(options.get("roll", -1.0))
	context.set_in_conversation(i, true)
	context.set_in_conversation(j, true)
	context.occupy(i, j, "chat", true)
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
		"event_happened", {"kind": "chat", "i": i, "j": j, "mode": MODE_JOIN, "accepted": roll < p}
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
				"mode": MODE_JOIN,
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


## 群聊编排的前置：请求者与**全体原成员**都得在聊天范围内。
func _group_space_ready(context: Context, i: int, options: Dictionary) -> bool:
	for member in _members(options, i):
		if not context.can_chat_in_space(i, int(member)):
			return false
	return true


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
