extends Control
## 麦克风三步校准覆盖层（2026-10-19）。
## 只在本机累计 RMS：安静 / 平常音量 / 最大声；不录音、不上传。
## 由设置菜单创建；完成后发 finished(profile)，由设置写入 VoiceSettings。

signal finished(profile: Dictionary)
signal cancelled

const FONTS := preload("res://scripts/ui/game_fonts.gd")
const VOICE_INPUT := preload("res://scripts/game/voice_input.gd")
const STEP_TEXTS := [
	"第 1 步：安静 1.5 秒，先别说话",
	"第 2 步：用平常音量说一句「同学们，看黑板」",
	"第 3 步：用最大声喊一声「安静！」",
]

var _input: Node
var _prompt: Label
var _bar: ProgressBar
var _hint: Label
var _cancel: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.97, 0.91, 1.0)
	style.set_border_width_all(2)
	style.border_color = Color(0.8, 0.7, 0.5, 1.0)
	style.set_corner_radius_all(22)
	style.set_content_margin_all(36)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 18)
	panel.add_child(rows)
	var title := Label.new()
	title.text = "校准麦克风"
	title.add_theme_font_override("font", FONTS.regular())
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.14, 0.24, 0.48, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)
	_prompt = Label.new()
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.add_theme_font_override("font", FONTS.regular())
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.add_theme_color_override("font_color", Color(0.28, 0.2, 0.12, 1))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_prompt)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 28)
	_bar.max_value = 100.0
	_bar.show_percentage = false
	rows.add_child(_bar)
	_hint = Label.new()
	_hint.text = "只在本机计算音量，不录音、不上传。"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_override("font", FONTS.regular())
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", Color(0.42, 0.34, 0.24, 1))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_hint)
	_cancel = Button.new()
	_cancel.text = "取消"
	_cancel.custom_minimum_size = Vector2(180, 52)
	_cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel.pressed.connect(_on_cancel)
	rows.add_child(_cancel)
	_input = VOICE_INPUT.new()
	add_child(_input)
	var rules := VoiceRules.new()
	rules.configure_table(ConfigLoader.new().get_table("rules/voice"))
	_input.configure(rules)
	_input.calibration_step.connect(_on_step)
	_input.calibration_level.connect(_on_level)
	_input.calibration_finished.connect(_on_finished)
	_input.calibration_failed.connect(_on_failed)
	TouchBind.bind_tree(self)


func open() -> void:
	visible = true
	if not _input.begin_calibration():
		_prompt.text = "麦克风不可用或未授权；可改用按住蓄力。"
		_bar.value = 0.0


func _on_step(index: int) -> void:
	if index < 0 or index >= STEP_TEXTS.size():
		return
	_prompt.text = str(STEP_TEXTS[index])
	_bar.value = 0.0


func _on_level(rms: float) -> void:
	_bar.value = clampf(rms * 500.0, 0.0, 100.0)


func _on_finished(profile: Dictionary) -> void:
	finished.emit(profile)
	queue_free()


func _on_failed(reason: String) -> void:
	_prompt.text = "麦克风不可用：%s。可改用按住蓄力。" % reason
	_hint.text = "校准只在本机计算音量，不录音、不上传。"
	_cancel.text = "关闭"


func _on_cancel() -> void:
	_input.cancel_calibration()
	cancelled.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
