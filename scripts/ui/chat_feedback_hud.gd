class_name ChatFeedbackHUD
extends CanvasLayer
## 闲聊的统一反馈入口（表现层，只读）：转笔判定、聊天进度、线索提示与本局历史列表。
##
## 依据：主文档 §10.32（同一次判定两种呈现）、§10.5 第 5 条（玩家专属透露）；
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §7、§8.4。
##
## 三条约束：
##   ① **只对「加入闲聊」转笔**：发起新聊天合法即开始，不额外掷骰、不显示虚假成功率；
##   ② 一次只有**一次**揭晓：`result_revealed(request_id)` 是唯一放行信号，界面从这里之后
##      才允许任何组件暴露 accepted；跳过只是提前揭晓**同一个已锁定结果**，不重复 commit；
##   ③ 时钟换算：进度与剩余时间一律用**当前相位的时钟配置**把 tick 换算成秒，
##      不把真实秒数与游戏内十分钟混为一谈，也不显示实现字段。

signal result_revealed(request_id: int)

const CampusTheme := preload("res://scripts/ui/campus_theme.gd")
const PenWheel := preload("res://scripts/ui/pen_probability_wheel.gd")
const RESULT_HOLD := &"pen_result_card"
const STYLE_TABLE := "ui/chat_feedback_style"
const PEN_TEXTURE := "res://assets/textures/ui/interaction/pen.png"
const COLOR_PAPER := Color(0.98, 0.96, 0.90, 0.94)
const COLOR_INK := Color(0.13, 0.16, 0.14)
const COLOR_SUB := Color(0.34, 0.38, 0.35)
const COLOR_ACCEPT := Color(0.16, 0.46, 0.30)
const COLOR_REJECT := Color(0.66, 0.30, 0.24)

## 轴的中文名（线索文案用；只三个轴）
const AXIS_NAMES := {"affinity": "好感", "hostility": "敌对"}

var _pen_card: PanelContainer = null
var _pen: TextureRect = null
var _pen_text: Label = null
var _pen_button: Button
var _pen_result: Label
var _pen_hint: Label
var _pen_wheel: PenWheel
var _pen_backdrop: ColorRect
var _pen_state := "ready"
var _rest_layer := 0
var _progress_card: PanelContainer = null
var _progress_text: Label = null
var _progress_portrait: TextureRect
var _activity_start := -1
var _activity_key := ""
var _progress_bar: ProgressBar = null
var _toast: Label = null
var _history: PanelContainer = null
var _history_list: VBoxContainer = null
var _invitation_card: PanelContainer = null
var _invitation_text: Label = null
var _invitation_accept: Button = null
var _invitation_reject: Button = null
var _invitation_id := -1

var _clock: SimulationClock = null
var _core: Variant = null
## 正在播放的笔（用于跳过与「不重复播放」判定）
var _pen_tween: Tween = null
var _pending: Dictionary = {}
var _revealed := -1
var _active: Dictionary = {}
var _active_label := ""
var _history_lines: Array[String] = []
var _toast_left := 0.0
## 呈现参数（全部来自 data/ui/chat_feedback_style.csv）
var _windup := 0.15
var _spin := 0.65
var _settle := 0.2
var _result := 0.4
var _pen_size := 180.0
var _toast_seconds := 4.0
var _bar_height := 10.0
var _invitation_margin := 0.0


func _ready() -> void:
	_rest_layer = layer
	_load_style()
	_build_ui()
	CampusTheme.apply_tree(self)
	var pen_paper := CampusTheme.paper_card()
	pen_paper.content_margin_top = CampusTheme.settings().pen_check.content_top
	pen_paper.content_margin_bottom = CampusTheme.settings().pen_check.content_bottom
	_pen_card.add_theme_stylebox_override("panel", pen_paper)
	CampusTheme.button(_pen_button, true)
	_invitation_card.add_theme_stylebox_override("panel", CampusTheme.paper_card())
	_invitation_card.custom_minimum_size = Vector2(
		CampusTheme.settings().event_card_width, CampusTheme.settings().event_card_height
	)
	var paper := CampusTheme.box("paper", "teal")
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(int(CampusTheme.settings().progress_padding))
	_progress_card.add_theme_stylebox_override("panel", paper)
	for state in ["background", "fill"]:
		var bar_style := _progress_bar.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		bar_style.set_content_margin_all(0)
		bar_style.shadow_size = 0
		_progress_bar.add_theme_stylebox_override(state, bar_style)
	set_process_unhandled_input(true)


## 情报日志是「界面、不占时间」（§12.3）：Tab 随时翻看，上课段也能看。
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.keycode != KEY_TAB or key.echo:
		return
	toggle_history()
	get_viewport().set_input_as_handled()


func bind_clock(clock: SimulationClock) -> void:
	_clock = clock


func bind_core(core: Variant) -> void:
	_core = core


# ------------------------------------------------------------------ 对外接口


## 锁定结果，等待点击开始；再次点击收尾揭晓，不自动停止或重新判定。
## packet 是内核的提交包（含 accepted / p_belief / mode）。
func present_locked_result(packet: Dictionary) -> void:
	if str(packet.get("mode", "")) != "join":
		# 发起新聊天没有掷骰，不该转笔
		return
	if is_presenting():
		return
	clear_pen()
	_pending = packet.duplicate(true)
	_revealed = -1
	_pen_state = "ready"
	layer = int(CampusTheme.settings().pen_check.modal_layer)
	_pen_backdrop.show()
	_pen_card.visible = true
	_pen_card.modulate.a = 1.0
	_pen_text.text = "我的把握 %d%%\n（根据目前了解估计）" % roundi(float(packet.get("p_belief", 0.0)) * 100.0)
	_pen_wheel.set_probability(float(packet.get("p_belief", 0.0)))
	_pen_button.text = "开始转笔"
	_pen_button.disabled = false
	_pen_hint.text = "点击开始，再次点击揭晓"
	_pen_result.text = ""
	_pen.modulate = Color.WHITE
	_pen.rotation = 0.0
	_pen.scale = Vector2.ONE
	_pen_button.grab_focus()


func _on_pen_pressed() -> void:
	match _pen_state:
		"ready":
			_pen_state = "spinning"
			_pen_button.text = "停下揭晓"
			_pen_hint.text = "再次点击，查看对方的回应"
		"spinning":
			_pen_state = "settling"
			_pen_button.disabled = true
			var target: float = _pen_wheel.result_angle(bool(_pending.get("accepted", false)))
			var angle := _pen.rotation + fposmod(target - _pen.rotation, TAU)
			_pen_tween = create_tween()
			(
				_pen_tween
				. tween_property(_pen, "rotation", angle, _settle)
				. set_trans(Tween.TRANS_QUAD)
				. set_ease(Tween.EASE_OUT)
			)
			_pen_tween.tween_callback(_reveal_result)
		"result":
			clear_pen()


func clear_pen() -> void:
	if _pen_tween != null and _pen_tween.is_valid():
		_pen_tween.kill()
	_pen_state = "ready"
	layer = _rest_layer
	_pending = {}
	if _pen_card != null:
		_pen_card.hide()
	if _pen_backdrop != null:
		_pen_backdrop.hide()
	if is_instance_valid(_clock):
		_clock.release(RESULT_HOLD)


func _exit_tree() -> void:
	clear_pen()


## 跳过：提前揭晓**同一个已锁定结果**（不重复 commit、不缩短真实占用）。
func skip() -> void:
	if _pending.is_empty() or _revealed >= 0:
		return
	if _pen_tween != null and _pen_tween.is_valid():
		_pen_tween.kill()
	_reveal_result()


func is_presenting() -> bool:
	return not _pending.is_empty() and _revealed < 0


func revealed_request_id() -> int:
	return _revealed


## 聊天进行中的进度卡（进入会话后调用；每帧按内核 tick 自行推进）。
func show_active(packet: Dictionary) -> void:
	_active = packet.duplicate(true)
	_progress_card.visible = true
	_progress_bar.visible = true
	var mode := str(packet.get("mode", "start"))
	_active_label = "正在和同学%s" % ("聊天" if mode == "start" else "一起聊")
	_progress_text.text = _active_label


func clear_active() -> void:
	_active = {}
	if _progress_card != null:
		_progress_card.visible = false


## 线索提示（同一 clue_id 只提示一次，重绑界面不重发）。
func show_intel(clues: Array) -> void:
	if clues.is_empty():
		return
	var fresh: Array[String] = []
	for clue in clues:
		var line := format_clue(clue)
		if _history_lines.has(line):
			continue
		_history_lines.append(line)
		fresh.append(line)
		_add_history_label(line)
	if fresh.is_empty():
		return
	_show_toast("\n".join(fresh))


## 线索文案：来源 → 对象、单轴数值、获知时间，并提醒「记录于当时」。
func format_clue(clue: Dictionary) -> String:
	var source := _name_of(int(clue.get("source", -1)))
	var subject := _name_of(int(clue.get("subject", -1)))
	var axis := str(AXIS_NAMES.get(str(clue.get("axis", "")), "关系"))
	var day := int(clue.get("day", 0))
	var value := float(clue.get("value", 0.0))
	return "第 %d 天 · %s 透露：他对%s的%s是 %.0f（记录于当时，关系可能变化）" % [day, source, subject, axis, value]


func toggle_history() -> void:
	_history.visible = not _history.visible


## 一句状态提示（「正在走向某同学」「对方活动变了」等）—— 不是结果，不泄露任何 accepted。
func show_status(text: String, seconds: float = 2.5) -> void:
	_show_toast(text)
	_toast_left = maxf(0.5, seconds)


func history_lines() -> Array[String]:
	return _history_lines.duplicate()


func is_history_visible() -> bool:
	return _history.visible


func progress_percent() -> float:
	return _progress_bar.value


func remaining_seconds() -> float:
	return _remaining_seconds()


## 清屏（切场景 / 退出时调用）：不撤销已经提交的结算，只收掉表现。
func clear() -> void:
	clear_pen()
	_revealed = -1
	if _pen_tween != null and _pen_tween.is_valid():
		_pen_tween.kill()
	_pen_card.visible = false
	clear_active()
	_toast.text = ""
	_toast_left = 0.0
	_invitation_id = -1
	_invitation_card.visible = false


func _process(delta: float) -> void:
	if _pen_state == "spinning":
		_pen.rotation = fposmod(
			(
				_pen.rotation
				+ TAU * float(CampusTheme.settings().pen_check.spin_turns_per_second) * delta
			),
			TAU
		)
	_refresh_invitation()
	_set_activity_portrait()
	if _toast_left > 0.0:
		_toast_left = maxf(0.0, _toast_left - delta)
		_toast.modulate.a = minf(1.0, _toast_left / 0.6)
		if _toast_left <= 0.0:
			_toast.text = ""
	if _active.is_empty():
		_show_current_player_activity()
		return
	var seconds := _remaining_seconds()
	var total := float(_active.get("duration_ticks", 0)) * _seconds_per_tick()
	_progress_bar.value = (
		0.0 if total <= 0.0 else clampf(100.0 * (1.0 - seconds / total), 0.0, 100.0)
	)
	_progress_text.text = "%s · 还剩 %.0f 秒" % [_active_label, seconds]


## 老师版没有「NPC 邀请玩家」机制（2026-10-16 随玩家节点删除）：邀请卡片恒隐藏。
func _refresh_invitation() -> void:
	_invitation_card.visible = false
	_invitation_id = -1


func _respond_invitation(_accepted: bool) -> void:
	_refresh_invitation()


## 没有主动聊天请求时，仍显示玩家被动参与的活动与移动限制。
## 只读内核占用与真实会话，不因缺少 request_id 把被动聊天显示为空闲。
func _show_current_player_activity() -> void:
	if _core == null:
		return
	var me := int(_core.node_count()) - 1
	_progress_card.visible = true
	_progress_bar.visible = false
	if _clock != null and is_instance_valid(_clock):
		var snapshot := _clock.snapshot()
		if bool(snapshot.get("paused", false)):
			_progress_text.text = "当前：转笔判定中" if is_presenting() else "当前：已暂停"
			return
		if not bool(snapshot.get("player_control", false)):
			_progress_text.text = (
				"当前：正在上课 · 暂时不能移动"
				if str(snapshot.get("kind", "")) == "class"
				else "当前：等待结算 · 暂时不能移动"
			)
			return
	if bool(_core._sleeping[me]):
		_progress_text.text = "当前：睡觉中 · 本课间无法移动"
		var phase: Dictionary = _core.time_snapshot()
		_update_activity_progress(
			"sleep", _current_tick() + int(phase.tick_count) - int(phase.tick_in_phase)
		)
		return
	if bool(_core.is_busy(me)):
		var activity := str(_core._busy_act[me])
		var end_tick := int(_core._busy_until[me])
		for session in _core.get_active_sessions():
			if (session["members"] as Array).has(me):
				activity = str(session["kind"])
				end_tick = int(session["end_tick"])
				break
		var label := str(PlayerActionBar.ACTIVITY_NAMES.get(activity, "正在参与同学的活动"))
		if activity == "eat_snack":
			label = "在吃零食（还剩 %d 份）" % int(_core.inventory_of(me)["snacks"])
		if activity == "chat":
			label = "正在和同学聊天"
		var seconds := maxf(0.0, float(end_tick - _current_tick()) * _seconds_per_tick())
		_progress_text.text = "%s · 还剩 %.0f 秒 · 暂时不能移动" % [label, seconds]
		_update_activity_progress(activity, end_tick)
		return
	# 学习态（§8.23）：不占时间槽，所以不会进 is_busy 分支 —— 必须单独认出来，
	# 否则学习中也显示「空闲」，玩家看不出自己在不在学。
	if str(_core.activity_of(me)) == "study":
		_progress_text.text = "当前：学习中 · 正在累积成绩"
		return
	if bool(_core.is_moving(me)):
		_progress_text.text = "当前：走动中"
		return
	if not bool(_core.in_own_seat(me)):
		# 离座时把原因挂在状态行上：点学习被拒不是「没反应」，而是需要回座位
		_progress_text.text = "当前：空闲 · 走回自己座位才能学习"
		return
	_progress_text.text = "当前：空闲 · 可以移动"


# ------------------------------------------------------------------ tick → 秒（只读时钟）


## 当前相位一个 tick 折合多少真实秒（读时钟快照，不自己推算相位）。
func _seconds_per_tick() -> float:
	if _clock == null or not is_instance_valid(_clock):
		return 1.0
	var snapshot := _clock.snapshot()
	var left := int(snapshot.get("tick_count", 0)) - int(snapshot.get("tick_in_phase", 0))
	if left <= 0:
		return 1.0
	var remaining := float(snapshot.get("remaining_seconds", 0.0))
	return remaining / float(left)


func _remaining_seconds() -> float:
	if _active.is_empty():
		return 0.0
	var end_tick := int(_active.get("end_tick", 0))
	# NPC 加入或继续聊天可能延长会话；倒计时必须跟随真实结束点。
	var session_id := int(_active.get("linked_session", _active.get("session_id", -1)))
	for session in _core.get_active_sessions() if _core != null else []:
		if int(session["session_id"]) == session_id:
			end_tick = int(session["end_tick"])
			break
	var ticks := end_tick - _current_tick()
	if ticks < 0:
		ticks = 0
	return float(ticks) * _seconds_per_tick()


func _current_tick() -> int:
	if _clock != null and is_instance_valid(_clock):
		return int(_clock.snapshot().get("global_tick", 0))
	if _core != null:
		return int(_core.global_tick())
	return 0


func _update_activity_progress(activity: String, end_tick: int) -> void:
	var key := activity + str(end_tick)
	if key != _activity_key:
		_activity_key = key
		var duration := int(str(_core._behaviors.get(activity, {}).get("duration", 0)))
		_activity_start = end_tick - duration if duration > 0 else _current_tick()
	_progress_bar.visible = true
	var total := maxi(1, end_tick - _activity_start)
	_progress_bar.value = clampf(
		100.0 * float(_current_tick() - _activity_start) / float(total), 0, 100
	)
	_set_activity_portrait()


func _set_activity_portrait() -> void:
	if _core == null:
		return
	var me := int(_core.node_count()) - 1
	var subject := me
	for session in _core.get_active_sessions():
		if (session.members as Array).has(me):
			for member in session.members:
				if int(member) != me:
					subject = int(member)
					break
	_progress_portrait.texture = null
	if subject == me:
		var scene := get_tree().current_scene
		var actors := scene.get_node_or_null("Actors") if scene != null else null
		if actors != null:
			var actor: Node3D = actors.actor_for(me)
			var sprite := actor.get_node_or_null("Sprite") as Sprite3D if actor != null else null
			if sprite != null and sprite.texture != null:
				var head := AtlasTexture.new()
				head.atlas = sprite.texture
				head.region = Rect2(
					0,
					0,
					sprite.texture.get_width(),
					(
						sprite.texture.get_height()
						* float(CampusTheme.settings().progress_head_fraction)
					)
				)
				_progress_portrait.texture = head
		return
	for row in ConfigLoader.new().get_table("characters/appearance").get("rows", []):
		if str(row.get("id", "")) == str(_core.character_id(subject)):
			var path := "res://assets/textures/character_head/%s.png" % str(row.get("sprite", ""))
			if ResourceLoader.exists(path):
				_progress_portrait.texture = load(path)
			return


# ------------------------------------------------------------------ 内部


func _reveal_result() -> void:
	if _pending.is_empty():
		return
	var request_id := int(_pending.get("request_id", -1))
	if _revealed == request_id:
		return
	_revealed = request_id
	var accepted := bool(_pending.get("accepted", false))
	_pen_state = "result"
	_pen_result.text = "✓ 对方答应了" if accepted else "✕ 对方婉拒了"
	_pen_result.add_theme_color_override("font_color", COLOR_ACCEPT if accepted else COLOR_REJECT)
	_pen_hint.text = "点击继续，返回教室"
	_pen_button.text = "继续"
	_pen_button.disabled = false
	# 原控制器在 result_revealed 时释放演出锁；结果卡单独持有暂停直至继续。
	if is_instance_valid(_clock):
		_clock.hold(RESULT_HOLD)
	result_revealed.emit(request_id)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_left = _toast_seconds


func _name_of(index: int) -> String:
	if _core == null or index < 0:
		return "某同学"
	var alias := str(_core.alias(index))
	if alias.is_empty():
		return "某同学"
	return alias


func _add_history_label(line: String) -> void:
	var label := Label.new()
	label.text = line
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", COLOR_SUB)
	label.add_theme_font_override("font", _font())
	_history_list.add_child(label)


func _font() -> Font:
	var font := preload("res://scripts/ui/game_fonts.gd").regular()

	return font


func _panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PAPER
	box.border_color = COLOR_INK
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(10.0)
	return box


func _make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", _font())
	return label


func _build_ui() -> void:
	var pen_cfg: Dictionary = CampusTheme.settings().pen_check
	_pen_backdrop = ColorRect.new()
	_pen_backdrop.name = "PenBackdrop"
	_pen_backdrop.color = Color(0, 0, 0, float(pen_cfg.backdrop_alpha))
	_pen_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pen_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_pen_backdrop)
	_pen_backdrop.hide()
	_pen_card = PanelContainer.new()
	_pen_card.name = "PenCard"
	_pen_card.add_theme_stylebox_override("panel", _panel_box())
	_pen_card.anchor_left = 0.5
	_pen_card.anchor_right = 0.5
	_pen_card.anchor_top = 0.5
	_pen_card.anchor_bottom = 0.5
	_pen_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pen_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_pen_card)
	_pen_card.custom_minimum_size = Vector2(pen_cfg.card_width, pen_cfg.card_height)
	_pen_card.offset_left = -float(pen_cfg.card_width) / 2.0
	_pen_card.offset_right = float(pen_cfg.card_width) / 2.0
	_pen_card.offset_top = -float(pen_cfg.card_height) / 2.0
	_pen_card.offset_bottom = float(pen_cfg.card_height) / 2.0
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", int(pen_cfg.card_gap))
	_pen_card.add_child(column)
	var title := _make_label(int(pen_cfg.heading_font_size), COLOR_INK)
	title.text = "加入同学的闲聊"
	column.add_child(title)
	_pen_wheel = PenWheel.new()
	_pen_wheel.name = "Spinner"
	_pen_wheel.configure(pen_cfg)
	column.add_child(_pen_wheel)
	_pen = _pen_wheel.pen
	_pen_result = _make_label(int(pen_cfg.result_font_size), COLOR_ACCEPT)
	_pen_result.name = "Result"
	column.add_child(_pen_result)
	_pen_button = Button.new()
	_pen_button.name = "PenButton"
	_pen_button.custom_minimum_size.y = float(pen_cfg.button_height)
	_pen_button.add_theme_font_size_override("font_size", int(pen_cfg.result_font_size))
	_pen_button.add_theme_font_override("font", _font())
	_pen_button.pressed.connect(_on_pen_pressed)
	column.add_child(_pen_button)
	_pen_hint = _make_label(int(pen_cfg.hint_font_size), COLOR_SUB)
	column.add_child(_pen_hint)
	column.add_child(HSeparator.new())
	_pen_text = _make_label(int(pen_cfg.belief_font_size), COLOR_INK)
	column.add_child(_pen_text)
	_pen_card.hide()

	_progress_card = PanelContainer.new()
	_progress_card.name = "ProgressCard"
	_progress_card.add_theme_stylebox_override("panel", _panel_box())
	_progress_card.anchor_top = 1.0
	_progress_card.anchor_bottom = 1.0
	_progress_card.anchor_left = 0.5
	_progress_card.anchor_right = 0.5
	_progress_card.offset_bottom = -28.0
	_progress_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_progress_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_progress_card)
	var cfg := CampusTheme.settings()
	_progress_card.custom_minimum_size = Vector2(cfg.progress_width, cfg.progress_height)
	_progress_card.offset_left = -cfg.progress_width / 2
	_progress_card.offset_right = cfg.progress_width / 2
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", int(cfg.progress_padding))
	_progress_card.add_child(layout)
	_progress_portrait = TextureRect.new()
	_progress_portrait.custom_minimum_size = Vector2.ONE * cfg.progress_portrait
	_progress_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_progress_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layout.add_child(_progress_portrait)
	var progress_column := VBoxContainer.new()
	progress_column.name = "Column"
	progress_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(progress_column)
	_progress_text = _make_label(int(cfg.progress_font_size), COLOR_INK)
	_progress_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0.0, cfg.progress_bar_height)
	_progress_bar.show_percentage = false
	progress_column.add_child(_progress_text)
	progress_column.add_child(_progress_bar)
	_progress_card.visible = false

	_toast = _make_label(16, COLOR_INK)
	_toast.name = "IntelToast"
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.anchor_top = 0.0
	_toast.anchor_bottom = 0.0
	_toast.anchor_left = 1.0
	_toast.anchor_right = 1.0
	_toast.offset_left = -420.0
	_toast.offset_right = -24.0
	_toast.offset_top = 24.0
	_toast.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_toast)

	_history = PanelContainer.new()
	_history.name = "IntelHistory"
	_history.add_theme_stylebox_override("panel", _panel_box())
	_history.anchor_top = 0.0
	_history.anchor_bottom = 0.0
	_history.anchor_left = 1.0
	_history.anchor_right = 1.0
	_history.offset_left = -420.0
	_history.offset_right = -24.0
	_history.offset_top = 96.0
	_history.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_history)
	_history_list = VBoxContainer.new()
	_history_list.name = "List"
	_history_list.add_theme_constant_override("separation", 4)
	_history.add_child(_history_list)
	_history.visible = false
	_build_invitation_ui()


func _build_invitation_ui() -> void:
	_invitation_card = PanelContainer.new()
	_invitation_card.name = "InvitationCard"
	_invitation_card.add_theme_stylebox_override("panel", _panel_box())
	_invitation_card.anchor_left = 0.0
	_invitation_card.anchor_right = 0.0
	_invitation_card.anchor_top = 1.0
	_invitation_card.anchor_bottom = 1.0
	_invitation_card.offset_left = _invitation_margin
	_invitation_card.offset_right = _invitation_margin + CampusTheme.settings().event_card_width
	_invitation_card.offset_bottom = (
		-_invitation_margin
		- CampusTheme.settings().event_card_height
		- CampusTheme.settings().event_stack_gap
	)
	_invitation_card.grow_horizontal = Control.GROW_DIRECTION_END
	_invitation_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_invitation_card)
	var column := VBoxContainer.new()
	_invitation_card.add_child(column)
	_invitation_text = _make_label(16, COLOR_INK)
	column.add_child(_invitation_text)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_invitation_accept = Button.new()
	_invitation_accept.text = "接受"
	_invitation_accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invitation_accept.add_theme_font_override("font", _font())
	_invitation_accept.pressed.connect(_respond_invitation.bind(true))
	buttons.add_child(_invitation_accept)
	_invitation_reject = Button.new()
	_invitation_reject.text = "拒绝"
	_invitation_reject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invitation_reject.add_theme_font_override("font", _font())
	_invitation_reject.pressed.connect(_respond_invitation.bind(false))
	buttons.add_child(_invitation_reject)
	_invitation_card.visible = false


func _load_style() -> void:
	for row in ConfigLoader.new().get_table(STYLE_TABLE).get("rows", []):
		var value := float(str(row.get("value", "0")))
		match str(row.get("param", "")):
			"menu_margin_px":
				_invitation_margin = value
			"pen_windup_seconds":
				_windup = value
			"pen_spin_seconds":
				_spin = value
			"pen_settle_seconds":
				_settle = value
			"pen_result_seconds":
				_result = value
			"pen_size_px":
				_pen_size = value
			"toast_seconds":
				_toast_seconds = value
			"progress_bar_height_px":
				_bar_height = value
