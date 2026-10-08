extends RefCounted
## tease：由 SimCore 兼容入口调用，共用本局结算服务。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")


func execute(context: Context, i: int, j: int, options: Dictionary = {}) -> void:
	var audience: Array = options.get("audience", [])
	context.occupy(i, j, "tease")
	if (
		context.affinity(i, j) >= context.threshold("tease_laugh_affinity")
		and context.hostility(i, j) < context.threshold("tease_laugh_hostility")
	):
		context.apply_event(i, j, "tease_success_affinity")
		context.apply_event(j, i, "tease_success_affinity")
		for k in audience:
			context.apply_event(k, j, "tease_success_affinity")
		context.apply_event(j, i, "tease_laugh_stress")
	elif (
		context.hostility(i, j) >= context.threshold("tease_taunt_hostility")
		or context.affinity(i, j) < context.threshold("tease_taunt_affinity")
	):
		context.apply_event(j, i, "tease_hostility")
		context.apply_event(j, i, "tease_stress")
		for k in audience:
			if context.affinity(k, j) >= context.threshold("tease_stand_affinity"):
				context.apply_event(k, i, "tease_hostility")
			elif context.hostility(k, j) >= context.threshold("tease_sneer_hostility"):
				context.apply_event(k, j, "tease_affinity")
		if audience.size() >= int(context.threshold("humiliate_bystanders")):
			context.apply_event(j, i, "humiliate_hostility")
			context.mark_hurt(i, j)
			context.increment_stat("humiliations")
		context.increment_stat("tease_fail")
	context.increment_stat("teases")
	context.emit_event("event_happened", {"kind": "tease", "i": i, "j": j})
