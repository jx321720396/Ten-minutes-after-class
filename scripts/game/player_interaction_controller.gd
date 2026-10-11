class_name PlayerInteractionController
extends Node3D
## 玩家交互控制器（表现层编排）：**选择 → 接近 → 校验 → 提交 → 演出 → 反馈**。
##
## 依据：主文档 §10.5／§10.7／§10.31／§10.32、§12.1；
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §2、§3、§6、§7。
##
## 职责边界（只有这里做编排，其他组件都别自己拉一遍流程）：
##   · **PlayerController 独占移动**：本控制器只调 `plan_approach` / `follow_path`；
##   · **内核独占判定与结算**：本控制器只调 `preview_player_interaction` / `commit_player_interaction`，
##     不做概率、不改矩阵、不自己判断「能不能聊」；
##   · **表现只读**：菜单 / 圈 / 气泡 / 情绪 / HUD 都是消费者，唯一的放行口是 `result_revealed`。
##
## 状态机（计划 §6）：Idle → Selected → Approaching → Validating → Active，
## 加入闲聊多一段 PenPresenting →（接受）Active /（拒绝）直接回到 Idle；
## 提交后的 Active / PenPresenting **禁止新行为与移动**，Esc 只打开暂停菜单。

signal state_changed(state: StringName)

const STATE_IDLE := &"idle"
const STATE_SELECTED := &"selected"
const STATE_APPROACHING := &"approaching"
const STATE_VALIDATING := &"validating"
const STATE_ACTIVE := &"active"
const STATE_PEN := &"pen_presenting"
const STATE_REJECTED := &"rejected_busy"

const KIND_CHAT := "chat"
const MODE_START := "start"
const MODE_JOIN := "join"
const PEN_HOLD := &"player_pen_check"
## 行为栏刷新频率（世界在推进，状态会变）
## 需要选对象的动作（与右侧行为栏的 target 组一致）
const BAR_REFRESH_SECONDS := 0.25
## 需要选对象的动作（与右侧行为栏的 target 组一致）
const PLAYER_TARGET_KINDS := ["chat", "pass_note", "report", "roughhouse", "exclude", "observe"]
## 自指行为（对自己做的事）：不选对象，点按钮就发起
const PLAYER_SELF_KINDS := ["study", "sleep"]

var _core: Variant = null
var _player: PlayerController = null
var _actors: Node3D = null
var _clock: SimulationClock = null
var _bar: PlayerActionBar = null
var _armed_kind := StringName("")
var _hud: ChatFeedbackHUD = null
var _rings: ActivityRingPresenter = null
var _bubbles: ChatActivityBubble = null
var _emotion: PlayerEmotionFeedback = null
var _note: NotePrompt = null

var _state: StringName = STATE_IDLE
var _selected := -1
var _request_id := -1
## 刚收尾的请求编号：线索通知可能紧跟完成通知之后到，只用于匹配情报，不用于提交
var _recent_request_id := -1
var _mode := ""
var _session_id := -1
var _packet: Dictionary = {}
var _pen_hold := false
var _bar_timer := 0.0


func _ready() -> void:
	set_process_unhandled_input(true)
	# EventBus 是 autoload：等一帧再连，保证场景装载顺序不影响接线
	call_deferred("_connect_sources")


# ------------------------------------------------------------------ 绑定


## 计划 §9 的公共接口：一次绑定内核 / 玩家 / 人物 / 时钟。
func bind_sources(
	core: Variant, player: PlayerController, actors: Node3D, clock: SimulationClock
) -> void:
	_core = core
	_player = player
	_actors = actors
	_clock = clock
	_connect_sources()


## 反馈组件（可选，缺失也不影响玩法逻辑）。
func bind_feedback(
	bar: PlayerActionBar,
	hud: ChatFeedbackHUD,
	rings: ActivityRingPresenter,
	bubbles: ChatActivityBubble,
	emotion: PlayerEmotionFeedback,
	note_prompt: NotePrompt
) -> void:
	_bar = bar
	_hud = hud
	_rings = rings
	_bubbles = bubbles
	_emotion = emotion
	_note = note_prompt


func _connect_sources() -> void:
	if _player != null:
		if not _player.actor_picked.is_connected(_on_actor_picked):
			_player.actor_picked.connect(_on_actor_picked)
		if not _player.ground_clicked.is_connected(_on_ground_clicked):
			_player.ground_clicked.connect(_on_ground_clicked)
		if not _player.request_arrived.is_connected(_on_request_arrived):
			_player.request_arrived.connect(_on_request_arrived)
		if not _player.request_cancelled.is_connected(_on_request_cancelled):
			_player.request_cancelled.connect(_on_request_cancelled)
		if not _player.request_failed.is_connected(_on_request_failed):
			_player.request_failed.connect(_on_request_failed)
	if _bar != null and not _bar.behavior_armed.is_connected(arm_behavior):
		_bar.behavior_armed.connect(arm_behavior)
	if _bar != null and not _bar.self_behavior_requested.is_connected(_on_self_behavior):
		_bar.self_behavior_requested.connect(_on_self_behavior)
	if _note != null and not _note.choice_made.is_connected(_on_note_choice):
		_note.choice_made.connect(_on_note_choice)
	if _hud != null and not _hud.result_revealed.is_connected(_on_result_revealed):
		_hud.result_revealed.connect(_on_result_revealed)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and not bus.event_happened.is_connected(_on_event_happened):
		bus.event_happened.connect(_on_event_happened)


func _disconnect_sources() -> void:
	if _player != null and is_instance_valid(_player):
		for signal_ref in [
			_player.actor_picked,
			_player.ground_clicked,
			_player.request_arrived,
			_player.request_cancelled,
			_player.request_failed,
		]:
			for connection in signal_ref.get_connections():
				signal_ref.disconnect(connection["callable"])
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.event_happened.is_connected(_on_event_happened):
		bus.event_happened.disconnect(_on_event_happened)


func _exit_tree() -> void:
	# 退出场景：取消未提交请求、释放**自己**持有的 hold，不撤销已提交的结算
	cancel_pending(&"scene_exit")
	_release_pen_hold()
	_disconnect_sources()
	if _hud != null:
		_hud.clear()


# ------------------------------------------------------------------ 对外接口


## 选中一个人物：只选中，不走动（走动由「选择行为」触发）。
func select_actor(index: int) -> void:
	if _core == null or index < 0:
		return
	if _is_committed():
		return
	cancel_pending(&"new_selection")
	_selected = index
	_set_state(STATE_SELECTED)
	_refresh_bar()
	# 已经选好动作时，点人就直接触发（两步交互的另一半）
	if _armed_kind != StringName(""):
		trigger_armed(index)


## 行为栏选中一个动作（§20.1.2 第一步）。如果已经点好了对象，立刻触发。
func arm_behavior(kind: StringName) -> void:
	if _is_committed():
		return
	_armed_kind = kind
	if _bar != null:
		_bar.set_armed(kind)
	_refresh_bar()
	if _selected >= 0:
		trigger_armed(_selected)


## 用已选动作对某个对象发起；需要接近的行为（闲聊）先走过去，到位后自动结算。
func trigger_armed(target: int) -> void:
	var kind := str(_armed_kind)
	if kind.is_empty() or not PLAYER_TARGET_KINDS.has(kind):
		return
	if kind == KIND_CHAT:
		request_behavior(KIND_CHAT)
		return
	if _core == null:
		return
	var result: Dictionary = _core.player_action(kind, target)
	if not bool(result.get("ok", false)):
		if _hud != null:
			_hud.show_status(_action_reason(str(result.get("error", ""))))
		return
	_finish_action()


## 自指行为（对自己做的事）：本批都是占位，明确告知而不是静默。
func _on_self_behavior(kind: StringName) -> void:
	var action := str(kind)
	if _core == null or not PLAYER_SELF_KINDS.has(action):
		if _hud != null:
			_hud.show_status("这个动作还没做出来。")
		return
	# 自指行为无对象：target 传 -1，内核对它们只看自己的状态
	var result: Dictionary = _core.player_action(action, -1)
	if not bool(result.get("ok", false)):
		if _hud != null:
			_hud.show_status(_action_reason(str(result.get("error", ""))))
		return
	if _hud != null:
		if action == "study":
			_hud.show_status("你回到座位，开始学习。")
		else:
			_hud.show_status("你父下睡了。")
	_refresh_bar()


## 请求一次闲聊（`kind` 固定 chat；`mode` 只在选择时解析一次，之后必须用冻结值提交）。
func request_behavior(kind: String, mode: String = "auto") -> void:
	if kind != KIND_CHAT or _selected < 0:
		return
	if _state != STATE_SELECTED:
		return
	var preview := _preview()
	if not bool(preview.get("ok", false)) or not bool(preview.get("eligible", false)):
		_refresh_bar()
		return
	var frozen_mode := str(preview["mode"]) if mode == "auto" else mode
	var frozen_session := int(preview["session_id"])
	if frozen_mode != str(preview["mode"]):
		# 调用方给的 mode 与世界不符：明确拒绝，不静默切换参与方式
		_refresh_bar()
		return
	if bool(preview["in_range"]):
		_commit(frozen_mode, frozen_session)
		return
	_approach(frozen_mode, frozen_session)


func request_behavior_chat() -> void:
	request_behavior(KIND_CHAT)


## 递纸条（§8.6）：以选中的同学为**被说的人**写一张纸条，投给座位相邻或已走近的人。
## 玩家只决定「说的是谁」——**写什么内容、递给谁由内核按写者自己的关系决定**，不做内容编辑。
func request_behavior_note() -> void:
	if _core == null or _selected < 0 or _state != STATE_SELECTED:
		return
	var result: Dictionary = _core.player_action("pass_note", _selected)
	if not bool(result.get("ok", false)):
		if _hud != null:
			_hud.show_status(_note_reason(str(result.get("error", ""))))
		_refresh_bar()
		return
	if _hud != null:
		_hud.show_status("纸条塞出去了。")
	_selected = -1
	_clear_armed_state()
	_set_state(STATE_IDLE)


## 纸条的两次决策（§21.2.9）：先看不看，看完再决定去向。内核是唯一事实源。
func _on_note_choice(action: StringName) -> void:
	if _core == null or _note == null:
		return
	match action:
		&"skip_forward":
			_core.respond_note(false, true)
			_note.close()
		&"skip_destroy":
			_core.respond_note(false, false)
			_note.close()
		&"read":
			# 「看」会打断当前动作并占一点时间；纸条仍在手上，等第二步决定去向
			_core.read_note()
			var row: Dictionary = _core.note_pending_for_player()
			_note.show_after_read(int(row.get("tone", 1)))
		&"destroy":
			_core.finish_note(false, false)
			_note.close()
		&"forward":
			_core.finish_note(true, false)
			_note.close()
		&"report":
			# 只能**当场**举报（撕掉之后不能再举）：被举报的是上一个递给我的人（§8.2）
			_core.finish_note(false, true)
			if _hud != null:
				_hud.show_status("你把纸条交给了老师。")
			_note.close()


## 纸条到手（§8.6）：**不打断当前动作**，只在界面角落提示，等玩家自己做选择。
func _poll_note() -> void:
	if _core == null or _note == null:
		return
	var pending: Dictionary = _core.note_pending_for_player()
	if pending.is_empty():
		if _note.is_open():
			_note.close()
		return
	if _note.is_open():
		return
	if bool(pending.get("read", false)):
		_note.show_after_read(int(pending.get("tone", 1)))
	else:
		_note.show_offer()


## 递纸条的可用性**预览**（真正的裁决在内核 `player_action`）：
## 上课段也能用（纸条是上课唯一允许的动作），但需坐位相邻或已走近、自己此刻没在忙。
func _note_ok(index: int) -> bool:
	if _core == null or index < 0 or not bool(_core._allowed("pass_note")):
		return false
	var me := int(_core.node_count()) - 1
	if _core.is_moving(me) or not str(_core.activity_of(me)).is_empty():
		return false
	if int(_core._busy_until[me]) > int(_core._global_tick):
		return false
	return bool(_preview().get("in_range", false))


func _note_hint(index: int) -> String:
	if _core == null:
		return ""
	if _note_ok(index):
		return "写一张纸条，说说%s（写什么由你与他的关系决定）" % _display_name(index)
	if not bool(_core._allowed("pass_note")):
		return "现在不能传纸条"
	var me := int(_core.node_count()) - 1
	if _core.is_moving(me) or not str(_core.activity_of(me)).is_empty():
		return "你正忙着"
	return "先走近一点再递"


## 内核错误码 → 一句人话（纸条侧；不暴露任何隐藏数值）
func _note_reason(error: String) -> String:
	match error:
		"player_busy":
			return "你正忙着"
		"phase_not_allowed":
			return "现在不能传纸条"
		"target_unavailable":
			return "现在递不过去"
		"invalid_target", "unknown_kind":
			return "现在没法传纸条"
	return "现在没法传纸条"


## 取消尚未提交的接近请求（选中 / 接近阶段可取消；提交后不撤销结果）。
## 状态回到 Idle（计划 §6：Approaching → Idle: 取消／不可达／失去权限）。
func cancel_pending(reason: StringName) -> void:
	if _state == STATE_APPROACHING and _player != null and _request_id >= 0:
		_player.cancel_request_movement(_request_id, reason)
		return
	_request_id = -1
	if _state == STATE_SELECTED or _state == STATE_APPROACHING or _state == STATE_VALIDATING:
		_selected = -1
		_clear_armed_state()
		_set_state(STATE_IDLE)


## 只读状态快照（测试与调试用；不含任何隐藏矩阵）。
func state_snapshot() -> Dictionary:
	return {
		"state": str(_state),
		"selected": _selected,
		"request_id": _request_id,
		"mode": _mode,
		"session_id": _session_id,
		"accepted": bool(_packet.get("accepted", false)) if not _packet.is_empty() else false,
	}


func current_state() -> StringName:
	return _state


# ------------------------------------------------------------------ 状态机


func _set_state(state: StringName) -> void:
	if _state == state:
		return
	_state = state
	state_changed.emit(state)


## 已经提交、结果不再由玩家撤销的阶段。
func _is_committed() -> bool:
	return _state == STATE_ACTIVE or _state == STATE_PEN


func _refresh_bar() -> void:
	if _bar == null or _core == null:
		return
	_bar.refresh(_bar_states())
	if _selected >= 0:
		_bar.show_target(_selected, _display_name(_selected), str(_core.activity_of(_selected)))
	else:
		_bar.show_hint("先在右边点一个动作")


## 行为栏每项的状态：只有本批实做的动作给出状态，其余由栏做「还没做」占位灰置。
func _bar_states() -> Dictionary:
	var states := {}
	for kind in PLAYER_TARGET_KINDS + PLAYER_SELF_KINDS:
		var ok := _can_do(kind)
		states[StringName(kind)] = {"ok": ok, "reason": "" if ok else _action_reason_of(kind)}
	return states


## 「现在能不能做这个动作」—— 只看玩家自身与相位（不含目标：目标在点人之后才校验）。
func _can_do(kind: String) -> bool:
	var me := int(_core.node_count()) - 1
	if bool(_core._sleeping[me]) or _core.is_moving(me):
		return false
	if int(_core._busy_until[me]) > int(_core._global_tick):
		return false
	return bool(_core._allowed(kind))


func _action_reason_of(kind: String) -> String:
	var me := int(_core.node_count()) - 1
	if bool(_core._sleeping[me]):
		return "你睡着了"
	if _core.is_moving(me):
		return "先停下再动手"
	if int(_core._busy_until[me]) > int(_core._global_tick):
		return "你正忙着"
	if not bool(_core._allowed(kind)):
		return "上课期间不能做这个"
	return "现在做不了"


## 内核错误码 → 一句人话（不暴露任何隐藏数值）。
func _action_reason(error: String) -> String:
	match error:
		"player_busy":
			return "你正忙着"
		"phase_not_allowed":
			return "上课期间不能做这个"
		"not_in_seat":
			return "回到自己座位上才能学习"
		"target_unavailable":
			return "现在没法对他做这个"
		"invalid_target", "unknown_kind":
			return "现在做不了"
	return "现在做不了"


## 动作提交成功：清掉已选动作与已选对象，回 Idle。
func _finish_action() -> void:
	_clear_armed_state()
	_selected = -1
	_set_state(STATE_IDLE)
	_refresh_bar()


## 只清掉「已选动作」（取消 / 打断 / 收尾时用，不动世界状态）。
func _clear_armed_state() -> void:
	_armed_kind = StringName("")
	if _bar != null:
		_bar.clear_armed()


func _preview() -> Dictionary:
	if _core == null or _selected < 0:
		return {"ok": false, "error": "no_selection"}
	return _core.preview_player_interaction(KIND_CHAT, _selected)


func _display_name(index: int) -> String:
	if index < 0 or _core == null:
		return "同学"
	if int(_core.node_count()) - 1 == index:
		return "我"
	var alias := str(_core.alias(index))
	return alias if not alias.is_empty() else "同学"


# ------------------------------------------------------------------ 接近


func _approach(mode: String, session_id: int) -> void:
	if _player == null:
		return
	var targets := _approach_targets(mode, session_id)
	var plan := _player.plan_approach(targets, _chat_range())
	if not bool(plan.get("ok", false)):
		if _hud != null:
			_hud.show_status("走不过去：%s" % str(plan.get("error", "")))
		return
	var request_id := _new_request_id()
	if not _player.follow_path(request_id, plan["path"]):
		if _hud != null:
			_hud.show_status("接近失败，请重新选择")
		return
	_request_id = request_id
	_mode = mode
	_session_id = session_id
	_set_state(STATE_APPROACHING)
	_clear_armed_state()
	if _hud != null:
		_hud.show_status("正在走向%s" % _display_name(_selected), 3.0)


## 接近的目标点：发起 = 目标一人；加入 = **全体原成员**（必须在所有成员范围内站稳）。
func _approach_targets(mode: String, session_id: int) -> Array:
	var out: Array = []
	if mode == MODE_JOIN and session_id >= 0:
		for member in _core.get_active_sessions():
			if int(member["session_id"]) != session_id:
				continue
			for index in member["members"]:
				var position: Vector2 = _core.position_of(int(index))
				out.append(Vector3(position.x, 0.0, position.y))
		return out
	var position: Vector2 = _core.position_of(_selected)
	out.append(Vector3(position.x, 0.0, position.y))
	return out


func _new_request_id() -> int:
	if _core == null:
		return -1
	return int(_core.next_player_request_id())


func _chat_range() -> float:
	# 范围口径只有一个来源：内核注入的交互几何参数
	if _core == null:
		return 1.2
	return float(_core._player_interactions.chat_range())


# ------------------------------------------------------------------ 提交与演出


## 提交（request_id 沿用接近阶段那一个：一次尝试只有一个编号）。
func _commit(mode: String, session_id: int, request_id: int = -1) -> void:
	var use_id := request_id if request_id > 0 else _new_request_id()
	var packet: Dictionary = _core.commit_player_interaction(
		use_id, KIND_CHAT, _selected, mode, session_id
	)
	if not bool(packet.get("ok", false)):
		# 最终校验失败：停在原地，显示原因，不结算、不扣占用
		_request_id = -1
		_set_state(STATE_SELECTED)
		_refresh_bar()
		if _hud != null:
			_hud.show_status("对方位置／活动变了，请重新选择")
		return
	_request_id = use_id
	_mode = mode
	_session_id = int(packet.get("session_id", -1))
	_packet = packet
	_clear_armed_state()
	if mode == MODE_JOIN:
		_begin_pen()
	else:
		_set_state(STATE_ACTIVE)
		_show_active()


## 转笔：同一帧内复查控制权限 → 对齐位置 → hold 世界 → 播放已锁定结果。
func _begin_pen() -> void:
	_set_state(STATE_PEN)
	if _clock != null and not _pen_hold:
		_clock.hold(PEN_HOLD)
		_pen_hold = true
	# 圈与气泡都按 request_id 隐藏这个「未揭晓」的成员，原组继续可见
	_hide_player_until_revealed()
	if _hud != null:
		_hud.present_locked_result(_packet)
	else:
		_on_result_revealed(_request_id)


func _hide_player_until_revealed() -> void:
	var index := int(_core.node_count()) - 1
	if _rings != null:
		_rings.hide_member(index)
	if _bubbles != null:
		_bubbles.hide_member(index)


func _show_player_after_reveal() -> void:
	var index := int(_core.node_count()) - 1
	if _rings != null:
		_rings.show_member(index)
	if _bubbles != null:
		_bubbles.show_member(index)


func _release_pen_hold() -> void:
	if _pen_hold and _clock != null:
		_clock.release(PEN_HOLD)
	_pen_hold = false


## 揭晓（笔的演出结束或玩家跳过）：此时才允许任何组件暴露结果。
func _on_result_revealed(request_id: int) -> void:
	if request_id != _request_id:
		return
	_release_pen_hold()
	_show_player_after_reveal()
	if bool(_packet.get("accepted", false)):
		_set_state(STATE_ACTIVE)
		_show_active()
	else:
		_handle_rejection()


## 拒绝收尾：拒绝不产生占用，表现层直接显示反馈并回到 Idle，玩家立即可移动。
func _handle_rejection() -> void:
	if _hud != null:
		_hud.clear_active()
	if _emotion != null:
		var effects: Dictionary = _packet.get("player_effects", {})
		var stress := 0.0
		if _core != null:
			stress = float(_core.stress(int(_core.node_count()) - 1))
		_emotion.show_emotion(_emotion.pick_emotion(effects, stress))
	if _hud != null:
		_hud.show_status("没能加入聊天")
	_recent_request_id = _request_id
	_request_id = -1
	_packet = {}
	_selected = -1
	_set_state(STATE_IDLE)


func _show_active() -> void:
	if _hud == null:
		return
	_hud.show_active(_packet)


# ------------------------------------------------------------------ 移动回调


func _on_actor_picked(index: int) -> void:
	select_actor(index)


func _on_ground_clicked(_point: Vector3) -> void:
	if _is_committed():
		return
	cancel_pending(&"ground_click")
	_selected = -1
	_set_state(STATE_IDLE)
	_clear_armed_state()


func _on_request_arrived(request_id: int) -> void:
	if request_id != _request_id:
		return
	_set_state(STATE_VALIDATING)
	# 到达后**再次检查**目标与（加入时的）原会话；失败就停在这里，不结算
	_commit(_mode, _session_id, request_id)


func _on_request_cancelled(request_id: int, reason: StringName) -> void:
	if request_id != _request_id:
		return
	_request_id = -1
	_selected = -1
	_clear_armed_state()
	_set_state(STATE_IDLE)
	if _hud != null and str(reason) == "lost_control":
		_hud.show_status("被打断了")


func _on_request_failed(request_id: int, reason: StringName) -> void:
	if request_id != _request_id:
		return
	_request_id = -1
	_set_state(STATE_SELECTED if _selected >= 0 else STATE_IDLE)
	if _hud != null:
		_hud.show_status("走不过去（%s），请重新选择" % str(reason))


# ------------------------------------------------------------------ 内核通知


## 只处理带 request_id 的玩家通知；圈 / 气泡 / 线索全部走这一条入口。
func _on_event_happened(payload: Dictionary) -> void:
	var kind := str(payload.get("kind", ""))
	# 观察结果（§10.3.1）：只读信息进情报日志，不提交任何行为
	if kind == "observe":
		if _hud != null:
			_hud.show_intel(payload.get("clues", []))
		return
	if not kind.begins_with("player_"):
		return
	var request_id: int = int(payload.get("request_id", -1))
	var intel := kind == "player_intel_received"
	if request_id != _request_id and not (intel and request_id == _recent_request_id):
		return
	match kind:
		"player_intel_received":
			if _hud != null:
				_hud.show_intel([payload.get("clue", {})])
		"player_interaction_finished":
			_on_finished(payload)
		"player_interaction_interrupted":
			_on_interrupted(payload)


func _on_finished(payload: Dictionary) -> void:
	var outcome := str(payload.get("outcome", ""))
	if _hud != null:
		_hud.clear_active()
	if _emotion != null:
		var effects: Dictionary = payload.get("player_effects", {})
		var stress := 0.0
		if _core != null:
			stress = float(_core.stress(int(_core.node_count()) - 1))
		_emotion.show_emotion(_emotion.pick_emotion(effects, stress))
	if outcome == "join_rejected" and _hud != null:
		_hud.show_status("没能加入聊天")
	_recent_request_id = _request_id
	_request_id = -1
	_packet = {}
	_selected = -1
	_set_state(STATE_IDLE)


func _on_interrupted(payload: Dictionary) -> void:
	if _state == STATE_PEN:
		# 还没揭晓就被打断：收掉笔、释放自己的 hold，不再发完成类信息
		if _hud != null:
			_hud.clear()
		_release_pen_hold()
		_show_player_after_reveal()
	elif _hud != null:
		_hud.clear_active()
		_hud.show_status("被铃声打断了")
	if _emotion != null:
		var effects: Dictionary = payload.get("player_effects", {})
		_emotion.show_emotion(_emotion.pick_emotion(effects, 0.0))
	_request_id = -1
	_packet = {}
	_selected = -1
	_set_state(STATE_IDLE)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Esc：取消**尚未提交**的接近请求；已提交的结果不受影响（暂停菜单由教室打开）
	if _state == STATE_SELECTED or _state == STATE_APPROACHING:
		cancel_pending(&"escape")
		_clear_armed_state()
		_selected = -1
		_set_state(STATE_IDLE)


# ------------------------------------------------------------------ 每帧


func _process(delta: float) -> void:
	# 纸条提示优先于菜单刷新：它**不打断**正在做的事，任何时候都可能到手
	_poll_note()
	if _state != STATE_SELECTED or _bar == null:
		return
	_bar_timer += delta
	if _bar_timer < BAR_REFRESH_SECONDS:
		return
	_bar_timer = 0.0
	_refresh_bar()


func _seconds_per_tick() -> float:
	if _clock == null or not is_instance_valid(_clock):
		return 1.0
	var snapshot := _clock.snapshot()
	var left := int(snapshot.get("tick_count", 0)) - int(snapshot.get("tick_in_phase", 0))
	if left <= 0:
		return 1.0
	return float(snapshot.get("remaining_seconds", 0.0)) / float(left)


func _remaining_seconds() -> float:
	if _clock == null or not is_instance_valid(_clock):
		return 0.0
	return float(_clock.snapshot().get("remaining_seconds", 0.0))


func _travel_seconds(index: int) -> float:
	if _player == null or _core == null:
		return 0.0
	var distance: Vector2 = _core.position_of(index)
	var mine: Vector2 = _core.position_of(int(_core.node_count()) - 1)
	var speed := maxf(_player.speed(), 0.001)
	return distance.distance_to(mine) / speed


func _phase_ok() -> bool:
	if _clock == null or not is_instance_valid(_clock):
		return true
	var snapshot := _clock.snapshot()
	return (
		str(snapshot.get("mode", "")) == SimulationClock.MODE_RUNNING
		and bool(snapshot.get("player_control", true))
	)
