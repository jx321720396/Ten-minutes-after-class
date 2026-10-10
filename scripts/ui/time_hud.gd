class_name TimeHUD
extends CanvasLayer
## 时间 HUD（表现层）：只读时钟快照，显示「第几天 / 阶段名 / 剩余时间 / 进度」。
##
## 依据：docs/superpowers/plans/2026-10-07-time-component.md §3（UI 方案）。
## 铁律：HUD **不持有玩法时间、不自己减秒** —— 一切数字来自 SimulationClock.snapshot()；
## 样式（米白纸面 / 墨绿细边 / 黑体）集中在本文件常量里，不在别处再起一套装饰。
##
## 显示口径：
##   · 课间：`第 6 / 30 天 · 中午午休` + `课间剩余 01:24` + 剩余时间条；
##   · 上课：`第 6 / 30 天 · 上午课堂` + `发酵中 · 本阶段约剩余 00:12`（玩家操作被锁）；
##   · 日末：第二行改为 `第 6 天结束`（简报与「继续」按钮由日报组件接入）；
##   · 倒计时**向上取整**，边界显示 00:00，不出现负数；阶段名提示在边界只弹一次。

## 日报组件接入用：玩家点「进入第 N 天」
signal continue_requested

## 日末是否等待输入（点按钮 / 空格）才进入次日：
##   true = 调试模式（当前）——按钮仅供内部调试，空格为快捷键；
##   false = 正式上线用 —— 日末自动进入次日，不显示按钮。
const WAIT_INPUT_ON_DAY_END := true

const FONT_FAMILIES: Array[String] = [
	"Microsoft YaHei",
	"微软雅黑",
	"SimHei",
	"Noto Sans CJK SC",
	"PingFang SC",
	"sans-serif",
]
const COLOR_PAPER := Color(0.98, 0.96, 0.90, 0.92)
const COLOR_INK := Color(0.12, 0.16, 0.14)
const COLOR_SUB := Color(0.28, 0.33, 0.30)
const COLOR_ACCENT := Color(0.16, 0.38, 0.26)
const COLOR_LOCKED := Color(0.62, 0.34, 0.22)
const CARD_MARGIN := Vector2(16.0, 16.0)
const CARD_WIDTH := 340.0
const TITLE_FONT_SIZE := 22
const DETAIL_FONT_SIZE := 18
const TOAST_SECONDS := 1.6

var _clock: SimulationClock = null
var _panel: PanelContainer = null
var _title: Label = null
var _grade: Label = null
var _detail: Label = null
var _bar: ProgressBar = null
var _toast: Label = null
var _action: Button = null
var _toast_left := 0.0
var _toast_count := 0
var _last: Dictionary = {}
var _font: Font = null


func _ready() -> void:
	_build_ui()
	_refresh({})


func _process(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left = maxf(0.0, _toast_left - delta)
	_toast.modulate.a = _toast_left / TOAST_SECONDS


## 日末调试快捷键：空格等同点「进入第 N 天」（仅 report 状态生效）。
func _unhandled_input(event: InputEvent) -> void:
	if _last.is_empty() or str(_last.get("mode", "")) != SimulationClock.MODE_REPORT:
		return
	if event.is_action_pressed("ui_accept"):
		continue_requested.emit()
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
	_clock.time_updated.connect(_on_time_updated)
	_clock.phase_changed.connect(_on_phase_changed)
	_clock.report_ready.connect(_on_report_ready)
	_clock.term_finished.connect(_on_term_finished)
	_refresh(_clock.snapshot())


func _unbind() -> void:
	if _clock == null or not is_instance_valid(_clock):
		_clock = null
		return
	_clock.time_updated.disconnect(_on_time_updated)
	_clock.phase_changed.disconnect(_on_phase_changed)
	_clock.report_ready.disconnect(_on_report_ready)
	_clock.term_finished.disconnect(_on_term_finished)
	_clock = null


# ------------------------------------------------------------------ 只读查询（供测试与外部判定）
func connection_count() -> int:
	if _clock == null or not is_instance_valid(_clock):
		return 0
	return (
		_clock.time_updated.get_connections().size()
		+ _clock.phase_changed.get_connections().size()
		+ _clock.report_ready.get_connections().size()
		+ _clock.term_finished.get_connections().size()
	)


func title_line() -> String:
	return _title.text


func detail_line() -> String:
	return _detail.text


func progress_percent() -> float:
	return _bar.value


## 玩家是否被允许操作（上课与日末简报期间为 false）。
func controls_locked() -> bool:
	var mode := str(_last.get("mode", "running"))
	if mode != SimulationClock.MODE_RUNNING:
		return true
	return not bool(_last.get("player_control", true))


func toast_count() -> int:
	return _toast_count


# ------------------------------------------------------------------ 刷新
func _on_time_updated(snapshot_data: Dictionary) -> void:
	_refresh(snapshot_data)


func _on_phase_changed(snapshot_data: Dictionary) -> void:
	_refresh(snapshot_data)
	var display_name := str(snapshot_data.get("display_name", ""))
	var kind := str(snapshot_data.get("kind", ""))
	_show_toast("%s 开始" % display_name if kind == "break" else "%s · 铃声" % display_name)


func _on_report_ready(ended_day: int) -> void:
	_refresh(_clock.snapshot() if _clock != null else {})
	_show_toast("第 %d 天结束" % ended_day)
	if not WAIT_INPUT_ON_DAY_END:
		# 正式上线模式：不等待输入，直接进入次日
		continue_requested.emit()


func _on_term_finished(ended_day: int) -> void:
	_refresh(_clock.snapshot() if _clock != null else {})
	_show_toast("学期结束 · 共 %d 天" % ended_day)


func _refresh(snapshot_data: Dictionary) -> void:
	if snapshot_data.is_empty():
		return
	_last = snapshot_data
	var day := int(snapshot_data.get("day", 0))
	var term_days := int(snapshot_data.get("term_days", 0))
	var player_grade := int(snapshot_data.get("player_grade", 0))
	_grade.text = "成绩 %d ｜ 距期末考 %d 天" % [player_grade, maxi(0, term_days - day)]
	var mode := str(snapshot_data.get("mode", SimulationClock.MODE_RUNNING))
	var display_name := str(snapshot_data.get("display_name", ""))
	_title.text = "第 %d / %d 天 · %s" % [day, term_days, display_name]
	var speed := float(snapshot_data.get("time_scale", 1.0))
	if speed > 1.0:
		_title.text += " · ×%s" % str(speed)
	_bar.value = float(snapshot_data.get("progress", 0.0)) * 100.0

	if mode == SimulationClock.MODE_FINISHED:
		_detail.text = "学期结束 · 共 %d 天" % int(snapshot_data.get("ended_day", 0))
		_detail.modulate = COLOR_LOCKED
		_show_action("查看学期报告")
		return
	if mode == SimulationClock.MODE_REPORT:
		var ended_day := int(snapshot_data.get("ended_day", 0))
		_detail.text = "第 %d 天结束 · 晚自习与夜晚悄然过去……" % ended_day
		_detail.modulate = COLOR_ACCENT
		_show_action("进入第 %d 天" % (ended_day + 1))
		return
	_action.visible = false

	var remaining := _seconds_text(float(snapshot_data.get("remaining_seconds", 0.0)))
	if str(snapshot_data.get("kind", "")) == "class":
		_detail.text = "发酵中 · 本阶段约剩余 %s 秒" % remaining
		_detail.modulate = COLOR_LOCKED
		return
	_detail.text = "课间剩余 %s 秒" % remaining
	_detail.modulate = COLOR_SUB


## 日末 / 学期结束的操作按钮文案（计划 §3）。
func _show_action(text: String) -> void:
	if _action == null:
		return
	_action.visible = true
	_action.text = text


## 倒计时格式：**直接给剩余秒数**（向上取整、边界 0、不出现负数）。
## 用户 2026-10-07 决策：不折算成 mm:ss —— 课间满段 100 秒就显示「100 秒」。
func _seconds_text(seconds: float) -> String:
	return "%d" % int(ceilf(maxf(seconds, 0.0)))


func _show_toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_left = TOAST_SECONDS
	_toast_count += 1


# ------------------------------------------------------------------ UI 构建
func _build_ui() -> void:
	layer = 2
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PAPER
	style.border_color = COLOR_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0

	_panel = PanelContainer.new()
	_panel.name = "Card"
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = CARD_MARGIN
	_panel.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "Rows"
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	# 成绩（§21.2.7）：**独立显示在屏幕右上角**，不与左上角的时间卡片挤在一起
	var grade_card := PanelContainer.new()
	grade_card.name = "GradeCard"
	grade_card.add_theme_stylebox_override("panel", style)
	grade_card.anchor_left = 1.0
	grade_card.anchor_right = 1.0
	grade_card.anchor_top = 0.0
	grade_card.anchor_bottom = 0.0
	grade_card.offset_left = -CARD_WIDTH
	grade_card.offset_right = -CARD_MARGIN.x
	grade_card.offset_top = CARD_MARGIN.y
	grade_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grade_card.grow_vertical = Control.GROW_DIRECTION_END
	add_child(grade_card)
	_grade = _make_label(DETAIL_FONT_SIZE, COLOR_ACCENT)
	_grade.name = "GradeLabel"
	grade_card.add_child(_grade)
	_title = _make_label(TITLE_FONT_SIZE, COLOR_INK)
	box.add_child(_title)
	_detail = _make_label(DETAIL_FONT_SIZE, COLOR_SUB)
	box.add_child(_detail)

	_bar = ProgressBar.new()
	_bar.name = "Remaining"
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(CARD_WIDTH - 28.0, 8.0)
	_bar.max_value = 100.0
	_bar.value = 0.0
	box.add_child(_bar)

	_toast = _make_label(DETAIL_FONT_SIZE, COLOR_ACCENT)
	_toast.name = "PhaseToast"
	_toast.position = CARD_MARGIN + Vector2(0.0, 108.0)
	_toast.modulate.a = 0.0
	add_child(_toast)

	# 日末 / 学期结束才出现：简报组件的入口（本组件只负责显示与转发）
	_action = Button.new()
	_action.name = "NextDayButton"
	_action.add_theme_font_override("font", _ui_font())
	_action.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
	_action.visible = false
	_action.position = CARD_MARGIN + Vector2(0.0, 116.0)
	_action.pressed.connect(func() -> void: continue_requested.emit())
	add_child(_action)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", _ui_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## UI 字体：中文字族优先，末位 sans-serif 兜底（与 ActorWalker 同一套族名）。
func _ui_font() -> Font:
	if _font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(FONT_FAMILIES)
		_font = font
	return _font
