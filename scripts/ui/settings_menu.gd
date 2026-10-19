extends Control

signal closed

const CONFIRM := preload("res://scenes/ui/confirm_dialog.tscn")
const FONTS := preload("res://scripts/ui/game_fonts.gd")
const VOICE_PERMISSION := "android.permission.RECORD_AUDIO"
const VOICE_TITLE := "声量模式（挑战）"
const VOICE_DESC := "开启后办公室操作随你的声量变化；可能让考核更难，极端情况下无法通关。"
const VOICE_WARN_TITLE := "开启声量模式？"
const VOICE_WARN_MSG := "声量会改变训斥、安抚、表扬、鼓励的效果。大声训斥可能让学生崩溃，进而影响考核；" + "使用本功能可能无法通关。关闭时按现行固定数值结算。"
const VOICE_WARN_OK := "仍然开启"

@onready var back_btn: Button = $Overlay/CenterContainer/Panel/VBox/BackBtn
@onready var bgm_slider: HSlider = $Overlay/CenterContainer/Panel/VBox/BGMRow/BGMSlider
@onready var sfx_slider: HSlider = $Overlay/CenterContainer/Panel/VBox/SFXRow/SFXSlider

var _voice_row: HBoxContainer
var _voice_toggle: Button
var _voice_desc: Label
var _voice_input_row: HBoxContainer
var _voice_mic_btn: Button
var _voice_hold_btn: Button
var _voice_calibrate: Button
var _voice_status: Label
var _voice_confirm: Control


func _ready():
	get_viewport().size_changed.connect(_fit_fullscreen)
	_fit_fullscreen()
	back_btn.pressed.connect(_on_back)
	bgm_slider.value = BGM.get_bgm_volume() * 100.0
	bgm_slider.value_changed.connect(_on_bgm_volume_changed)
	sfx_slider.value = SFX.get_sfx_volume() * 100.0
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_build_voice_settings()
	_wrap_in_scroll()
	_fit_fullscreen()
	TouchBind.bind_tree(self)


func _fit_fullscreen() -> void:
	preload("res://scripts/ui/fullscreen_panel.gd").fit(
		$Overlay/CenterContainer, $Overlay/CenterContainer/Panel, Vector2(1280, 720)
	)


func _on_bgm_volume_changed(value: float) -> void:
	BGM.set_bgm_volume(value / 100.0)


func _on_sfx_volume_changed(value: float) -> void:
	SFX.set_sfx_volume(value / 100.0)


func _on_back():
	emit_signal("closed")


# ------------------------------------------------------------------ 声量模式（可选挑战）
func _build_voice_settings() -> void:
	var vbox := $Overlay/CenterContainer/Panel/VBox as VBoxContainer
	# 压缩原有间距，给声量区留出空间。
	(vbox.get_node("Spacer1") as Control).custom_minimum_size.y = 20.0
	(vbox.get_node("Spacer2") as Control).custom_minimum_size.y = 12.0
	(vbox.get_node("Spacer3") as Control).custom_minimum_size.y = 20.0
	var replay: Button = back_btn  # 「重看教程」按钮已移除，以「返回」按钮作样式参照与插入锚点
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)
	vbox.move_child(spacer, replay.get_index())
	_voice_row = HBoxContainer.new()
	_voice_row.add_theme_constant_override("separation", 20)
	var title := Label.new()
	title.text = VOICE_TITLE
	title.custom_minimum_size = Vector2(240, 0)
	title.add_theme_font_override("font", FONTS.regular())
	title.add_theme_color_override("font_color", Color(0.28, 0.2, 0.12, 1))
	title.add_theme_font_size_override("font_size", 24)
	_voice_row.add_child(title)
	var flex := Control.new()
	flex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_row.add_child(flex)
	_voice_toggle = Button.new()
	_voice_toggle.toggle_mode = true
	_voice_toggle.custom_minimum_size = Vector2(96, 44)
	_style_like(_voice_toggle, replay)
	_voice_toggle.add_theme_font_size_override("font_size", 22)
	_voice_toggle.pressed.connect(_on_voice_toggle_pressed)
	_voice_row.add_child(_voice_toggle)
	vbox.add_child(_voice_row)
	vbox.move_child(_voice_row, replay.get_index())
	_voice_desc = Label.new()
	_voice_desc.text = VOICE_DESC
	_voice_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voice_desc.custom_minimum_size = Vector2(0, 44)
	_voice_desc.add_theme_font_override("font", FONTS.regular())
	_voice_desc.add_theme_color_override("font_color", Color(0.42, 0.34, 0.24, 1))
	_voice_desc.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_voice_desc)
	vbox.move_child(_voice_desc, replay.get_index())
	_voice_input_row = HBoxContainer.new()
	_voice_input_row.add_theme_constant_override("separation", 10)
	var input_title := Label.new()
	input_title.text = "输入"
	input_title.custom_minimum_size = Vector2(40, 0)
	input_title.add_theme_font_override("font", FONTS.regular())
	input_title.add_theme_color_override("font_color", Color(0.28, 0.2, 0.12, 1))
	input_title.add_theme_font_size_override("font_size", 20)
	_voice_input_row.add_child(input_title)
	_voice_mic_btn = Button.new()
	_voice_mic_btn.text = "麦克风"
	_voice_mic_btn.toggle_mode = true
	_voice_mic_btn.custom_minimum_size = Vector2(112, 40)
	_style_like(_voice_mic_btn, replay)
	_voice_mic_btn.add_theme_font_size_override("font_size", 18)
	_voice_mic_btn.pressed.connect(_on_voice_input_pressed.bind("mic"))
	_voice_input_row.add_child(_voice_mic_btn)
	_voice_hold_btn = Button.new()
	_voice_hold_btn.text = "按住蓄力"
	_voice_hold_btn.toggle_mode = true
	_voice_hold_btn.custom_minimum_size = Vector2(112, 40)
	_style_like(_voice_hold_btn, replay)
	_voice_hold_btn.add_theme_font_size_override("font_size", 18)
	_voice_hold_btn.pressed.connect(_on_voice_input_pressed.bind("hold"))
	_voice_input_row.add_child(_voice_hold_btn)
	_voice_calibrate = Button.new()
	_voice_calibrate.text = "校准麦克风"
	_voice_calibrate.custom_minimum_size = Vector2(136, 40)
	_style_like(_voice_calibrate, replay)
	_voice_calibrate.add_theme_font_size_override("font_size", 18)
	_voice_calibrate.pressed.connect(_on_voice_calibrate)
	_voice_input_row.add_child(_voice_calibrate)
	vbox.add_child(_voice_input_row)
	vbox.move_child(_voice_input_row, replay.get_index())
	_voice_status = Label.new()
	_voice_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voice_status.custom_minimum_size = Vector2(0, 20)
	_voice_status.add_theme_font_override("font", FONTS.regular())
	_voice_status.add_theme_color_override("font_color", Color(0.42, 0.34, 0.24, 1))
	_voice_status.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_voice_status)
	vbox.move_child(_voice_status, replay.get_index())
	_voice_confirm = CONFIRM.instantiate()
	add_child(_voice_confirm)
	_voice_confirm.visible = false
	_voice_confirm.confirmed_warning.connect(_on_voice_warning_confirmed)
	_voice_confirm.cancelled.connect(_on_voice_warning_cancelled)
	_update_voice_visibility()


## 设置面板固定为 1280×720；新增声量区后内容可能超出可视高度。
## 把 VBox 放进可触摸拖动的 ScrollContainer，保证底部输入/返回按钮总能到达。
func _wrap_in_scroll() -> void:
	var panel := $Overlay/CenterContainer/Panel as PanelContainer
	var vbox := panel.get_node("VBox") as VBoxContainer
	if panel.has_node("SettingsScroll"):
		return
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.set_script(preload("res://scripts/ui/touch_scroll_container.gd"))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.remove_child(vbox)
	panel.add_child(scroll)
	scroll.add_child(vbox)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _style_like(target: Button, source: Button) -> void:
	for key in ["normal", "pressed", "hover", "disabled", "focus"]:
		target.add_theme_stylebox_override(key, source.get_theme_stylebox(key))
	target.add_theme_font_override("font", source.get_theme_font("font"))
	target.add_theme_font_size_override("font_size", source.get_theme_font_size("font_size"))
	for key in ["font_color", "font_pressed_color", "font_hover_color", "font_disabled_color"]:
		target.add_theme_color_override(key, source.get_theme_color(key))


func _update_voice_visibility() -> void:
	var enabled := VoiceSettings.is_enabled()
	_voice_toggle.set_pressed_no_signal(enabled)
	_voice_toggle.text = "开启" if enabled else "关闭"
	_voice_input_row.visible = enabled
	_voice_mic_btn.set_pressed_no_signal(VoiceSettings.input_mode() == "mic")
	_voice_hold_btn.set_pressed_no_signal(VoiceSettings.input_mode() == "hold")
	_voice_calibrate.visible = enabled and VoiceSettings.input_mode() == "mic"
	_update_voice_status()


func _update_voice_status() -> void:
	if not VoiceSettings.is_enabled():
		_voice_status.text = ""
		return
	if VoiceSettings.input_mode() == "hold":
		_voice_status.text = "按住蓄力不需要麦克风权限。"
		return
	if OS.get_name() == "Android" and not OS.get_granted_permissions().has(VOICE_PERMISSION):
		_voice_status.text = "未授予麦克风权限；可在系统设置中开启，或改用按住蓄力。"
	elif VoiceSettings.has_calibration():
		_voice_status.text = "麦克风已校准。"
	else:
		_voice_status.text = "首次使用建议校准麦克风；不校准也能玩，但档位可能偏保守。"


func _on_voice_toggle_pressed() -> void:
	if _voice_toggle.button_pressed:
		_voice_toggle.text = "开启"
		if not VoiceSettings.is_enabled():
			_voice_confirm.open_warning(VOICE_WARN_TITLE, VOICE_WARN_MSG, VOICE_WARN_OK)
	else:
		_voice_toggle.text = "关闭"
		if VoiceSettings.is_enabled():
			VoiceSettings.set_enabled(false)
		_update_voice_visibility()


func _on_voice_warning_confirmed() -> void:
	VoiceSettings.set_enabled(true)
	_voice_confirm.visible = false
	_update_voice_visibility()
	if VoiceSettings.input_mode() == "mic":
		_request_mic_permission()


func _on_voice_warning_cancelled() -> void:
	_voice_confirm.visible = false
	_update_voice_visibility()


func _on_voice_input_pressed(mode: String) -> void:
	VoiceSettings.set_input_mode(mode)
	_update_voice_visibility()
	if mode == "mic":
		_request_mic_permission()


func _request_mic_permission() -> void:
	if OS.get_name() != "Android":
		_update_voice_status()
		return
	if OS.get_granted_permissions().has(VOICE_PERMISSION):
		_update_voice_status()
		return
	OS.request_permission(VOICE_PERMISSION)
	# 系统权限框是原生的，返回时机不固定；最多等约 5 秒再刷新一次状态。
	for _i in range(300):
		await get_tree().process_frame
		if not is_inside_tree():
			return
		if OS.get_granted_permissions().has(VOICE_PERMISSION):
			break
	_update_voice_status()


func _on_voice_calibrate() -> void:
	# 麦克风校准由 VoiceCalibration 覆盖层完成；未校准时也能按默认比例使用。
	var calibration: Control = preload("res://scripts/ui/voice_calibration.gd").new()
	add_child(calibration)
	calibration.finished.connect(_on_calibration_finished)
	calibration.open()


func _on_calibration_finished(profile: Dictionary) -> void:
	VoiceSettings.set_calibration(profile)
	if bool(profile.get("noisy", false)):
		_voice_status.text = "环境较吵，建议改用按住蓄力；也可重新校准。"
	else:
		_update_voice_status()


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()
		get_viewport().set_input_as_handled()
