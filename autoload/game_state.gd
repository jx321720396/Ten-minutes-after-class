extends Node
## GameState 单例：当前局状态持有与推进入口（§4.1/§4.4）。
##
## 只持有会话标识与内核实例槽，不承载玩法规则；推进逻辑在 SimCore（D8 落地）。

var seed: int = 0
var difficulty: int = 0
var day: int = 0
var phase: String = ""
## SimCore 实例（D8 落地后赋值）；用 Variant 避免提前锁定类型。
var sim_core: Variant = null


func start_game(new_seed: int, new_difficulty: int) -> void:
	seed = new_seed
	difficulty = new_difficulty
	day = 0
	phase = ""
	sim_core = null
	# TODO(D8): sim_core = SimCore.new(seed, difficulty)


func end_game() -> void:
	sim_core = null


## 把内核事件出口绑到 EventBus 四信号（D11 缺口④）。
## 内核零 autoload 依赖：这里由表现层（GameState）完成「内核事件 → 全局信号」的路由。
func wire_events(core: Variant) -> void:
	if core == null:
		return
	core.event_sink = func(e: Dictionary) -> void:
		match e["type"]:
			"event_happened":
				EventBus.event_happened.emit(e["payload"])
			"day_settled":
				EventBus.day_settled.emit(e["payload"])
			"tag_changed":
				EventBus.tag_changed.emit(e["payload"]["id"], e["payload"]["tag"])
			"stress_burst":
				EventBus.stress_burst.emit(e["payload"]["i"])


func is_running() -> bool:
	return sim_core != null
