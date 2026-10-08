extends RefCounted
## chat：由 SimCore 兼容入口调用，共用本局结算服务。
##
## 真实会话成立挂点（计划 §5.1）：闲聊一旦真的开始，就在这里登记**一场共同活动**
## （`begin_or_join`）—— 同一场闲聊只登记一次，已有会话则并入而不是另开一场。
## 该登记不消费随机数、不改任何矩阵，只让底部圈与「能不能加入」有真实成员来源。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")


func execute(context: Context, i: int, j: int, _options: Dictionary = {}) -> void:
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
