extends RefCounted
## ask_help：由 SimCore 兼容入口调用，共用本局结算服务。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")


func execute(context: Context, i: int, j: int, _options: Dictionary = {}) -> void:
	context.occupy(i, j, "ask_help")
	context.apply_event(i, j, "ask_help_cost_stress")
	var score := (
		context.affinity(j, i)
		+ context.dimension(j, 0) / 100.0 * context.threshold("ask_help_extrovert_bonus")
	)
	var p := context.sigmoid(
		(
			(score - context.threshold("ask_help_accept_theta"))
			/ context.threshold("ask_help_accept_scale")
		)
	)
	var accepted := context.random() < p
	if accepted:
		context.apply_event(i, j, "ask_help_ok_asker_affinity")
		context.apply_event(i, j, "ask_help_ok_asker_stress")
		context.apply_event(j, i, "ask_help_ok_helper_affinity")
		context.apply_event(j, i, "ask_help_ok_helper_trust")
		context.increment_stat("helps")
	else:
		context.apply_event(i, j, "ask_help_no_stress")
		context.apply_event(i, j, "ask_help_no_hostility")
		context.apply_event(i, j, "ask_help_no_trust")
		context.increment_stat("help_rejects")
	context.emit_event("event_happened", {"kind": "ask_help", "i": i, "j": j, "accepted": accepted})
