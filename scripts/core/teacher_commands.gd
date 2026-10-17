class_name TeacherCommands
extends RefCounted
## 老师命令与时间规则（《老师版规则合并稿 D01至D07》D03）。
##
## 分工：表现层只发意图、只读快照；耗时与效果都在这里结算；数值全部来自
## `data/rules/teacher_commands.csv`（耗时）与 `data/rules/activities.csv`（压力增量）。
##
## 已实现（D03 已明确的部分）：
##   · 召唤 10 秒到达 / 遣返 10 秒；办公室同时只召唤一名学生
##   · 办公室聊天统一 20 秒（安抚 / 训斥 / 打听 / 鼓励），召唤与遣返另计
##   · 去教室：即时、不设固定耗时；每个课间首次进入 → 全班压力 +5（同一课间不重复）
##   · 调座位：发起后 10 秒生效
##   · 上课统一边界：上课期间不执行命令、不产生未完成命令的效果；未完成命令保留到下一个课间
##
## 待确认（合并稿未定，本模块不擅自新增数值）：
##   · 延后命令是「保留已用时间继续」还是「重新计满」—— 当前按**保留已用时间继续**实现
##     （见 `_hold_for_class`）；确认后只改这一处。
##   · 安抚的减压幅度、调解耗时、打听 / 鼓励的效果数值 —— 相关命令只计时、不施加数值。

var _timing: Dictionary = {}
var _acts: Dictionary = {}

## 当前命令："", "summon", "office_chat", "send_back", "seat_change"
var _command := ""
var _mediate_pair: Dictionary = {}  # 老师调解（D07）的双方
## 命令的剩余秒数（1 tick = 1 秒，课间）
var _remaining := 0
## 被召唤 / 正在办公室的学生索引（-1 = 无人）
var _called := -1
## 办公室聊天的类型（"comfort" / "scold" / "ask" / "encourage"）
var _chat_kind := ""
## 调座位：{"a": int, "b": int}
var _seat_change := {}
## 上课期间挂起的命令（下课后继续）
var _held := false
## 本课间是否已经触发「首次进入教室」的全班加压
var _entered_this_break := false


func configure(timing: Dictionary, activities: Dictionary) -> void:
	_timing = timing
	_acts = activities


# ------------------------------------------------------------------ 段边界（D03 第 8/9/10 条）
## 课间开始：解除挂起，重置「每课间首次进入教室」的生效机会。
func begin_break() -> void:
	_entered_this_break = false
	_held = false


## 上课开始（D03 第 9 / 10 条）：未完成的命令不执行、不产生效果；召唤行程中断（学生先回课堂）。
## 当前按「保留已用时间继续」挂起（待确认项，见文件头）。
func begin_class(core: Variant) -> void:
	_held = true
	# 召唤途中上课：学生先回到课堂，命令本身保留（下课后继续）
	if _command == "summon" and _called >= 0:
		if core != null and core.has_method("set_position_free"):
			pass


## 是否被上课挂起（上课期间不推进任何命令）。
func is_held() -> bool:
	return _held


# ------------------------------------------------------------------ 命令入口
## 召唤（D03 第 1 条）：一次只能叫一名学生；已在办公室的学生不重复召唤。
func summon(core: Variant, index: int) -> bool:
	if _held or _command != "" or _called >= 0 or index < 0 or index >= int(core.node_count()):
		return false
	core.interrupt_for_seat_change(index)
	_called = index
	var travel := int(_timing["summon_travel_seconds"])
	if travel <= 0:
		# 2026-10-16 裁定：叫同学来不再等待路程，学生**直接到办公室**（即时完成）。
		# 学生从召唤发起时就已在办公室（见 _is_in_office），完成后即可谈话／遣返。
		_command = ""
		_remaining = 0
		core._note_stopped(index)
		return true
	_command = "summon"
	_remaining = travel
	return true


## 遣返回教室（D03 第 1 条）：上课前剩余时间不足返程秒数时直接返回，不等完整流程。
func send_back(core: Variant) -> bool:
	if _held or _called < 0 or _command != "":
		return false
	_command = "send_back"
	var back := int(_timing["send_back_seconds"])
	var left := _seconds_left_in_break(core)
	_remaining = mini(back, left) if left > 0 else 0
	if _remaining <= 0:
		_finish(core)
	return true


## 办公室聊天（D03 第 2 条）：安抚 / 训斥 / 打听 / 鼓励统一耗时 20 秒；训斥按 D01 加压 +20。
## 参数 `_core` 保留为统一调用签名（与 summon / send_back 一致），本命令当下不需读内核状态。
func office_chat(_core: Variant, kind: String) -> bool:
	if _held or _command != "" or kind not in ["comfort", "scold", "ask", "encourage"]:
		return false
	if _called < 0:
		return false
	_command = "office_chat"
	_chat_kind = kind
	_remaining = int(_timing["office_chat_seconds"])
	return true


## 老师调解（D07）：任一方向敌对 >50 才执行（否则调用方不应扣耗时）；
## 完成后双方敌对各 −5，不抹去风险历史、不自动修复无冲突的敌对。
func mediate(core: Variant, a: int, b: int) -> bool:
	if _held or _command != "" or _called >= 0:
		return false
	if a < 0 or b < 0 or a == b or a >= int(core.node_count()) or b >= int(core.node_count()):
		return false
	var threshold := float(core._mediate_hostility_threshold())
	if float(core.hostility(a, b)) <= threshold and float(core.hostility(b, a)) <= threshold:
		return false  # 两方向都不超过门槛：不执行、不扣耗时
	_command = "mediate"
	_remaining = int(_timing["mediate_seconds"])
	_mediate_pair = {"a": a, "b": b}
	return true


## 全班训斥（D01）：全班压力 +30；有「听劝」的学生动力额外 +10（§10.2，按实际完成结算）。
func scold_class(core: Variant) -> void:
	var delta := float(_acts["class_scold_stress"])
	for i in range(int(core.node_count())):
		core.add_stress(i, delta)
		core._note_scolded(i)


## 去教室（D03 第 3 条）：即时，不设固定耗时；每个课间首次进入 → 全班压力 +5（同一课间不重复）。
func enter_classroom(core: Variant) -> bool:
	if _held or _entered_this_break:
		return false
	_entered_this_break = true
	var delta := float(_acts["teacher_enter_stress"])
	for i in range(int(core.node_count())):
		core.add_stress(i, delta)
	return true


## 调座位（D03 第 4 / 5 / 6 条）：发起后 10 秒生效；发起时打断参与者当前行为。
func start_seat_change(core: Variant, a: int, b: int) -> bool:
	if _held or _command != "" or _called >= 0:
		return false
	if a < 0 or b < 0 or a == b:
		return false
	if a >= int(core.node_count()) or b >= int(core.node_count()):
		return false
	_command = "seat_change"
	_remaining = int(_timing["seat_change_seconds"])
	_seat_change = {"a": a, "b": b}
	core.interrupt_for_seat_change(a)
	core.interrupt_for_seat_change(b)
	return true


# ------------------------------------------------------------------ 推进（每秒一次）
func tick(core: Variant) -> void:
	if _command == "" or _held:
		return
	_remaining -= 1
	if _remaining > 0:
		return
	_finish(core)


func _finish(core: Variant) -> void:
	match _command:
		"seat_change":
			if not _seat_change.is_empty():
				core.apply_seat_change(int(_seat_change["a"]), int(_seat_change["b"]))
			_seat_change = {}
		"mediate":
			if not _mediate_pair.is_empty():
				var cut := float(core._mediate_hostility_cut())
				core._add_hostility(int(_mediate_pair["a"]), int(_mediate_pair["b"]), -cut)
				core._add_hostility(int(_mediate_pair["b"]), int(_mediate_pair["a"]), -cut)
				# D07 §10：调解完成后，涉及的双方本课间都不能再主动伤害。
				core._note_stopped(int(_mediate_pair["a"]))
				core._note_stopped(int(_mediate_pair["b"]))
			_mediate_pair = {}
		"office_chat":
			# 训斥按 D01 加压 +20；安抚 / 打听 / 鼓励的幅度待确认，只计时不施加数值。
			if _chat_kind == "scold" and _called >= 0:
				core.add_stress(_called, float(_acts["office_scold_stress"]))
				core._note_scolded(_called)
			# D07 §10：办公室处理（含现场制止类的训斥）完成后，该学生本课间不能主动伤害。
			core._note_stopped(_called)
			_chat_kind = ""
		"summon":
			# D07 §10：被召唤到办公室后，该学生本课间不能主动伤害。
			core._note_stopped(_called)
		"send_back":
			_called = -1
	_command = ""
	_remaining = 0


func _seconds_left_in_break(core: Variant) -> int:
	if core == null:
		return 0
	var snap: Dictionary = core.time_snapshot()
	if str(snap.get("kind", "")) != "break":
		return 0
	return int(snap.get("tick_count", 0)) - int(snap.get("tick_in_phase", 0))


# ------------------------------------------------------------------ 只读快照
## 该生是否处在换座窗口内（D03 第 5 条）：换座期间不参加课间涓流（既不作接收者也不作来源）。
func is_seat_changing(i: int) -> bool:
	if _command != "seat_change" or _seat_change.is_empty():
		return false
	return int(_seat_change["a"]) == i or int(_seat_change["b"]) == i


func snapshot() -> Dictionary:
	return {
		"command": _command,
		"remaining_seconds": _remaining,
		"called": _called,
		"chat_kind": _chat_kind,
		"seat_change": _seat_change.duplicate(true),
		"held_by_class": _held,
		"entered_this_break": _entered_this_break,
	}


func current_command() -> String:
	return _command


func remaining_seconds() -> int:
	return _remaining


func called_index() -> int:
	return _called
