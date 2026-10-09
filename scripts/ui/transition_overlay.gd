class_name TransitionOverlay
extends CanvasLayer
## 转场黑幕（表现层）：上课相位的黑幕呈现与跳过，模拟在黑幕后照常推进。
##
## 依据：主文档 §3.3（上课发酵层）、§3.2（tick 定义）；转场黑幕为 UI 任务
## （2026-10-08 UI 分工：转场黑幕 + 跳过键）。
##
## 职责边界：
##   · 本组件**只做呈现与跳过转发**：不持有时间、不推进 tick、不读写任何矩阵数值；
##   · 「跳过」= 黑幕提前退场，相位仍由 SimulationClock 正常逐 tick 跑完 ——
##     事件一个不少，只是玩家不再看画面（任务要求：跳过不得省略事件发生）；
##   · 黑幕何时出现由内核快照的相位 kind 决定（kind = class 才盖黑幕），
##     不写「第 N 段必然黑幕」的脚本化判断。
##
## 显示口径：
##   · 进入上课相位：「上课了」黑幕，总长约 2 秒（空格可提前跳过）；
##   · 黑幕显示期间时钟 hold 暂停：倒计时冻结、内核不推 tick、NPC 不动；
##     黑幕退场（自动 / 跳过）后 release 照常 —— 退场 ≠ 跳过事件，
##   · 每天首个课间（开局 / 放学结算后）：大字「第 N 天」+ 小字阶段名，总长约 2 秒；
##   · 其余课间：黑幕短闪「下课了」，总长约 1.5 秒；跳过键所有黑幕都可用；
##   · 黑幕退场 ≠ 跳过事件：相位仍由 SimulationClock 逐 tick 跑完，事件一个不少。

signal shown(display_name: String)
signal dismissed
signal dismiss_started
signal skip_pressed

const FONT_FAMILIES: Array[String] = [
	"Microsoft YaHei",
	"微软雅黑",
	"SimHei",
	"Noto Sans CJK SC",
	"PingFang SC",
	"sans-serif",
]
const COLOR_VEIL := Color(0.05, 0.06, 0.06, 1.0)
const COLOR_TITLE := Color(0.92, 0.90, 0.84, 1.0)
const COLOR_SUB := Color(0.55, 0.58, 0.55, 1.0)
const FADE_IN_SECONDS := 0.4
const FADE_OUT_SECONDS := 0.25
## 短闪黑幕的停留时长（不含淡入淡出共 0.65 秒）：
##   下课总长约 1.65 秒；早上「第 N 天」与上课均总长约 2 秒
const FLASH_HOLD_BREAK := 1.0
const FLASH_HOLD_DAY := 1.35
const FLASH_HOLD_CLASS := 1.35
## 时钟暂停的拥有者标记（黑幕显示期间冻结倒计时与走动）
const HOLD_OWNER := &"transition_overlay"
const TITLE_FONT_SIZE := 64
const SUB_FONT_SIZE := 24
const TITLE_CLASS := "上课了"
const TITLE_BREAK := "下课了"
## 放学边界（进入晚自习留白）的短闪文案
const TITLE_EVENING := "晚自习了"
const SKIP_BUTTON_TEXT := "跳过 ▶（空格）"
const CORNER_MARGIN := Vector2(24.0, 20.0)
const LAYER := 10

var _clock: SimulationClock = null
var _root: Control = null
var _title: Label = null
var _subtitle: Label = null
var _skip_button: Button = null
var _tween: Tween = null
var _font: Font = null
## 已展示过黑幕的最后一天（判定「每天首个课间」用；-1 = 尚未展示）
var _last_day := -1
## 开局首日是否已展示过「第 1 天」黑幕（首日用第 N 天黑幕，之后放学边界改用晚自习短闪）
var _first_day_shown := false


func _ready() -> void:
	layer = LAYER
	visible = false
	_build_ui()


func _exit_tree() -> void:
	_unbind()


## 跳过快捷键：黑幕是全屏模态层，用 _input 而非 _unhandled_input ——
## 避免 _unhandled 被焦点按钮 / 其它 UI 抢先消费导致“有时按了没反应”。
## 仅黑幕可见时拦截，平时不碰任何输入。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept"):
		_request_skip()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ 绑定
## 绑定时钟（重复绑定同一个时钟不会重复连接信号）。
func bind_clock(clock: SimulationClock) -> void:
	if _clock == clock:
		return
	_unbind()
	_clock = clock
	if _clock == null:
		return
	_clock.phase_changed.connect(_on_phase_changed)
	_clock.term_finished.connect(_on_term_finished)
	# 绑定时可能已在上课（教室场景中途接入）：按当前快照同步一次
	_sync_with(_clock.snapshot())


func _unbind() -> void:
	if _clock == null or not is_instance_valid(_clock):
		_clock = null
		return
	_clock.release(HOLD_OWNER)
	_clock.phase_changed.disconnect(_on_phase_changed)
	_clock.term_finished.disconnect(_on_term_finished)
	_clock = null


# ------------------------------------------------------------------ 相位响应
func _on_phase_changed(snapshot_data: Dictionary) -> void:
	_sync_with(snapshot_data)


func _on_term_finished(_ended_day: int) -> void:
	_hide_overlay()


## 黑幕只跟相位走：上课与课间都是短闪（时长不同），结算等其余相位一律退场。
## 跨天：开局首日用「第 N 天」黑幕；之后放学边界改短闪「晚自习了」——
## 真正的「第 N 天」黑幕改到点按钮 / 空格确认进入后由 show_day_start() 显示。
func _sync_with(snapshot_data: Dictionary) -> void:
	var kind := str(snapshot_data.get("kind", ""))
	var running := str(snapshot_data.get("mode", "")) == SimulationClock.MODE_RUNNING
	if not running:
		_hide_overlay()
		return
	var display_name := str(snapshot_data.get("display_name", ""))
	if kind == "class":
		_show_overlay(display_name, TITLE_CLASS, FLASH_HOLD_CLASS)
		return
	if kind == "break":
		var day := int(snapshot_data.get("day", 0))
		var is_day_start := day != _last_day
		_last_day = day
		if is_day_start:
			if not _first_day_shown:
				_first_day_shown = true
				_show_overlay(display_name, "第 %d 天" % day, FLASH_HOLD_DAY)
			else:
				# 晚自习过场不带阶段小字（已放学，"上午课间"字样不符）
				_show_overlay("", TITLE_EVENING, FLASH_HOLD_BREAK)
		else:
			_show_overlay(display_name, TITLE_BREAK, FLASH_HOLD_BREAK)
		return
	_hide_overlay()


## 转场黑幕任务：确认进入次日（点按钮 / 空格）后由 classroom 调用，
## 显示「第 N 天」黑幕并 hold 时钟；黑幕结束后的归位与停留由走动组件接管。
func show_day_start(day: int, display_name: String) -> void:
	_show_overlay(display_name, "第 %d 天" % day, FLASH_HOLD_DAY)


# ------------------------------------------------------------------ 显示与跳过
## 所有黑幕都是短闪：淡入 → 停留 hold_seconds → 自动淡出；空格 / 按钮可随时提前退场。
## 显示期间 hold 时钟（倒计时 / tick / NPC 走动冻结），退场后 release 照常。
func _show_overlay(subtitle_text: String, title_text: String, hold_seconds: float) -> void:
	_title.text = title_text
	_subtitle.text = subtitle_text
	_skip_button.visible = true
	visible = true
	if _clock != null and is_instance_valid(_clock):
		_clock.hold(HOLD_OWNER)
	shown.emit(title_text)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_root.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN_SECONDS)
	_tween.tween_interval(hold_seconds)
	_tween.tween_callback(_begin_dismiss)
	_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT_SECONDS)
	_tween.tween_callback(_on_fade_out_done)


func _hide_overlay() -> void:
	if not visible:
		return
	_begin_dismiss()
	_play_fade(0.0, FADE_OUT_SECONDS, true)


## 黑幕开始退场（自动到时或跳过）：先 release 时钟并广播，再淡出 ——
## 外部（走动组件）趁黑幕还没透出画面时完成瞬间归位，避免淡出期间闪现昨天的位置。
func _begin_dismiss() -> void:
	if _clock != null and is_instance_valid(_clock):
		_clock.release(HOLD_OWNER)
	dismiss_started.emit()


## 跳过：让黑幕提前退场并 release 时钟 —— 不丢任何 tick，事件一个不少。
## ⚠️ 必须走 _hide_overlay（内含 _begin_dismiss 释放时钟）：
## 直接 fade 会杀掉尚未执行 _begin_dismiss 的补间，导致时钟永久暂停（倒计时卡死）。
func _request_skip() -> void:
	if not visible:
		return
	skip_pressed.emit()
	_hide_overlay()


func _play_fade(target_alpha: float, seconds: float, hide_at_end: bool = false) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", target_alpha, seconds)
	if hide_at_end:
		_tween.tween_callback(_on_fade_out_done)


func _on_fade_out_done() -> void:
	visible = false
	_root.modulate.a = 0.0
	dismissed.emit()


# ------------------------------------------------------------------ UI 构建
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.modulate.a = 0.0
	add_child(_root)

	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.color = COLOR_VEIL
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(veil)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var box := VBoxContainer.new()
	box.name = "Rows"
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	_title = _make_label(TITLE_FONT_SIZE, COLOR_TITLE)
	_title.name = "PhaseTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_subtitle = _make_label(SUB_FONT_SIZE, COLOR_SUB)
	_subtitle.name = "PhaseSubtitle"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_subtitle)

	var corner := MarginContainer.new()
	corner.name = "SkipCorner"
	corner.set_anchors_preset(Control.PRESET_FULL_RECT)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_constant_override("margin_right", int(CORNER_MARGIN.x))
	corner.add_theme_constant_override("margin_bottom", int(CORNER_MARGIN.y))
	_root.add_child(corner)

	var skip := Button.new()
	skip.name = "SkipButton"
	skip.text = SKIP_BUTTON_TEXT
	skip.focus_mode = Control.FOCUS_NONE
	skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	skip.size_flags_vertical = Control.SIZE_SHRINK_END
	skip.add_theme_font_override("font", _ui_font())
	skip.add_theme_font_size_override("font_size", SUB_FONT_SIZE)
	skip.pressed.connect(_request_skip)
	_skip_button = skip
	corner.add_child(skip)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", _ui_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## UI 字体：中文字族优先，末位 sans-serif 兜底（与 TimeHUD 同一套族名）。
func _ui_font() -> Font:
	if _font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(FONT_FAMILIES)
		font.font_weight = 700
		_font = font
	return _font
