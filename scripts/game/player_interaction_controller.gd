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
## 加入闲聊多一段 PenPresenting →（接受）Active /（拒绝）RejectedBusy；
## 提交后的 Active / PenPresenting / RejectedBusy **禁止新行为与移动**，Esc 只打开暂停菜单。

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
## 菜单刷新频率（世界在推进，状态会变）
const MENU_REFRESH_SECONDS := 0.25

var _core: Variant = null
var _player: PlayerController = null
var _actors: Node3D = null
var _clock: SimulationClock = null
var _menu: PlayerInteractionMenu = null
var _hud: ChatFeedbackHUD = null
var _rings: ActivityRingPresenter = null
var _bubbles: ChatActivityBubble = null
var _emotion: PlayerEmotionFeedback = null

var _state: StringName = STATE_IDLE
var _selected := -1
var _request_id := -1
## 刚收尾的请求编号：线索通知可能紧跟完成通知之后到，只用于匹配情报，不用于提交
var _recent_request_id := -1
var _mode := ""
var _session_id := -1
var _packet: Dictionary = {}
var _pen_hold := false
var _menu_timer := 0.0


func _ready() -> void:
	set_process_unhandled_input(true)
	# EventBus 是 autoload：等一帧再连，保证场景装载顺序不影响接线
	call_deferred("_connect_sources")


# ------------------------------------------------------------------ 绑定

## 计划 §9 的公共接口：一次绑定内核 / 玩家 / 人物 / 时钟。
func bind_sources(core: Variant, player: PlayerController, actors: Node3D, clock: SimulationClock) -> void:
	_core = core
	_player = player
	_actors = actors
	_clock = clock
	_connect_sources()


## 反馈组件（可选，缺失也不影响玩法逻辑）。
func bind_feedback(
	menu: PlayerInteractionMenu,
	hud: ChatFeedbackHUD,
	rings: ActivityRingPresenter,
	bubbles: ChatActivityBubble,
	emotion: PlayerEmotionFeedback
) -> void:
	_menu = menu
	_hud = hud
	_rings = rings
	_bubbles = bubbles
	_emotion = emotion


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
	if _menu != null and not _menu.chat_requested.is_connected(request_behavior_chat):
		_menu.chat_requested.connect(request_behavior_chat)
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
	_open_menu()


## 请求一次闲聊（`kind` 固定 chat；`mode` 只在选择时解析一次，之后必须用冻结值提交）。
func request_behavior(kind: String, mode: String = "auto") -> void:
	if kind != KIND_CHAT or _selected < 0:
		return
	if _state != STATE_SELECTED:
		return
	var preview := _preview()
	if not bool(preview.get("ok", false)) or not bool(preview.get("eligible", false)):
		_open_menu()
		return
	var frozen_mode := str(preview["mode"]) if mode == "auto" else mode
	var frozen_session := int(preview["session_id"])
	if frozen_mode != str(preview["mode"]):
		# 调用方给的 mode 与世界不符：明确拒绝，不静默切换参与方式
		_open_menu()
		return
	if bool(preview["in_range"]):
		_commit(frozen_mode, frozen_session)
		return
	_approach(frozen_mode, frozen_session)


func request_behavior_chat() -> void:
	request_behavior(KIND_CHAT)


## 取消尚未提交的接近请求（选中 / 接近阶段可取消；提交后不撤销结果）。
## 状态回到 Idle（计划 §6：Approaching → Idle: 取消／不可达／失去权限）。
func cancel_pending(reason: StringName) -> void:
	if _state == STATE_APPROACHING and _player != null and _request_id >= 0:
		_player.cancel_request_movement(_request_id, reason)
		return
	_request_id = -1
	if _state == STATE_SELECTED or _state == STATE_APPROACHING or _state == STATE_VALIDATING:
		_selected = -1
		if _menu != null:
			_menu.close()
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
	return _state == STATE_ACTIVE or _state == STATE_PEN or _state == STATE_REJECTED


func _open_menu() -> void:
	if _menu == null or _selected < 0 or _is_committed():
		return
	_menu.open(_selected, _menu_info(_selected))


## 菜单要的所有信息：公开状态 + 只读预览 + 用时估计（tick 用时钟换算成秒）。
func _menu_info(index: int) -> Dictionary:
	var preview := _preview()
	var info := {
		"name": _display_name(index),
		"activity": str(_core.activity_of(index)),
		"moving": bool(_core.is_moving(index)),
		"sleeping": bool(_core._sleeping[index]),
		"mode": str(preview.get("mode", MODE_START)),
		"eligible": bool(preview.get("eligible", false)),
		"in_range": bool(preview.get("in_range", false)),
		"reason": str(preview.get("reason", "")),
		"phase_ok": _phase_ok(),
		"chat_seconds": float(preview.get("duration_ticks", 0)) * _seconds_per_tick(),
		"travel_seconds": _travel_seconds(index),
		"remaining_seconds": _remaining_seconds(),
	}
	return info


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
	if _menu != null:
		_menu.close()
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
		_open_menu()
		if _hud != null:
			_hud.show_status("对方位置／活动变了，请重新选择")
		return
	_request_id = use_id
	_mode = mode
	_session_id = int(packet.get("session_id", -1))
	_packet = packet
	if _menu != null:
		_menu.close()
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
		_set_state(STATE_REJECTED)
		if _hud != null:
			_hud.clear_active()


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
	if _menu != null:
		_menu.close()


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
	if _menu != null:
		_menu.close()
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
		if _menu != null:
			_menu.close()
		_selected = -1
		_set_state(STATE_IDLE)


# ------------------------------------------------------------------ 每帧

func _process(delta: float) -> void:
	if _state != STATE_SELECTED or _menu == null:
		return
	_menu_timer += delta
	if _menu_timer < MENU_REFRESH_SECONDS:
		return
	_menu_timer = 0.0
	_open_menu()


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
	return str(snapshot.get("mode", "")) == SimulationClock.MODE_RUNNING and bool(
		snapshot.get("player_control", true)
	)
