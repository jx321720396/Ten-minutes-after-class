class_name TeacherCommands
extends RefCounted
## 老师命令与时间规则（《老师版规则合并稿 D01至D07》D03）。
##
## 分工：表现层只发意图、只读快照；耗时与效果都在这里结算；数值全部来自
## `data/rules/teacher_commands.csv`（耗时）与 `data/rules/activities.csv`（压力增量）。
##
## 已实现（D03 已明确的部分）：
##   · 召唤与遣返都即时完成；办公室同时只召唤一名学生
##   · 办公室聊天统一 20 秒（安抚 / 表扬 / 训斥 / 打听 / 鼓励），召唤与遣返另计
##   · 去教室：即时、不设固定耗时；每个课间首次进入 → 全班压力 +5（同一课间不重复）
##   · 调座位：发起后 10 秒生效
##   · 上课统一边界：上课期间不执行命令、不产生未完成命令的效果；未完成命令保留到下一个课间
##
## 待确认（合并稿未定，本模块不擅自新增数值）：
##   · 延后命令是「保留已用时间继续」还是「重新计满」—— 当前按**保留已用时间继续**实现
##     （见 `_hold_for_class`）；确认后只改这一处。
##   · 调解耗时 —— 鼓励只计时、不直接施加数值（结束时生成一次聊天目标，见下方 D09）。
##     安抚减压、表扬只加动力、训斥走一般压力联动（压力与动力同加）。
##     打听在谈话结束时给出「一条优先消息 + 最多 ask_relation_max 条有向单轴关系信息」（D10），
##     不改压力、动力、学业收益或真实关系矩阵；关系信息只进入档案观察笔记。

var _timing: Dictionary = {}
var _acts: Dictionary = {}

## 当前命令："", "summon", "office_chat", "send_back", "seat_change"
var _command := ""
var _mediate_pair: Dictionary = {}  # 老师调解（D07）的双方
## 命令的剩余秒数（1 tick = 1 秒，课间）
var _remaining := 0
## 被召唤 / 正在办公室的学生索引（-1 = 无人）
var _called := -1
## 办公室聊天的类型（"comfort" / "praise" / "scold" / "ask" / "encourage"）
var _chat_kind := ""
## 调座位：{"a": int, "b": int}
var _seat_change := {}
## 上课期间挂起的命令（下课后继续）
var _held := false
## 本课间是否已经成功完成一次打听（D10：全班每课间最多成功一次）。
var _asked_this_break := false
## 打听关系记录的专用随机流（独立于内核 _rng，避免污染模拟序列；种子取内核 seed）。
var _ask_rng: MtRandom = null
## 优先消息去重：已告知过的「消息类型:目标」，不反复让同一条未变化消息占用机会。
var _told_messages: Dictionary = {}
## 关系记录覆盖：已打听过的「受访者:对象:轴」，下次优先未打听过的方向/轴。
var _asked_relations: Dictionary = {}
## 最近一次打听结果。界面只读，按序号显示一次。
var _ask_lines: Array = []
## 最近一次打听的有向单轴关系记录（供档案观察笔记写入，不改真实矩阵）。
var _ask_records: Array = []
var _ask_id := 0
## 本课间是否已经触发「首次进入教室」的全班加压
var _entered_this_break := false
# —— 鼓励目标（D09，2026-10-17）：老师 20 秒鼓励 → 一次聊天目标 ——
## 目标对象索引（-1 = 自主模式尚未选人；>=0 = 指定或已选定的对象）
var _encourage_target: Array = []
## "specified"（老师指定对象）/ "auto"（自主找最近娱乐对象）
var _encourage_mode: Array = []
## 剩余课间次数（含当前课间；跨上课保留；考试日无课间不消耗）
var _encourage_breaks: Array = []
## "" = 无目标；"active" / "done" / "rejected" / "expired"（观察层只读）
var _encourage_status: Array = []


func configure(timing: Dictionary, activities: Dictionary) -> void:
	_timing = timing
	_acts = activities


## 鼓励目标有效期（课间数，含当前课间）。
func encourage_valid_breaks() -> int:
	return int(_timing.get("encourage_valid_breaks", 4))


# ------------------------------------------------------------------ 鼓励目标生命周期（D09）
## 新局重置鼓励目标（每名学生一格；由内核 `_reset_runtime` 调用）。
func reset_encourage(n: int) -> void:
	_encourage_target.clear()
	_encourage_mode.clear()
	_encourage_breaks.clear()
	_encourage_status.clear()
	for _i in range(n):
		_encourage_target.append(-1)
		_encourage_mode.append("")
		_encourage_breaks.append(0)
		_encourage_status.append("")


## 老师完成 20 秒鼓励后生成一次聊天目标。已有未结束目标时重复鼓励无效（不覆盖、不叠加）。
## target >= 0 = 指定对象；target < 0 = 自主找最近娱乐对象。
func start_encourage(i: int, target: int) -> bool:
	if i < 0 or i >= _encourage_status.size():
		return false
	if _encourage_status[i] == "active":
		return false
	_encourage_target[i] = target
	_encourage_mode[i] = "specified" if target >= 0 else "auto"
	_encourage_breaks[i] = encourage_valid_breaks()
	_encourage_status[i] = "active"
	return true


func has_active_encourage(i: int) -> bool:
	return i >= 0 and i < _encourage_status.size() and _encourage_status[i] == "active"


## 鼓励目标只读快照（观察层 / 界面；不回写内核）。
## `wait_reason` 仅在 status == "active" 时有意义：空串 = 可尝试，非空 = 等待原因。
func encourage_snapshot(core: Variant, i: int) -> Dictionary:
	if i < 0 or i >= _encourage_status.size():
		return {}
	return {
		"target": _encourage_target[i],
		"mode": _encourage_mode[i],
		"breaks_left": _encourage_breaks[i],
		"status": _encourage_status[i],
		"wait_reason": _wait_reason(core, i),
	}


## 交流目标展示文案（界面只读，观察层）。无目标时返回空串，由界面回落到「暂无」。
func encourage_goal_text(core: Variant, i: int) -> String:
	var snap := encourage_snapshot(core, i)
	if snap.is_empty() or str(snap.get("status", "")) == "":
		return ""
	var status := str(snap["status"])
	var mode := "指定" if str(snap["mode"]) == "specified" else "自主"
	var target := int(snap["target"])
	var breaks := int(snap["breaks_left"])
	if status == "done":
		return "鼓励交流 · 已完成（%s）" % str(core.alias(target))
	if status == "rejected":
		return "鼓励交流 · 被拒绝（%s）" % str(core.alias(target))
	if status == "expired":
		if target < 0:
			return "鼓励交流 · 已到期"
		return "鼓励交流 · 已到期（%s）" % str(core.alias(target))
	# active：展示对象、模式、剩余课间次数，以及（若有）等待原因。
	if target < 0:
		return "鼓励交流 · %s · 待选对象 · 剩 %d 次课间" % [mode, breaks]
	var line := "鼓励交流 · %s · %s · 剩 %d 次课间" % [mode, str(core.alias(target)), breaks]
	var reason := str(snap["wait_reason"])
	if reason != "":
		line += " · " + reason
	return line


## 等待原因（仅在进行中且当前不可尝试时非空）。
func _wait_reason(core: Variant, i: int) -> String:
	if _encourage_status[i] != "active":
		return ""
	var t := int(_encourage_target[i])
	if t < 0:
		return "无合格对象"
	if (
		core._join_blocked(t)
		or (core._phase_state.size() > t and str(core._phase_state[t]) in ["study", "broken"])
	):
		return "对象暂不可聊"
	if core._global_tick < core._busy_until[t]:
		return "对象忙碌中"
	return ""


## 课间末扣减鼓励目标有效期；归零即到期。只对「进行中」目标生效；
## 考试日没有课间，`_end_phase` 不会调用本方法（不消耗次数）。
func settle_encourage_breaks() -> void:
	for i in range(_encourage_status.size()):
		if _encourage_status[i] != "active":
			continue
		_encourage_breaks[i] -= 1
		if _encourage_breaks[i] <= 0:
			_encourage_status[i] = "expired"


## 鼓励目标的一次尝试（D09）：返回 true = 本决策点被鼓励占满（成事或关系拒绝）；
## false = 等待（无合格对象 / 对象忙碌 / 锁定），学生走正常决策。不强行打断锁定、崩溃或办公室状态。
func try_encourage(core: Variant, i: int) -> bool:
	if _encourage_status[i] != "active":
		return false
	if _encourage_target[i] < 0:
		var picked := _pick_encourage_target(core, i)
		if picked < 0:
			return false  # 无合格对象，等待
		_encourage_target[i] = picked
	var t := int(_encourage_target[i])
	# 目标此刻不能聊天（锁定 / 不在场 / 睡觉 / 忙碌）→ 等待，不打断、不算关系拒绝。
	if (
		core._join_blocked(t)
		or (core._phase_state.size() > t and str(core._phase_state[t]) in ["study", "broken"])
	):
		return false
	if core._global_tick < core._busy_until[t]:
		return false  # 目标还在娱乐 / 忙碌，等其活动结束
	var log_before: int = core._join_log.size()
	core._propose_activity(i, t, "chat")
	var stage := ""
	if core._join_log.size() > log_before:
		stage = str(core._join_log[-1]["stage"])
	if stage == "vote_reject":
		_encourage_status[i] = "rejected"
		return true  # 关系拒绝：目标结束，本决策点到此为止
	if core._conv_of[i] != null:
		_encourage_status[i] = "done"
		return true  # 聊天成功：目标完成
	return false  # 条件不满足等：保持 active，下一决策点再试


## 鼓励专用选人（D09）：距离最近、正在娱乐且符合聊天条件；并列带种子随机。
func _pick_encourage_target(core: Variant, i: int) -> int:
	var best: Array = []
	var best_dist := 1e9
	for j in range(int(core.node_count())):
		if not _encourage_target_eligible(core, i, j):
			continue
		var d: float = core.distance_between(i, j)
		if d < best_dist - 1e-6:
			best_dist = d
			best = [j]
		elif abs(d - best_dist) <= 1e-6:
			best.append(j)
	if best.is_empty():
		return -1
	if best.size() == 1:
		return int(best[0])
	return int(core._rng.choice(best))


func _encourage_target_eligible(core: Variant, i: int, j: int) -> bool:
	if j == i or core._join_blocked(j):
		return false
	if core._phase_state.size() > j and str(core._phase_state[j]) in ["study", "broken"]:
		return false
	return _is_entertaining(core, j)


## 正在娱乐 = 正在做休闲活动（LEISURE_KINDS 且占用未到）。
func _is_entertaining(core: Variant, j: int) -> bool:
	return core.LEISURE_KINDS.has(core._busy_act[j]) and core._global_tick < core._busy_until[j]


# ------------------------------------------------------------------ 段边界（D03 第 8/9/10 条）
## 课间开始：解除挂起，重置「每课间首次进入教室」的生效机会。
func begin_break() -> void:
	_entered_this_break = false
	_held = false
	_asked_this_break = false


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


## D05（2026-10-17 裁定）：考试当天只有考试 —— 老师命令一律不接受，在途命令冻结到考后。
func _exam_blocked(core: Variant) -> bool:
	return core != null and core.has_method("is_exam_only_day") and bool(core.is_exam_only_day())


# ------------------------------------------------------------------ 命令入口
## 召唤（D03 第 1 条）：一次只能叫一名学生；已在办公室的学生不重复召唤。
func summon(core: Variant, index: int) -> bool:
	if _exam_blocked(core):
		return false
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


## 送回教室：返程秒数为 0 时当场离开办公室，不再占用命令、不消耗课间时间。
func send_back(core: Variant) -> bool:
	if _exam_blocked(core):
		return false
	if _held or _called < 0 or _command != "":
		return false
	var back := int(_timing["send_back_seconds"])
	if back <= 0:
		_called = -1
		_command = ""
		_remaining = 0
		return true
	_command = "send_back"
	var left := _seconds_left_in_break(core)
	_remaining = mini(back, left) if left > 0 else 0
	if _remaining <= 0:
		_finish(core)
	return true


## 办公室聊天（D03 第 2 条）：安抚 / 表扬 / 训斥 / 打听 / 鼓励统一耗时 20 秒。
## 安抚：压力与动力各减配置值（一般联动）。训斥：压力与动力各加配置值。
## 表扬：只加该生动力，不加压力。鼓励当下只计时。
## 打听结束时给出消息：首次 3 条，再次打听同一人 5 条；百事通提高到配置条数。
## 参数 `_core` 保留为统一调用签名（与 summon / send_back 一致），本命令当下不需读内核状态。
func office_chat(core: Variant, kind: String) -> bool:
	if _exam_blocked(core):
		return false
	if _held or _command != "" or kind not in ["comfort", "praise", "scold", "ask", "encourage"]:
		return false
	if _called < 0:
		return false
	# D09：已有未结束目标时重复鼓励无效，不覆盖、不叠加、也不扣 20 秒。
	if kind == "encourage" and has_active_encourage(_called):
		return false
	# D10：全班每课间最多成功一次打听；本课间已打听过则不再扣 20 秒。
	if kind == "ask" and _asked_this_break:
		return false
	_command = "office_chat"
	_chat_kind = kind
	_remaining = int(_timing["office_chat_seconds"])
	return true


## 中断正在进行的办公室谈话：当作从未发生（谈话效果只在 _finish 结算，未到不结算）。
## 打听／鼓励尚未结算，取消后可重新选择；已流逝的课间时间不退（期间其余学生仍在行动）。
## 返回是否真的取消了一项在途谈话（无在途谈话返回 false）。
func cancel_office_chat() -> bool:
	if _command != "office_chat":
		return false
	_command = ""
	_chat_kind = ""
	_remaining = 0
	return true


## 老师调解：进行中的吵架 / 推搡立刻终止（敌对只加中断幅度）；
## 没有可终止的冲突时，命令结束后双方敌对各 −10。
## 打架不能终止。自本次调解结束的课间起，三个课间不能再调解这对人。
func mediate(core: Variant, a: int, b: int) -> bool:
	if _exam_blocked(core):
		return false
	if _held or _command != "" or _called >= 0:
		return false
	if a < 0 or b < 0 or a == b or a >= int(core.node_count()) or b >= int(core.node_count()):
		return false
	var outcome := "queued"
	if core._harm_events != null:
		outcome = str(core._harm_events.mediate(core, a, b))
	if outcome in ["invalid", "cooldown", "fight"]:
		return false
	_command = "mediate"
	_remaining = int(_timing["mediate_seconds"])
	_mediate_pair = {"a": a, "b": b, "apply_cut": outcome == "queued"}
	return true


## 全班训斥（D01）：全班压力 +30；有「听劝」的学生动力额外 +10（§10.2，按实际完成结算）。
func scold_class(core: Variant) -> void:
	if _exam_blocked(core):
		return
	var delta := float(_acts["class_scold_stress"])
	for i in range(int(core.node_count())):
		core.add_stress(i, delta)
		core._note_scolded(i)


## 去教室（D03 第 3 条）：即时，不设固定耗时；每个课间首次进入 → 全班压力 +5（同一课间不重复）。
func enter_classroom(core: Variant) -> bool:
	if _exam_blocked(core):
		return false
	if _held or _entered_this_break:
		return false
	_entered_this_break = true
	var delta := float(_acts["teacher_enter_stress"])
	for i in range(int(core.node_count())):
		core.add_stress(i, delta)
	return true


## 调座位（D03 第 4 / 5 / 6 条）：发起后 10 秒生效；发起时打断参与者当前行为。
func start_seat_change(core: Variant, a: int, b: int) -> bool:
	if _exam_blocked(core):
		return false
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
	if _exam_blocked(core):
		return
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
				var a := int(_mediate_pair["a"])
				var b := int(_mediate_pair["b"])
				if core._harm_events != null:
					core._harm_events.finish_mediate(
						core, a, b, bool(_mediate_pair.get("apply_cut", true))
					)
				core._note_stopped(a)
				core._note_stopped(b)
			_mediate_pair = {}
		"office_chat":
			# 训斥走一般联动（压力与动力同加）；安抚按一般联动减压；表扬只加动力。
			# 打听只给出消息；鼓励生成一次聊天目标（D09，自主模式：学生自己找最近娱乐对象）。
			if _called >= 0 and _chat_kind == "scold":
				core.add_stress(_called, float(_acts["office_scold_stress"]))
				core._note_scolded(_called)
			elif _called >= 0 and _chat_kind == "comfort":
				core.add_stress(_called, float(_acts["office_comfort_stress"]))
			elif _called >= 0 and _chat_kind == "praise":
				core.add_vitality(_called, float(_acts["office_praise_vitality"]))
			elif _called >= 0 and _chat_kind == "ask":
				_deliver_ask(core, _called)
			elif _called >= 0 and _chat_kind == "encourage":
				start_encourage(_called, -1)
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


## 打听（D10）：一条优先消息 + 最多 ask_relation_max 条有向单轴关系信息。
## 优先消息按「正式霸凌 → 正式孤立 → 敌对隐患 → 低好感隐患 → 手机 → MP3 → 零食」取最高可用，
## 且不反复给同一条未变化消息（按「类型:目标」去重）。
## 关系信息方向固定为受访者 → 对象，每条只含好感或敌对一轴，优先未打听过的方向/轴；
## 选取走独立的 _ask_rng（种子取内核 seed，不污染模拟随机序列）。不改真实矩阵。
func _deliver_ask(core: Variant, index: int) -> void:
	_asked_this_break = true
	if _ask_rng == null:
		_ask_rng = MtRandom.new(core.seed())
	var rel_cap := int(_timing.get("ask_relation_max", 3))
	var informed := int(core.teacher_student_snapshot(index).get("well_informed_messages", 0))
	if informed > rel_cap:
		rel_cap = informed  # 百事通：一次打听提供更多关系信息
	var stamp: Dictionary = core.time_snapshot()
	var lines: Array = []
	var priority := _pick_priority_message(core, index)
	if priority != "":
		lines.append(priority)
	var records := _pick_relation_records(core, index, rel_cap, stamp)
	for rec in records:
		lines.append(_relation_line(core, rec))
	if lines.is_empty():
		lines.append("暂无新的相关消息")
	_ask_records = records
	_ask_lines = lines
	_ask_id += 1


## 优先消息（D10）：按优先级从高到低取第一条「可提供且未告知」的消息；没有则返回空串。
func _pick_priority_message(core: Variant, index: int) -> String:
	# 1/2) 正式霸凌 → 正式孤立（读已有风险记录，不以一次打听生成正式风险）。
	for kind in ["bully", "isolate"]:
		for t in _triggered_of_kind(core, kind):
			if _tell_once("risk_%s" % kind, t):
				return _risk_text(core, kind, t)
	# 3) 敌对隐患：≥ ask_hostility_hint_count 名其他学生对同一目标敌对 > 阈值。
	for t in _hostility_hint_targets(core):
		if _tell_once("hostility_hint", t):
			return _hostility_hint_text(core, t)
	# 4) 低好感隐患：≥ ask_low_affinity_count 名其他学生对目标好感 < 阈值（超过一周才开放）。
	if int(core.day()) >= int(_timing.get("ask_low_affinity_open_day", 8)):
		for t in _low_affinity_hint_targets(core):
			if _tell_once("low_affinity_hint", t):
				return _low_affinity_hint_text(core, t)
	# 5-7) 物品消息：受访者对目标敌对 > 阈值，且「知道」其带对应物品（知情范围待定）。
	for item in ["phone", "mp3", "snack"]:
		for t in _item_hint_targets(core, index, item):
			if _tell_once("item_%s" % item, t):
				return _item_text(core, item, t)
	return ""


## 正式风险目标（只读）：已正式触发该类型的学生，按节点号升序。
func _triggered_of_kind(core: Variant, kind: String) -> Array:
	var out: Array = []
	var risk: Dictionary = core._risk_snapshot()
	var triggered: Array = risk.get("triggered", [])
	var kinds: Array = risk.get("triggered_kind", [])
	for i in range(int(core.node_count())):
		if (
			i < triggered.size()
			and i < kinds.size()
			and bool(triggered[i])
			and str(kinds[i]) == kind
		):
			out.append(i)
	return out


## 敌对隐患目标：≥ 阈值人数的其他学生对同一目标敌对严格超过阈值。
func _hostility_hint_targets(core: Variant) -> Array:
	var threshold := float(_timing.get("ask_hostility_hint_threshold", 50))
	var need := int(_timing.get("ask_hostility_hint_count", 2))
	var n := int(core.node_count())
	var out: Array = []
	for k in range(n):
		var count := 0
		for j in range(n):
			if j != k and float(core.hostility(j, k)) > threshold:
				count += 1
		if count >= need:
			out.append(k)
	return out


## 低好感隐患目标：≥ 阈值人数的其他学生对目标好感严格低于阈值。
func _low_affinity_hint_targets(core: Variant) -> Array:
	var threshold := float(_timing.get("ask_low_affinity_threshold", 20))
	var need := int(_timing.get("ask_low_affinity_count", 13))
	var n := int(core.node_count())
	var out: Array = []
	for k in range(n):
		var count := 0
		for j in range(n):
			if j != k and float(core.affinity(j, k)) < threshold:
				count += 1
		if count >= need:
			out.append(k)
	return out


## 物品消息目标：受访者对目标敌对严格超过阈值，且「知道」其带对应物品。
## 知情范围待定（无携带物品模型）：暂以「目标此刻正在做对应娱乐」作为「知道」的代理。
func _item_hint_targets(core: Variant, index: int, item: String) -> Array:
	var threshold := float(_timing.get("ask_item_hostility_threshold", 40))
	var act: String = {"phone": "play_phone", "mp3": "listen_music", "snack": "eat_snack"}[item]
	var n := int(core.node_count())
	var out: Array = []
	for k in range(n):
		if k == index:
			continue
		if float(core.hostility(index, k)) <= threshold:
			continue
		if str(core._busy_act[k]) == act:
			out.append(k)
	return out


## 去重并登记：同一条（类型:目标）只告知一次，返回是否可用。
func _tell_once(kind: String, target: int) -> bool:
	var key := "%s:%d" % [kind, target]
	if _told_messages.has(key):
		return false
	_told_messages[key] = true
	return true


## 关系记录（D10）：最多 rel_cap 条，方向受访者→对象，单轴，优先未打听过的方向/轴。
func _pick_relation_records(core: Variant, index: int, rel_cap: int, stamp: Dictionary) -> Array:
	var uncovered: Array = []
	var covered: Array = []
	var n := int(core.node_count())
	for j in range(n):
		if j == index:
			continue
		for axis in ["affinity", "hostility"]:
			var value: float = (
				core.affinity(index, j) if axis == "affinity" else core.hostility(index, j)
			)
			var rec := {"source": index, "subject": j, "axis": axis, "value": value}
			rec.merge(stamp, true)
			if _asked_relations.has(_rel_key(index, j, axis)):
				covered.append(rec)
			else:
				uncovered.append(rec)
	var picked: Array = []
	if uncovered.size() >= rel_cap:
		picked = _ask_rng.sample(uncovered, rel_cap)
	else:
		picked = uncovered.duplicate()
		var remaining := rel_cap - picked.size()
		if remaining > 0 and not covered.is_empty():
			picked.append_array(_ask_rng.sample(covered, mini(remaining, covered.size())))
	for rec in picked:
		_asked_relations[_rel_key(int(rec["source"]), int(rec["subject"]), str(rec["axis"]))] = true
	picked.sort_custom(_relation_less)
	return picked


func _rel_key(source: int, subject: int, axis: String) -> String:
	return "%d:%d:%s" % [source, subject, axis]


func _relation_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["subject"]) != int(b["subject"]):
		return int(a["subject"]) < int(b["subject"])
	return str(a["axis"]) < str(b["axis"])


func _relation_line(core: Variant, rec: Dictionary) -> String:
	var axis_label := "好感" if str(rec["axis"]) == "affinity" else "敌对"
	return (
		"我（%s）对%s的%s：%s"
		% [
			str(core.alias(int(rec["source"]))),
			str(core.alias(int(rec["subject"]))),
			axis_label,
			_disclose_band(float(rec["value"])),
		]
	)


## 关系披露档位（待定：数值精度 vs 档位，当前按档位，阈值与档案档位一致）。
func _disclose_band(value: float) -> String:
	if value >= float(_timing.get("ask_disclose_very_high", 75)):
		return "很高"
	if value >= float(_timing.get("ask_disclose_high", 50)):
		return "较高"
	if value >= float(_timing.get("ask_disclose_medium", 25)):
		return "一般"
	return "较低"


func _risk_text(core: Variant, kind: String, t: int) -> String:
	if kind == "bully":
		return "听说%s最近一直被同学欺负" % str(core.alias(t))
	return "听说%s最近持续被排斥" % str(core.alias(t))


func _hostility_hint_text(core: Variant, t: int) -> String:
	return "有几个同学对%s的敌意很深" % str(core.alias(t))


func _low_affinity_hint_text(core: Variant, t: int) -> String:
	return "班里很多同学不太喜欢%s" % str(core.alias(t))


func _item_text(core: Variant, item: String, t: int) -> String:
	var label: String = {"phone": "手机", "mp3": "MP3", "snack": "零食"}[item]
	return "听说%s带了%s" % [str(core.alias(t)), label]


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
		"ask_lines": _ask_lines.duplicate(),
		"ask_records": _ask_records.duplicate(true),
		"ask_id": _ask_id,
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


# ------------------------------------------------------------------ 存档
## 导出老师命令运行时状态。_ask_rng 是第二条独立随机流（打听），必须随档，勿漏。
## _timing / _acts 是配置，由 configure 重建。
func export_state() -> Dictionary:
	return {
		"command": _command,
		"mediate_pair": _mediate_pair.duplicate(true),
		"remaining": _remaining,
		"called": _called,
		"chat_kind": _chat_kind,
		"seat_change": _seat_change.duplicate(true),
		"held": _held,
		"asked_this_break": _asked_this_break,
		"ask_rng": _ask_rng.export_state() if _ask_rng != null else {},
		"told_messages": _told_messages.duplicate(true),
		"asked_relations": _asked_relations.duplicate(true),
		"ask_lines": _ask_lines.duplicate(),
		"ask_records": _ask_records.duplicate(true),
		"ask_id": _ask_id,
		"entered_this_break": _entered_this_break,
		"encourage_target": _encourage_target.duplicate(),
		"encourage_mode": _encourage_mode.duplicate(),
		"encourage_breaks": _encourage_breaks.duplicate(),
		"encourage_status": _encourage_status.duplicate(),
	}


## 回填老师命令状态（读档用）。JSON 往返把 int / bool 变 float，逐个还原。
func restore_state(data: Dictionary) -> void:
	_command = str(data.get("command", ""))
	_mediate_pair = _int_pair(data.get("mediate_pair", {}))
	_remaining = int(data.get("remaining", 0))
	_called = int(data.get("called", -1))
	_chat_kind = str(data.get("chat_kind", ""))
	_seat_change = _int_pair(data.get("seat_change", {}))
	_held = bool(data.get("held", false))
	_asked_this_break = bool(data.get("asked_this_break", false))
	if _ask_rng == null:
		_ask_rng = MtRandom.new(0)
	_ask_rng.restore_state(data.get("ask_rng", {}))
	_told_messages = data.get("told_messages", {}).duplicate(true)
	_asked_relations = data.get("asked_relations", {}).duplicate(true)
	_ask_lines = data.get("ask_lines", []).duplicate()
	_ask_records = data.get("ask_records", []).duplicate(true)
	_ask_id = int(data.get("ask_id", 0))
	_entered_this_break = bool(data.get("entered_this_break", false))
	_encourage_target = _ints(data.get("encourage_target", []))
	_encourage_mode = _strs(data.get("encourage_mode", []))
	_encourage_breaks = _ints(data.get("encourage_breaks", []))
	_encourage_status = _strs(data.get("encourage_status", []))


func _int_pair(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	return {"a": int(raw.get("a", -1)), "b": int(raw.get("b", -1))}


func _ints(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(int(v))
	return out


func _strs(raw: Array) -> Array:
	var out: Array = []
	for v in raw:
		out.append(str(v))
	return out
