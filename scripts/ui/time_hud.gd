class_name TimeHUD
extends CanvasLayer
## 时间 HUD（表现层）：只读时钟快照，显示「第几天 / 阶段名 / 剩余时间 / 进度」。
##
## 依据：docs/superpowers/plans/2026-10-07-time-component.md §3（UI 方案）。
## 铁律：HUD **不持有玩法时间、不自己减秒** —— 一切数字来自 SimulationClock.snapshot()；
## 卡片尺寸、文案及试用目标集中在 data/ui/time_card.json，纸张样式复用 CampusTheme。
##
## 显示口径：
##   · 课间／上课：天数与阶段 + 剩余时间条，不显示具体分秒；
##   · 临近结束变暖橙色，暂停时冻结并显示「已暂停」；
##   · 日末：第二行改为 `第 6 天结束 · 晚自习与夜晚悄然过去……`，停留 `report_hold_seconds` 秒后
##     **自动进入次日**（空格可提前）；第 30 天结束显示「查看学期报告」按钮；
##   · 剩余比例钳制在 0–1；阶段名提示在边界只弹一次。

## 日报组件接入用：日末停留结束（或玩家按空格提前）时发出
signal continue_requested
signal student_profile_requested(index: int)

## 日末停留时长来自时钟快照（`rules/time_runtime` 的 `report_hold_seconds`）；本组件只倒计时 ——
## 到时**自动**发出 `continue_requested`（第二章 §2.5「日末停留与自动进入」），不显示确认按钮；
## 只有学期结束（finished）保留「查看学期报告」按钮。
const CampusTheme := preload("res://scripts/ui/campus_theme.gd")

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
const TOAST_SECONDS := 1.6

var _card_cfg: Dictionary = JSON.parse_string(
	FileAccess.get_file_as_string("res://data/ui/time_card.json")
)
var _card_margin := Vector2(float(_card_cfg.margin[0]), float(_card_cfg.margin[1]))
var _weekly: Label
var _clock: SimulationClock = null
var _panel: PanelContainer = null
var _title: Label = null
var _grade: RichTextLabel = null
## 上一次显示的学生均分；变化时轻微闪一下。
var _grade_shown := -1.0
var _detail: Label = null
var _time_status: Label
var _time_icon: TextureRect
var _exam: Label = null
var _bar: ProgressBar = null
var _toast: Label = null
var _action: Button = null
var _skip_break_btn: Button = null
var _toast_left := 0.0
var _toast_count := 0
var _last: Dictionary = {}
## 日末自动进入倒计时剩余秒数（< 0 = 不在倒计时）
var _report_hold_left := -1.0
var _font: Font = null
var _attention_card: Control
var _attention_cfg: Dictionary = JSON.parse_string(
	FileAccess.get_file_as_string("res://data/ui/attention_card.json")
)
var _class_card: Control
var _overview_cfg: Dictionary = JSON.parse_string(
	FileAccess.get_file_as_string("res://data/ui/class_overview_card.json")
)


func _ready() -> void:
	_build_ui()
	CampusTheme.apply_tree(self)
	_style_time_card()
	_class_card = preload("res://scripts/ui/class_overview_card.gd").new()
	_class_card.name = "ClassOverviewCard"
	add_child(_class_card)
	_attention_card = preload("res://scripts/ui/attention_card.gd").new()
	_attention_card.name = "AttentionCard"
	_attention_card.student_requested.connect(student_profile_requested.emit)
	add_child(_attention_card)
	# 2026-10-16：点一下时间卡片按 1× → 2× → 3× 循环换档（键盘/触屏同一入口）。
	if _panel != null and not _panel.gui_input.is_connected(_on_time_card_input):
		_panel.gui_input.connect(_on_time_card_input)
	_refresh({})


func _process(delta: float) -> void:
	# hold/release 不发 time_updated；只读同步暂停变化，不推进模拟时间。
	if is_instance_valid(_clock) and _clock.is_paused() != bool(_last.get("paused", false)):
		_refresh(_clock.snapshot())
	_layout_left_cards()
	tick_report_hold(delta)
	if _toast_left <= 0.0:
		return
	_toast_left = maxf(0.0, _toast_left - delta)
	_toast.modulate.a = _toast_left / TOAST_SECONDS


## 时间卡片被点/触摸一次 → 切换世界速度档位，并立即刷新卡片上的 ×N 显示。
func _on_time_card_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventScreenTouch):
		return
	if not event.pressed:
		return
	if not is_instance_valid(_clock):
		return
	_clock.cycle_time_scale()
	_refresh(_clock.snapshot())


## 跳过当前课间剩余时间：直接调时钟快进（事件不省略），再刷新。
func _on_skip_break_pressed() -> void:
	if not is_instance_valid(_clock):
		return
	if _clock.skip_break_remaining():
		_refresh(_clock.snapshot())


## 三张卡片按可用屏高统一缩放，详情弹层仍使用完整视口。
func _layout_left_cards() -> void:
	var cards := [_panel, _class_card, _attention_card]
	var total := float(_attention_cfg.gap) * (cards.size() - 1)
	for card in cards:
		total += maxf(card.size.y, card.custom_minimum_size.y)
	var height := get_viewport().get_visible_rect().size.y
	var available := maxf(0.0, height - _card_margin.y - float(_attention_cfg.bottom_margin))
	var factor := minf(1.0, available / total) if total > 0.0 else 1.0
	var y := _card_margin.y
	for card in cards:
		card.scale = Vector2.ONE * factor
		card.position = Vector2(_card_margin.x, y)
		y += maxf(card.size.y, card.custom_minimum_size.y) * factor
		y += float(_attention_cfg.gap) * factor
	var x := _card_margin.x
	if y + float(_attention_cfg.toast_reserve) > height:
		x += _panel.size.x * factor + float(_attention_cfg.gap)
		y = _card_margin.y
	_toast.position = Vector2(x, y)
	_action.position = Vector2(x, y + float(_attention_cfg.footer_gap))


## 日末停留期间的「提前进入」键：空格 / 回车（与转场黑幕的跳过键同一动作，仅 report 生效）。
func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_clock) and _clock.is_held_by(&"outcome_screen"):
		return
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


## 日末 / 学期结束按钮当前文案（不可见时为空串）—— 供测试与外部判定。
func action_line() -> String:
	if _action == null or not _action.visible:
		return ""
	return _action.text


## 日末由 ClueBoardEntry 转调：收起风险关注卡片的详情弹层，避免压住推理板。
func close_attention_details() -> void:
	if _attention_card != null and _attention_card.has_method("close_details"):
		_attention_card.close_details()


# ------------------------------------------------------------------ 日末自动进入
## 日末停留倒计时（`_process` 只是转调它，测试可直接驱动）：
## 到时自动发出 `continue_requested`，且**只发一次**；未到停留时长返回 false。
func tick_report_hold(delta_seconds: float) -> bool:
	if is_instance_valid(_clock) and _clock.is_held_by(&"outcome_screen"):
		return false
	if _report_hold_left < 0.0:
		return false
	_report_hold_left = maxf(0.0, _report_hold_left - maxf(delta_seconds, 0.0))
	if _report_hold_left > 0.0:
		return false
	_report_hold_left = -1.0
	continue_requested.emit()
	return true


# ------------------------------------------------------------------ 刷新
func _on_time_updated(snapshot_data: Dictionary) -> void:
	_refresh(snapshot_data)


func _on_phase_changed(snapshot_data: Dictionary) -> void:
	_refresh(snapshot_data)
	var display_name := str(snapshot_data.get("display_name", ""))
	var kind := str(snapshot_data.get("kind", ""))
	_show_toast("%s 开始" % display_name if kind == "break" else "%s · 铃声" % display_name)


func _on_report_ready(ended_day: int) -> void:
	# 日末不等待确认：_refresh 进入 report 分支时开始停留倒计时（见 tick_report_hold）
	_refresh(_clock.snapshot() if _clock != null else {})
	_show_toast("第 %d 天结束" % ended_day)


## 成绩变化时的轻微闪动（§21.2.7：不弹窗、不报数，只让数字自己说话）
func _flash_grade() -> void:
	var tween := create_tween()
	tween.tween_property(_grade, "modulate", Color(1.7, 1.7, 1.7, 1.0), 0.12)
	tween.tween_property(_grade, "modulate", Color.WHITE, 0.4)


func _on_term_finished(ended_day: int) -> void:
	_refresh(_clock.snapshot() if _clock != null else {})
	_show_toast("学期结束 · 共 %d 天" % ended_day)


func _refresh(snapshot_data: Dictionary) -> void:
	if snapshot_data.is_empty():
		return
	_last = snapshot_data
	_class_card.refresh(snapshot_data)
	_attention_card.refresh(snapshot_data)
	var day := int(snapshot_data.get("day", 0))
	var term_days := int(snapshot_data.get("term_days", 0))
	_refresh_weekly_goal(snapshot_data)
	var mode := str(snapshot_data.get("mode", SimulationClock.MODE_RUNNING))
	if _skip_break_btn != null:
		_skip_break_btn.visible = (
			mode == SimulationClock.MODE_RUNNING
			and str(snapshot_data.get("kind", "")) == "break"
			and bool(snapshot_data.get("player_control", true))
			and not bool(snapshot_data.get("paused", false))
		)
	var display_name := str(snapshot_data.get("display_name", ""))
	display_name = str(
		_card_cfg.phase_names.get(str(snapshot_data.get("phase_id", "")), display_name)
	)
	_title.text = "第 %d / %d 天 · %s" % [day, term_days, display_name]
	var speed := float(snapshot_data.get("time_scale", 1.0))
	if speed > 1.0:
		_title.text += " · ×%s" % str(speed)
	_bar.value = (
		(1.0 - clampf(float(snapshot_data.get("progress", 0.0)), 0.0, 1.0)) * 100.0
		if mode == SimulationClock.MODE_RUNNING
		else 0.0
	)
	_bar.visible = mode == SimulationClock.MODE_RUNNING
	_time_icon.visible = _bar.visible
	_time_status.text = ""

	# 非日末状态一律清空停留倒计时（进入 report 时再起，见下）
	if mode != SimulationClock.MODE_REPORT:
		_report_hold_left = -1.0
	_show_exam_line(str(snapshot_data.get("exam_report", snapshot_data.get("exam_banner", ""))))
	if mode == SimulationClock.MODE_FINISHED:
		_detail.text = "学期结束 · 共 %d 天" % int(snapshot_data.get("ended_day", 0))
		_detail.modulate = COLOR_LOCKED
		_show_action("查看学期报告")
		return
	if mode == SimulationClock.MODE_REPORT:
		var ended_day := int(snapshot_data.get("ended_day", 0))
		_detail.text = "第 %d 天结束 · 晚自习与夜晚悄然过去……" % ended_day
		_detail.modulate = COLOR_ACCENT
		# 不显示确认按钮：停留 report_hold_seconds 后自动进入次日（见 tick_report_hold）
		if _report_hold_left < 0.0:
			_report_hold_left = maxf(0.0, float(snapshot_data.get("report_hold_seconds", 0.0)))
		_action.visible = false
		return
	_action.visible = false
	_show_exam_line("")

	_refresh_remaining_state(snapshot_data)


func _refresh_remaining_state(snapshot_data: Dictionary) -> void:
	var words: Dictionary = _card_cfg.messages
	var is_class := str(snapshot_data.get("kind", "")) == "class"
	var paused := bool(snapshot_data.get("paused", false))
	var ending := _bar.value <= float(_card_cfg.ending_remaining_ratio) * _bar.max_value
	var color := Color(str(CampusTheme.settings().teal))
	_detail.text = str(words.class_remaining if is_class else words.break_remaining)
	_detail.modulate = Color.WHITE
	if paused:
		_time_status.text = str(words.paused)
		color = Color(str(_card_cfg.bar_paused_color))
	elif ending:
		_time_status.text = str(words.class_ending if is_class else words.break_ending)
		color = Color(str(_card_cfg.bar_ending_color))
	_time_status.add_theme_color_override("font_color", color)
	_time_icon.modulate = color
	_time_icon.texture = load(
		"res://assets/icons/ui/time_pause.svg" if paused else "res://assets/icons/ui/time_bell.svg"
	)
	var fill := _bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = color


func _refresh_weekly_goal(snapshot_data: Dictionary) -> void:
	var words: Dictionary = _card_cfg.messages
	var day := int(snapshot_data.get("day", 0))
	if str(snapshot_data.get("mode", "")) != SimulationClock.MODE_RUNNING:
		day = int(snapshot_data.get("ended_day", day))
	var exam_day := int(snapshot_data.get("first_exam_day", 0))
	_weekly.text = str(words.week_unknown)
	if exam_day > day:
		_weekly.text = str(words.week_future) % (exam_day - day)
	elif exam_day == day and exam_day > 0:
		_weekly.text = str(words.week_today)
	elif exam_day > 0:
		_weekly.text = str(words.week_past)
	var target := _number_text(float(_card_cfg.target_mean))
	var average = snapshot_data.get("class_average_grade")
	_grade.text = str(words.goal_missing) % target
	_grade.tooltip_text = ""
	if average == null:
		return
	var mean := float(average)
	var theme := CampusTheme.settings()
	var gap := float(_card_cfg.target_mean) - mean
	if gap > 0.0:
		_grade.text = str(words.goal_gap) % [target, str(theme.warning), _number_text(gap)]
	else:
		_grade.text = str(words.goal_reached) % [target, str(theme.teal)]
	_grade.tooltip_text = (
		str(words.grade_tooltip)
		% [
			_number_text(mean),
			_number_text(float(snapshot_data.get("grade_max", 0.0))),
			int(snapshot_data.get("student_count", 0))
		]
	)
	if _grade_shown >= 0.0 and not is_equal_approx(mean, _grade_shown):
		_flash_grade()
	_grade_shown = mean


func _number_text(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")


## 复用纸张纹理；尺寸、留白和字号由 time_card.json 定义。
func _style_time_card() -> void:
	var paper := CampusTheme.paper_card()
	paper.content_margin_left = float(_card_cfg.content_margins[0])
	paper.content_margin_top = float(_card_cfg.content_margins[1])
	paper.content_margin_right = float(_card_cfg.content_margins[2])
	paper.content_margin_bottom = float(_card_cfg.content_margins[3])
	_panel.add_theme_stylebox_override("panel", paper)
	_panel.custom_minimum_size.y = float(_card_cfg.minimum_height)
	var theme := CampusTheme.settings()
	for role in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(str(theme.teal if role == "fill" else theme.disabled))
		style.set_corner_radius_all(int(_card_cfg.bar_radius))
		style.set_content_margin_all(0.0)
		_bar.add_theme_stylebox_override(role, style)


func _show_exam_line(text: String) -> void:
	if _exam == null:
		return
	_exam.text = text
	_exam.visible = not text.is_empty()


## 学期结束的操作按钮文案（日末已改自动进入，不再有按钮）。
func _show_action(text: String) -> void:
	if _action == null:
		return
	_action.visible = true
	_action.text = text


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
	_panel.position = _card_margin
	_panel.custom_minimum_size = Vector2(float(_card_cfg.width), 0.0)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "Rows"
	box.add_theme_constant_override("separation", int(_card_cfg.row_gap))
	_panel.add_child(box)

	_title = _make_label(int(_card_cfg.title_font_size), COLOR_INK)
	box.add_child(_title)
	_detail = _make_label(int(_card_cfg.detail_font_size), COLOR_SUB)
	var time_row := HBoxContainer.new()
	time_row.name = "TimeRow"
	time_row.add_theme_constant_override("separation", int(_card_cfg.icon_gap))
	box.add_child(time_row)
	_time_icon = TextureRect.new()
	_time_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_time_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_time_icon.custom_minimum_size = Vector2.ONE * float(_card_cfg.icon_size)
	time_row.add_child(_time_icon)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(_detail)
	_time_status = _make_label(int(_card_cfg.detail_font_size), COLOR_SUB)
	_time_status.name = "TimeStatus"
	time_row.add_child(_time_status)
	_bar = ProgressBar.new()
	_bar.name = "Remaining"
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0.0, float(_card_cfg.bar_height))
	_bar.max_value = 100.0
	_bar.value = 0.0
	box.add_child(_bar)
	_skip_break_btn = Button.new()
	_skip_break_btn.name = "SkipBreakButton"
	_skip_break_btn.text = str(_card_cfg.messages.get("skip_break", "跳过课间"))
	_skip_break_btn.focus_mode = Control.FOCUS_NONE
	_skip_break_btn.add_theme_font_override("font", _ui_font())
	_skip_break_btn.add_theme_font_size_override("font_size", int(_card_cfg.detail_font_size))
	_skip_break_btn.visible = false
	_skip_break_btn.pressed.connect(_on_skip_break_pressed)
	box.add_child(_skip_break_btn)
	var separator := HSeparator.new()
	separator.name = "GradeSeparator"
	box.add_child(separator)
	var weekly_row := HBoxContainer.new()
	weekly_row.name = "WeeklyExamRow"
	weekly_row.add_theme_constant_override("separation", int(_card_cfg.icon_gap))
	box.add_child(weekly_row)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/icons/ui/calendar.svg")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2.ONE * float(_card_cfg.icon_size)
	weekly_row.add_child(icon)
	_weekly = _make_label(int(_card_cfg.exam_font_size), Color(CampusTheme.settings().teal))
	_weekly.name = "WeeklyExamLabel"
	weekly_row.add_child(_weekly)
	_grade = RichTextLabel.new()
	_grade.name = "GradeLabel"
	_grade.bbcode_enabled = true
	_grade.fit_content = true
	_grade.scroll_active = false
	_grade.add_theme_font_override("normal_font", _ui_font())
	_grade.add_theme_font_size_override("normal_font_size", int(_card_cfg.goal_font_size))
	_grade.add_theme_color_override("default_color", Color(CampusTheme.settings().teal))
	box.add_child(_grade)
	_exam = _make_label(int(_card_cfg.detail_font_size), COLOR_ACCENT)
	_exam.name = "ExamLine"
	_exam.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_exam.visible = false
	box.add_child(_exam)

	_toast = _make_label(int(_card_cfg.detail_font_size), COLOR_ACCENT)
	_toast.name = "PhaseToast"
	_toast.position = _card_margin + Vector2(0.0, CampusTheme.settings().time_card_height)
	_toast.modulate.a = 0.0
	add_child(_toast)

	# 学期结束才出现（日末改自动进入、不显示按钮）；简报组件接入后由它接管日末
	_action = Button.new()
	_action.name = "NextDayButton"
	_action.add_theme_font_override("font", _ui_font())
	_action.add_theme_font_size_override("font_size", int(_card_cfg.detail_font_size))
	_action.visible = false
	_action.position = _card_margin + Vector2(0.0, CampusTheme.settings().time_card_height + 28)
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
		var font := preload("res://scripts/ui/game_fonts.gd").regular()

		_font = font
	return _font
