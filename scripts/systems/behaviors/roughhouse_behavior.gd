extends RefCounted
## roughhouse：由 SimCore 兼容入口调用，共用本局结算服务。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")


func execute(context: Context, i: int, j: int, options: Dictionary = {}) -> void:
	var bystanders: Array = options.get("bystanders", [])
	context.occupy(i, j, "roughhouse")
	context.apply_event(i, j, "roughhouse_affinity")
	context.apply_event(j, i, "roughhouse_affinity")
	for k in bystanders:
		context.apply_event(k, i, "roughhouse_hostility")
		context.apply_event(k, j, "roughhouse_hostility")
	context.increment_stat("roughhouse")
	context.emit_event("event_happened", {"kind": "roughhouse", "i": i, "j": j})
