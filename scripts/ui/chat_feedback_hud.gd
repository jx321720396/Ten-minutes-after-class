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

const STYLE_TABLE := "ui/chat_feedback_style"
const PEN_TEXTURE := "res://assets/textures/ui/interaction/pen.png"
const COLOR_PAPER := Color(0.98, 0.96, 0.90, 0.94)
const COLOR_INK := Color(0.13, 0.16, 0.14)
const COLOR_SUB := Color(0.34, 0.38, 0.35)
const COLOR_ACCEPT := Color(0.16, 0.46, 0.30)
const COLOR_REJECT := Color(0.66, 0.30, 0.24)

## 轴的中文名（线索文案用；只三个轴）
const AXIS_NAMES := {"affinity": "好感", "hostility": "敌对", "trust": "信任"}

var _pen_card: PanelContainer = null
var _pen: TextureRect = null
var _pen_text: Label = null
var _progress_card: PanelContainer = null
var _progress_text: Label = null
var _progress_bar: ProgressBar = null
var _toast: Label = null
var _history: PanelContainer = null
var _history_list: VBoxContainer = null

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


func _ready() -> void:
	_load_style()
	_build_ui()
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

## 锁定结果并播放转笔：起势 → 旋转 → 收尾 → **揭晓**（此时才发 result_revealed）。
## packet 是内核的提交包（含 accepted / p_belief / mode）。
func present_locked_result(packet: Dictionary) -> void:
	if str(packet.get("mode", "")) != "join":
		# 发起新聊天没有掷骰，不该转笔
		return
	_pending = packet.duplicate(true)
	_revealed = -1
	_pen_card.visible = true
	_pen_card.modulate.a = 1.0
	_pen_text.text = "我的把握 %d%%\n（根据目前了解估计）" % roundi(float(packet.get("p_belief", 0.0)) * 100.0)
	_pen.modulate = Color(1, 1, 1, 0)
	_pen.rotation = 0.0
	_pen.scale = Vector2.ONE
	var size := Vector2(_pen_size, _pen_size * 0.5)
	_pen.size = size
	_pen.pivot_offset = size * 0.5
	_pen.position = Vector2.ZERO
	if _pen_tween != null and _pen_tween.is_valid():
		_pen_tween.kill()
	_pen_tween = create_tween()
	_pen_tween.tween_property(_pen, "modulate:a", 1.0, _windup)
	_pen_tween.parallel().tween_property(_pen, "rotation", -0.5, _windup)
	_pen_tween.tween_property(_pen, "rotation", TAU * 2.5, _spin).set_trans(Tween.TRANS_LINEAR)
	_pen_tween.tween_property(_pen, "rotation", TAU * 3.0, _settle)
	_pen_tween.tween_callback(_reveal_result)
	_pen_tween.tween_interval(_result)
	_pen_tween.tween_property(_pen, "modulate:a", 0.0, 0.15)
	_pen_tween.tween_callback(func() -> void: _pen_card.visible = false)


## 跳过：提前揭晓**同一个已锁定结果**（不重复 commit、不缩短真实占用）。
func skip() -> void:
	if _pending.is_empty() or _revealed >= 0:
		return
	if _pen_tween != null and _pen_tween.is_valid():
		_pen_tween.kill()
	_reveal_result()
	_pen_card.visible = false


func is_presenting() -> bool:
	return not _pending.is_empty() and _revealed < 0


func revealed_request_id() -> int:
	return _revealed


## 聊天进行中的进度卡（进入会话后调用；每帧按内核 tick 自行推进）。
func show_active(packet: Dictionary) -> void:
	_active = packet.duplicate(true)
	_progress_card.visible = true
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
	return "第 %d 天 · %s 透露：他对%s的%s是 %.0f（记录于当时，关系可能变化）" % [
		day, source, subject, axis, float(clue.get("value", 0.0))
	]


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
	_pending = {}
	_revealed = -1
	if _pen_tween != null and _pen_tween.is_valid():
		_pen_tween.kill()
	_pen_card.visible = false
	clear_active()
	_toast.text = ""
	_toast_left = 0.0


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left = maxf(0.0, _toast_left - delta)
		_toast.modulate.a = minf(1.0, _toast_left / 0.6)
		if _toast_left <= 0.0:
			_toast.text = ""
	if _active.is_empty():
		return
	var seconds := _remaining_seconds()
	var total := float(_active.get("duration_ticks", 0)) * _seconds_per_tick()
	_progress_bar.value = 0.0 if total <= 0.0 else clampf(100.0 * (1.0 - seconds / total), 0.0, 100.0)
	_progress_text.text = "%s · 还剩 %.0f 秒" % [_active_label, seconds]


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
	var ticks := int(_active.get("end_tick", 0)) - _current_tick()
	if ticks < 0:
		ticks = 0
	return float(ticks) * _seconds_per_tick()


func _current_tick() -> int:
	if _clock != null and is_instance_valid(_clock):
		return int(_clock.snapshot().get("global_tick", 0))
	if _core != null:
		return int(_core.global_tick())
	return 0


# ------------------------------------------------------------------ 内部

func _reveal_result() -> void:
	if _pending.is_empty():
		return
	var request_id := int(_pending.get("request_id", -1))
	if _revealed == request_id:
		return
	_revealed = request_id
	var accepted := bool(_pending.get("accepted", false))
	_pen_text.text = "加入了聊天" if accepted else "没能加入聊天"
	_pen_text.add_theme_color_override("font_color", COLOR_ACCEPT if accepted else COLOR_REJECT)
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
	var font := SystemFont.new()
	font.font_names = PackedStringArray(
		["Microsoft YaHei", "微软雅黑", "SimHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"]
	)
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
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	_pen_card.add_child(column)
	var spinner := Control.new()
	spinner.name = "Spinner"
	spinner.custom_minimum_size = Vector2(_pen_size, _pen_size * 0.5)
	spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pen = TextureRect.new()
	_pen.name = "Pen"
	_pen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pen.pivot_offset = Vector2.ZERO
	_pen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(PEN_TEXTURE):
		_pen.texture = load(PEN_TEXTURE)
	spinner.add_child(_pen)
	_pen_text = _make_label(18, COLOR_INK)
	column.add_child(spinner)
	column.add_child(_pen_text)
	_pen_card.visible = false

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
	var progress_column := VBoxContainer.new()
	progress_column.name = "Column"
	_progress_card.add_child(progress_column)
	_progress_text = _make_label(18, COLOR_INK)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(280.0, _bar_height)
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


func _load_style() -> void:
	for row in ConfigLoader.new().get_table(STYLE_TABLE).get("rows", []):
		var value := float(str(row.get("value", "0")))
		match str(row.get("param", "")):
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
