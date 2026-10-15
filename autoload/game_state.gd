extends Node
## GameState 单例：当前局状态持有与推进入口（§4.1/§4.4）。
##
## 只持有会话标识与内核实例槽，不承载玩法规则；推进逻辑在 SimCore（D8 落地）。

var seed: int = 0
## 本局入局 NPC 数（玩家另算）；2026-10-12 起由 data/rules/roster.csv 给定（一局 16）
var npc_count: int = 0
var day: int = 0
var phase: String = ""
## SimCore 实例（D8 落地后赋值）；用 Variant 避免提前锁定类型。
## 玩家性别（"male" / "female"）：学生版运行时残留，立绘/表情仍按它取图；
## 老师版已删除选角色界面，不再有入口改写，固定默认 "male"，不写存档。
var player_gender: String = "male"

var sim_core: Variant = null
## 本局观察笔记；与真实关系矩阵隔离，供存档层独立打包。
var profile_notebook: Dictionary = {"current": {}, "history": [], "seen": {}}
## 本局按日观察归档，不属于学生关系矩阵；新局重置。
var clue_board_journal: Dictionary = {"days": {}, "sealed": {}}
## 期末「再玩一局」交回主菜单直接开新局（不弹选角色）。
var new_game_requested := false
## 设置菜单「重看教程」请求（2026-10-13）：主菜单开新局时并入 tutorial_pending，消费后清零。
var replay_tutorial := false
## 本次进教室是否要弹新手教程（由入口决定：主菜单开新局置位，教室消费后清零）。
## 教室自身不读「已看」文件——直接实例化教室（测试 / 调试）永远零教程、零冻结。
var tutorial_pending := false


func start_game(new_seed: int, new_npc_count: int) -> void:
	clue_board_journal = {"days": {}, "sealed": {}}
	profile_notebook = {"current": {}, "history": [], "seen": {}}
	seed = new_seed
	npc_count = new_npc_count
	day = 0
	phase = ""
	# §4.1 契约：SimCore.new(seed, npc_count)（2026-10-12 起不再有难度档映射）。
	sim_core = SimCore.new(seed, npc_count)
	if sim_core != null:
		wire_events(sim_core)


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


## 时间镜像：day / phase 由表现层时钟从内核快照统一同步（**不独立自增**，避免与内核真值漂移）。
## 参数是 SimulationClock.snapshot() 的返回值。
func sync_time(snapshot: Dictionary) -> void:
	day = int(snapshot.get("day", day))
	phase = str(snapshot.get("kind", phase))
