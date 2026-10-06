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


func is_running() -> bool:
	return sim_core != null
