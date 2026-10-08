class_name PlayerChatIntel
extends RefCounted
## 玩家闲聊线索（内核侧）：**自然完成**的一次玩家闲聊，才读取当刻真值透露单轴信息。
##
## 依据：主文档 §10.5 第 5 条（玩家专属的关系透露：O < 50 透露 1 条、O ≥ 50 透露 2 条，
##      每条只属于本次情报、不写回关系矩阵）；
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §8.4。
##
## 三条硬约束：
##   ① **抽样走独立、有种子的随机流**（seed = 本局 seed）——不消费内核主随机流，
##      因此显示 / 隐藏 UI、跳过动画、改帧率都不会改变抽样结果；
##   ② **只拷贝被抽中的那一个轴**，且读取的是「自然完成这一刻」的真值；
##      历史卡片不跟着矩阵实时刷新（记录 ≠ 实时视图）；
##   ③ **不预设虚构对白**，也不把真值写回信念矩阵（当前信念结构也存不了第三人关系）。

## 单条线索只透露一个轴：好感 / 敌对 / 信任。
const AXES: Array[String] = ["affinity", "hostility", "trust"]

var _rng := RandomNumberGenerator.new()
## 历史日志（本局顺序，只增不改）
var _history: Array = []
var _next_clue_id := 1
## 呈现口径（来自 data/rules/player_interaction.csv，不落脚本魔法数字）
var _opacity_split := 50.0
var _count_low := 1
var _count_high := 2


func _init(seed: int) -> void:
	_rng.seed = seed


## 注入配置：透明度分界与两档条数。
func configure(params: Dictionary) -> void:
	_opacity_split = float(params.get("clue_opacity_split", _opacity_split))
	_count_low = int(params.get("clue_count_low", _count_low))
	_count_high = int(params.get("clue_count_high", _count_high))


func clear() -> void:
	_history = []
	_next_clue_id = 1


## 本局已获得的历史线索（深拷贝，不实时刷新旧值）。
func history() -> Array:
	var out: Array = []
	for clue in _history:
		out.append(clue.duplicate(true))
	return out


func clue_count() -> int:
	return _history.size()


## 应透露几条：由**闲聊对象当时的透明度**决定（与 §9.2 的透明度分界同一口径）。
func clue_count_for(opacity_value: float) -> int:
	return _count_high if opacity_value >= _opacity_split else _count_low


## 抽样：从候选对象里选（不重复）subject，并为每条独立抽一个轴。
## candidates 必须是**已经排好序**的角色索引（排除玩家与 source，由调用方保证）。
## 返回 [{"subject": int, "axis": String}]，长度即本次透露条数。
func draw_subjects(opacity_value: float, candidates: Array) -> Array:
	var out: Array = []
	var pool: Array = []
	for c in candidates:
		pool.append(int(c))
	if pool.is_empty():
		return out
	var want := clue_count_for(opacity_value)
	for _k in range(want):
		if pool.is_empty():
			break
		var pick := _rng.randi_range(0, pool.size() - 1)
		var subject := int(pool[pick])
		pool.remove_at(pick)
		var axis := AXES[_rng.randi_range(0, AXES.size() - 1)]
		out.append({"subject": subject, "axis": axis})
	return out


## 写入一条线索并返回完整记录（字段见计划 §8.4）。
## value 由调用方在「自然完成这一刻」从真值矩阵读出后传入 —— 本类不读矩阵。
## at = {"day": int, "phase_id": String, "global_tick": int}。
func record(
	request_id: int,
	session_id: int,
	source: int,
	subject: int,
	axis: String,
	value: float,
	at: Dictionary
) -> Dictionary:
	var clue := {
		"clue_id": _next_clue_id,
		"request_id": request_id,
		"session_id": session_id,
		"source": source,
		"subject": subject,
		"axis": axis,
		"value": snapped(value, 0.1),
		"day": int(at.get("day", 0)),
		"phase_id": str(at.get("phase_id", "")),
		"global_tick": int(at.get("global_tick", 0)),
	}
	_next_clue_id += 1
	_history.append(clue)
	return clue.duplicate(true)


## 同一 clue_id 只发一次（自然完成事件去重的兜底判定）。
func has_clue(clue_id: int) -> bool:
	for clue in _history:
		if int(clue["clue_id"]) == clue_id:
			return true
	return false
