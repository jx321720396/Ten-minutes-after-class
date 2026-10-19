class_name TutorialOverlay
extends CanvasLayer
## 老师版新手教程覆盖层（第 0 天报到日，docs/design/新手教程-报到日-2026-10-19.md）。
##
## 纪律：纯表现层——只消费调用方喂进来的事件（notify_event），自己轮询步骤计时；
## 不读 NPC 隐藏数值、不写任何矩阵。把本组件整体删掉，正式局行为零变化。
## 文案全部来自 data/ui/tutorial.json（本地化纪律），本脚本零中文字面量。
##
## 流程：start_first_run() → 开场纸卡 → intro_closed → 步进提示（done_event / 超时 /
## 说明卡）→ tutorial_finished。教程时钟由调用方管理：每段开始 hold，玩家点继续释放。

signal intro_closed
signal tutorial_finished

const CFG_PATH := "res://data/ui/tutorial.json"
const DEFAULT_SEEN_PATH := "user://tutorial_seen.dat"
## 压在转场黑幕（TransitionOverlay layer=10）之上，开场卡不被盖住
const UI_LAYER := 45
const HINT_WIDTH := 720.0
## 提示条内「下一步」按钮的尺寸（热区 ≥44，§20.0.4）
const HINT_NEXT_MIN := Vector2(96, 44)

const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.45)
const COLOR_PAPER := Color(1.0, 0.97, 0.91, 1.0)
const COLOR_BORDER := Color(0.8, 0.7, 0.5, 1.0)
const COLOR_INK := Color(0.28, 0.2, 0.12, 1.0)
const COLOR_SUB := Color(0.42, 0.44, 0.5, 1.0)
const COLOR_ACCENT := Color(0.16, 0.38, 0.26, 1.0)
const COLOR_HIGHLIGHT := Color(0.78, 0.65, 0.42, 0.9)

## 「已看」标记路径：默认值之上的覆盖仅供测试隔离（不污染开发者真档）
var seen_path := DEFAULT_SEEN_PATH

var _cfg: Dictionary = {}
var _running := false
var _card_index := 0
var _step_index := -1
var _step_elapsed := 0.0
var _anchors: Dictionary = {}

var _root: Control
var _card_overlay: Control
var _card_title: Label
var _card_msg: Label
var _next_btn: Button
var _hint_bar: PanelContainer
var _hint_label: Label
var _hint_next_btn: Button
var _skip_btn: Button
var _highlight: PanelContainer
var _info_overlay: Control
var _info_title: Label
var _info_rows: VBoxContainer
var _info_close_btn: Button


func _ready() -> void:
	layer = UI_LAYER
	_cfg = _load_cfg()
	_build_ui()
	TouchBind.bind_tree(self)
	visible = false


func _load_cfg() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	if parsed is Dictionary:
		return parsed
	push_error("TutorialOverlay：配置读不到或格式不对（%s）——教程静默跳过。" % CFG_PATH)
	return {}


# ------------------------------------------------------------------ 绑定


## 注入界面锚点。时钟与玩家参数保留以兼容现有教室调用；教程时钟由调用方管理。
func bind_world(_clock: SimulationClock, _player: Node3D, anchors: Dictionary) -> void:
	_anchors = anchors


# ------------------------------------------------------------------ 对外状态


static func is_seen() -> bool:
	return FileAccess.file_exists(DEFAULT_SEEN_PATH)


## 固定教程种子：保证每次报到日的学生初始状态一致（可在 tutorial.json 改）。
static func tutorial_seed() -> int:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	if parsed is Dictionary:
		return int(parsed.get("seed", 20261019))
	return 20261019


func is_running() -> bool:
	return _running


func start_first_run() -> void:
	if _cfg.is_empty():
		return
	_running = true
	visible = true
	_skip_btn.visible = true
	_card_index = 0
	_show_card(0)


func skip() -> void:
	if not _running:
		return
	_finish()


# ------------------------------------------------------------------ 事件入口（由教室 / 办公室转发）


## 真实操作完成时通知教程。只有当前步骤等待的 done_event 匹配才推进。
func notify_event(event: StringName) -> void:
	if not _running or is_intro_open() or is_info_open():
		return
	var step := _current_step()
	if str(step.get("done_event", "")) == str(event):
		_advance()


## 兼容旧教室接线：老师版新教程不使用行为栏 arm / commit 事件。
func notify_armed(_kind: StringName) -> void:
	pass


func notify_committed(_kind: StringName) -> void:
	pass


# ------------------------------------------------------------------ 每帧推进


func _process(delta: float) -> void:
	if not visible:
		return
	_sync_positions()
	if not _running or is_intro_open() or is_info_open():
		return
	var step := _current_step()
	if step.is_empty():
		_finish()
		return
	_step_elapsed += delta
	var auto_pass := float(step.get("auto_pass_seconds", 0.0))
	if auto_pass > 0.0 and _step_elapsed >= auto_pass:
		_advance()
		return
	var timeout := float(step.get("timeout_seconds", 0.0))
	if timeout > 0.0 and _step_elapsed >= timeout:
		_advance()


# ------------------------------------------------------------------ 开场卡


func _show_card(i: int) -> void:
	var cards: Array = _cfg.get("intro_cards", [])
	if cards.is_empty():
		_close_intro()
		return
	_card_index = clampi(i, 0, cards.size() - 1)
	var card: Dictionary = cards[_card_index]
	_card_title.text = str(card.get("title", ""))
	_card_msg.text = str(card.get("text", ""))
	_next_btn.text = _label("next")
	_card_overlay.visible = true


func _last_card() -> bool:
	return _card_index >= _cfg.get("intro_cards", []).size() - 1


func _on_hint_next() -> void:
	# 「下一步」：手动推进当前提示；开场卡与说明卡各有自己的按钮
	if _running and not is_intro_open() and not is_info_open():
		_advance()


func _on_next_pressed() -> void:
	if not _last_card():
		_show_card(_card_index + 1)
		return
	_close_intro()


func _close_intro() -> void:
	_card_overlay.visible = false
	intro_closed.emit()
	_step_index = 0
	_apply_step()


# ------------------------------------------------------------------ 步进提示


func _apply_step() -> void:
	var step := _current_step()
	if step.is_empty():
		_finish()
		return
	_step_elapsed = 0.0
	var info_id := str(step.get("info_card", ""))
	if not info_id.is_empty():
		_hint_bar.visible = false
		_highlight.visible = false
		_show_info(info_id)
		return
	_hint_label.text = str(step.get("text", ""))
	_hint_bar.visible = true
	_hint_next_btn.visible = true
	_skip_btn.visible = true
	_show_anchor(str(step.get("anchor", "")))


func _show_info(info_id: String) -> void:
	var cards: Dictionary = _cfg.get("info_cards", {})
	var rows: Array = cards.get(info_id, [])
	if rows.is_empty():
		_advance()
		return
	for child in _info_rows.get_children():
		_info_rows.remove_child(child)
		child.queue_free()
	_info_title.text = _label("info_title")
	for row in rows:
		var line := Label.new()
		line.text = "%s：%s" % [str(row.get("name", "")), str(row.get("text", ""))]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(520, 0)
		line.add_theme_color_override("font_color", COLOR_INK)
		line.add_theme_font_size_override("font_size", 23)
		_info_rows.add_child(line)
	_info_close_btn.text = _label("info_close")
	_info_overlay.visible = true
	_skip_btn.visible = true


func _on_info_close() -> void:
	if not is_info_open():
		return
	_info_overlay.visible = false
	_advance()


func _show_anchor(anchor_id: String) -> void:
	if anchor_id.is_empty() or not _anchors.has(anchor_id):
		_highlight.visible = false
		return
	_highlight.visible = true


func _sync_positions() -> void:
	if _hint_bar.visible:
		_hint_bar.position = Vector2((_root.size.x - _hint_bar.size.x) * 0.5, 16.0)
	if not _highlight.visible:
		return
	var step := _current_step()
	var anchor_id := str(step.get("anchor", "")) if _running and _step_index >= 0 else ""
	if anchor_id.is_empty() or not _anchors.has(anchor_id):
		_highlight.visible = false
		return
	var target: Control = _anchors[anchor_id] as Control
	if target == null or not is_instance_valid(target):
		# 锚点绑了非 Control（如 CanvasLayer 本体）时静默不画，不让教程炸掉
		_highlight.visible = false
		return
	_highlight.position = target.get_global_rect().position - Vector2(6.0, 6.0)
	_highlight.size = target.get_global_rect().size + Vector2(12.0, 12.0)


func _current_step() -> Dictionary:
	var steps: Array = _cfg.get("steps", [])
	if _step_index < 0 or _step_index >= steps.size():
		return {}
	return steps[_step_index]


func _advance() -> void:
	var steps: Array = _cfg.get("steps", [])
	if _step_index + 1 >= steps.size():
		_finish()
		return
	_step_index += 1
	_apply_step()


func _finish() -> void:
	var was_intro := is_intro_open()
	_running = false
	_hint_bar.visible = false
	_highlight.visible = false
	_skip_btn.visible = false
	_card_overlay.visible = false
	_info_overlay.visible = false
	if was_intro:
		# 跳过发生在开场卡期间也要通知调用方释放时钟，否则世界永远冻结
		intro_closed.emit()
	_write_seen()
	tutorial_finished.emit()


func _label(key: String) -> String:
	return str(_cfg.get("labels", {}).get(key, ""))


func _write_seen() -> void:
	var f := FileAccess.open(seen_path, FileAccess.WRITE)
	if f != null:
		f.store_string("seen")


func is_intro_open() -> bool:
	return _card_overlay != null and _card_overlay.visible


func is_info_open() -> bool:
	return _info_overlay != null and _info_overlay.visible


# ------------------------------------------------------------------ UI 搭建（样式同纸面基线 §20.0.3）


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_card_overlay = ColorRect.new()
	_card_overlay.name = "CardOverlay"
	_card_overlay.color = COLOR_OVERLAY
	_card_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_overlay.visible = false
	_root.add_child(_card_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", _paper_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	_card_title = Label.new()
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_title.add_theme_color_override("font_color", COLOR_INK)
	_card_title.add_theme_font_size_override("font_size", 34)
	vbox.add_child(_card_title)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.72, 0.7, 0.64, 1)
	vbox.add_child(sep)

	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer1)

	_card_msg = Label.new()
	_card_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_msg.custom_minimum_size = Vector2(400, 0)
	_card_msg.add_theme_color_override("font_color", COLOR_SUB)
	_card_msg.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_card_msg)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(spacer2)

	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(240, 52)
	_next_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_next_btn.add_theme_color_override("font_color", COLOR_ACCENT)
	_next_btn.add_theme_font_size_override("font_size", 26)
	_next_btn.pressed.connect(_on_next_pressed)
	vbox.add_child(_next_btn)

	_build_info_ui()

	_hint_bar = PanelContainer.new()
	_hint_bar.name = "HintBar"
	# 条身不拦截鼠标：地面点击照常落下去，只有「下一步」按钮自己接输入
	_hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_bar.add_theme_stylebox_override("panel", _paper_style())
	_hint_bar.visible = false
	_root.add_child(_hint_bar)

	var hint_margin := MarginContainer.new()
	hint_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_margin.add_theme_constant_override("margin_left", 18)
	hint_margin.add_theme_constant_override("margin_right", 18)
	hint_margin.add_theme_constant_override("margin_top", 10)
	hint_margin.add_theme_constant_override("margin_bottom", 10)
	_hint_bar.add_child(hint_margin)

	var hint_row := HBoxContainer.new()
	hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_row.add_theme_constant_override("separation", 14)
	hint_margin.add_child(hint_row)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(HINT_WIDTH, 0)
	_hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_color_override("font_color", COLOR_INK)
	_hint_label.add_theme_font_size_override("font_size", 24)
	hint_row.add_child(_hint_label)

	_hint_next_btn = Button.new()
	_hint_next_btn.name = "HintNextBtn"
	_hint_next_btn.text = _label("next_hint")
	_hint_next_btn.custom_minimum_size = HINT_NEXT_MIN
	_hint_next_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint_next_btn.add_theme_color_override("font_color", COLOR_ACCENT)
	_hint_next_btn.add_theme_font_size_override("font_size", 22)
	_hint_next_btn.pressed.connect(_on_hint_next)
	_hint_next_btn.visible = false
	hint_row.add_child(_hint_next_btn)

	_skip_btn = Button.new()
	_skip_btn.name = "SkipBtn"
	_skip_btn.text = _label("skip")
	_skip_btn.custom_minimum_size = Vector2(120, 44)
	_skip_btn.anchor_left = 1.0
	_skip_btn.anchor_right = 1.0
	_skip_btn.offset_left = -136.0
	_skip_btn.offset_right = -16.0
	_skip_btn.offset_top = 12.0
	_skip_btn.offset_bottom = 56.0
	_skip_btn.add_theme_color_override("font_color", COLOR_SUB)
	_skip_btn.add_theme_font_size_override("font_size", 20)
	_skip_btn.pressed.connect(skip)
	_skip_btn.visible = false
	_root.add_child(_skip_btn)

	_highlight = PanelContainer.new()
	_highlight.name = "AnchorHighlight"
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hl := StyleBoxFlat.new()
	hl.draw_center = false
	hl.border_color = COLOR_HIGHLIGHT
	hl.set_border_width_all(3)
	hl.set_corner_radius_all(8)
	_highlight.add_theme_stylebox_override("panel", hl)
	_highlight.visible = false
	_root.add_child(_highlight)


func _build_info_ui() -> void:
	_info_overlay = ColorRect.new()
	_info_overlay.name = "InfoOverlay"
	_info_overlay.color = COLOR_OVERLAY
	_info_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_info_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_info_overlay.visible = false
	_root.add_child(_info_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_info_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	panel.add_theme_stylebox_override("panel", _paper_style())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	_info_title = Label.new()
	_info_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_title.add_theme_color_override("font_color", COLOR_INK)
	_info_title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(_info_title)

	_info_rows = VBoxContainer.new()
	_info_rows.add_theme_constant_override("separation", 10)
	vbox.add_child(_info_rows)

	_info_close_btn = Button.new()
	_info_close_btn.custom_minimum_size = Vector2(180, 52)
	_info_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_info_close_btn.add_theme_color_override("font_color", COLOR_ACCENT)
	_info_close_btn.add_theme_font_size_override("font_size", 24)
	_info_close_btn.pressed.connect(_on_info_close)
	vbox.add_child(_info_close_btn)


func _paper_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PAPER
	sb.border_color = COLOR_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 36.0
	sb.content_margin_right = 36.0
	sb.content_margin_top = 28.0
	sb.content_margin_bottom = 28.0
	return sb


func _unhandled_input(event: InputEvent) -> void:
	# 开场卡期间 Esc = 跳过教程；说明卡期间 Esc = 关闭说明；步进提示仍归暂停菜单。
	if not visible or not _running or not event.is_action_pressed("ui_cancel"):
		return
	if is_intro_open():
		skip()
		get_viewport().set_input_as_handled()
	elif is_info_open():
		_on_info_close()
		get_viewport().set_input_as_handled()
