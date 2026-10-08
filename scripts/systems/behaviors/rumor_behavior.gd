extends RefCounted
## rumor：由 SimCore 兼容入口调用，共用本局结算服务。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")


func execute(context: Context, i: int, j: int, _options: Dictionary = {}) -> void:
	var negative := context.hostility(i, j) > context.affinity(i, j)
	context.apply_event(j, i, "rumor_hostility")
	if negative:
		context.apply_event(i, j, "rumor_stress")
		context.apply_event(i, j, "tease_hostility")
	for k in range(context.node_count()):
		if k != i and k != j:
			context.observe(k, j, "hostility")
	context.increment_stat("rumors")
	context.emit_event("event_happened", {"kind": "rumor", "i": i, "j": j})
