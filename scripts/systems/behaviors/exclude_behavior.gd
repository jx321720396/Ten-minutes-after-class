extends RefCounted
## exclude：由 SimCore 兼容入口调用，共用本局结算服务。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")


func execute(context: Context, i: int, j: int, options: Dictionary = {}) -> void:
	var crowd: Array = options.get("crowd", [])
	context.occupy(i, j, "exclude")
	context.apply_event(j, i, "exclude_stress")
	context.apply_event(j, i, "exclude_affinity")
	for k in crowd:
		if k != i:
			context.apply_event(j, k, "exclude_affinity")
	context.apply_event(i, j, "exclude_affinity")
	for k in crowd:
		if k != i:
			context.apply_event(k, j, "exclude_affinity")
	context.increment_stat("excludes")
	context.emit_event("event_happened", {"kind": "exclude", "i": i, "j": j})
