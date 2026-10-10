extends RefCounted
## observe（§10.3.1）：玩家独有的**只读**行为 —— 靠近对象读信息。
##
## 硬约束（零副作用）：不写任何矩阵、不产生成绩／好感／敌对／信任／压力变化、**不发出噪音**、
## **不占用也不能打断对象**（对象不知情）、不进 NPC 决策。
##
## 信息口径（§10.3.1 / §15.5.5）：读的是「**对象对玩家的**态度」——
##   · **真实信息** = 对象对玩家的 `A`（好感）与 `H`（敌对）；对象 `O ≥ 50` 时再多一条 `T`（信任）；
##   · **信念信息** = 对象以为玩家怎么看他（`B[对象][玩家]`，**可能是错的** —— 误差本身就是戏）。
## 睡觉对象没有社交动向 → 只给真实信息，不给信念信息。
##
## 本版只做**单人对象**；活动圈（群体）观察见 §10.3.1 的待办。

const Context = preload("res://scripts/systems/behaviors/behavior_context.gd")
## 「透明度高」档（与 §7.2 的分界一致）：多给一条真实信息
const OPAQUE_HIGH := 50


func execute(context: Context, i: int, j: int, _options: Dictionary = {}) -> void:
	# 只占玩家自己的时间槽；对象完全不知情、不被打断
	context.occupy(i, i, "observe")
	context.increment_stat("observes")
	context.emit_event(
		"event_happened",
		{
			"kind": "observe",
			"i": i,
			"j": j,
			"day": context.day(),
			"clues": build_clues(context, i, j)
		}
	)


## 观察读到的信息（只读，不改任何矩阵）。
func build_clues(context: Context, me: int, obj: int) -> Array:
	var out: Array = []
	out.append(_true_clue(context, obj, me, "affinity"))
	out.append(_true_clue(context, obj, me, "hostility"))
	if context.opacity(obj) >= OPAQUE_HIGH:
		out.append(_true_clue(context, obj, me, "trust"))
	if str(context.current_act_of(obj)) != "sleep":
		(
			out
			. append(
				{
					"source": obj,
					"subject": obj,
					"axis": "affinity",
					"value": context.belief_axis(obj, me, "affinity"),
					"day": context.day(),
					"via": "observe",
					"belief": true,
				}
			)
		)
	return out


func _true_clue(context: Context, obj: int, me: int, axis: String) -> Dictionary:
	var value := 0.0
	match axis:
		"affinity":
			value = context.affinity(obj, me)
		"hostility":
			value = context.hostility(obj, me)
		"trust":
			value = context.trust(obj, me)
	return {
		"source": obj,
		"subject": me,
		"axis": axis,
		"value": value,
		"day": context.day(),
		"via": "observe",
	}
