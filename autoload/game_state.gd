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
## 期末「再玩一局」交回主菜单直接开新局（不弹选角色）。
var new_game_requested := false
## 设置菜单「重看教程」请求（2026-10-13）：主菜单开新局时并入 tutorial_pending，消费后清零。
var replay_tutorial := false
## 本次进教室是否要弹新手教程（由入口决定：主菜单开新局置位，教室消费后清零）。
## 教室自身不读「已看」文件——直接实例化教室（测试 / 调试）永远零教程、零冻结。
var tutorial_pending := false
## 主菜单开幕是否已经显示过「第 N 天」黑幕（教室进场消费一次，避免重复盖卡片）。
var opening_day_shown := false
## 教室场景注入的时钟引用（存档 / 读档用；SimulationClock 是场景节点，不在 autoload 里）。
var clock: Variant = null
## 读档暂存的时钟状态：教室 bind_core 后应用（时钟须先绑内核才能 restore）。
var pending_clock_state: Dictionary = {}
## 读档落在课间时置位：教室绑定 Roam 后立即强制一批离座决策（跳过「第 N 天」归位停留）。
## 否则读档被 Roam 当成一天之始（表现层 `_last_snapped_day` 不存档、恒为 -1），首批离座会被
## 0.7 秒停留顺延。由 load_game 置位、教室消费后清零（与 pending_clock_state 同一套 pending 约定）。
var force_roam_decide := false


func start_game(new_seed: int, new_npc_count: int) -> void:
	profile_notebook = {"current": {}, "history": [], "seen": {}}
	force_roam_decide = false
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


## 打包本局快照并写盘（单槽 user://savegame.dat）。日末自动存档与暂停菜单手动存档共用。
## 返回是否写入成功（false = 无内核实例或磁盘写入失败）。
func save_snapshot() -> bool:
	if sim_core == null:
		push_warning("GameState：没有本局内核，无法存档。")
		return false
	var core_state: Dictionary = SimCoreSerializer.export_state(sim_core)
	var payload := {
		"config_fingerprint": str(core_state.get("config_fingerprint", "")),
		"seed": seed,
		"n": npc_count,
		"day": day,
		"core": core_state,
		"clock": clock.save_state() if clock != null else {},
		"journal":
		{
			"profile_notebook": profile_notebook,
		},
	}
	return Save.save(payload)


## 日末简报边界自动存档（此时 mode=report，正是时钟可安全恢复的边界）。
func auto_save() -> void:
	save_snapshot()


## 从存档 data 恢复本局：校验配置指纹 → 重建内核并覆盖运行时态 → 回填会话字段。
## 返回 true 表示内核已就绪（可切教室）；false = 数据表已变 / 存档损坏 / seed 人数非法。
func load_game(data: Dictionary) -> bool:
	if data.is_empty():
		push_warning("GameState：存档为空，无法恢复。")
		return false
	var tables := ConfigLoader.new().load_all()
	var saved_fp := str(data.get("config_fingerprint", ""))
	if saved_fp == "" or saved_fp != SimCoreSerializer.config_fingerprint(tables):
		push_warning("GameState：存档配置指纹与当前数据表不一致，拒绝恢复。")
		return false
	var s := int(data.get("seed", 0))
	var n := int(data.get("n", 0))
	if n <= 0:
		push_warning("GameState：存档人数非法，拒绝恢复。")
		return false
	var core: Variant = SimCore.new(s, n, tables)
	if core == null or not SimCoreSerializer.restore_state(core, data.get("core", {})):
		push_warning("GameState：内核恢复失败（版本 / 指纹 / seed 不符）。")
		return false
	seed = s
	npc_count = n
	day = int(data.get("day", 0))
	sim_core = core
	wire_events(core)
	profile_notebook = data.get("journal", {}).get("profile_notebook", profile_notebook)
	pending_clock_state = data.get("clock", {})
	force_roam_decide = false
	# 读档落在「课间」（running 模式 + break）时：① 把课间拨回段首（tick 与时钟累计归零），
	# 玩家重新得到一个完整课间；② 置位强制离座判定，让教室绑定 Roam 后立即跑一批走动决策，
	# 而不是被当成一天之始、首批离座被 0.7 秒停留顺延。段首判定（睡眠 / 学习状态等）保留
	# 存档值、不重跑 _begin_phase —— 读档只重置课间计时，不改变已保存的世界。
	if str(pending_clock_state.get("mode", "")) == "running":
		var snap: Dictionary = core.time_snapshot()
		if str(snap.get("kind", "")) == "break":
			force_roam_decide = true
			if int(snap.get("tick_in_phase", 0)) > 0:
				core._tick_in_phase = 0
				pending_clock_state["accumulator"] = 0.0
	return true
