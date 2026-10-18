extends Control

signal resume_game

@onready var panel: PanelContainer = $Panel
@onready var resume_btn: Button = $Panel/VBox/MenuVBox/ResumeBtn
@onready var save_btn: Button = $Panel/VBox/MenuVBox/SaveBtn
@onready var setting_btn: Button = $Panel/VBox/MenuVBox/SettingBtn
@onready var quit_btn: Button = $Panel/VBox/MenuVBox/QuitBtn
@onready var settings_panel: Control = $SettingsMenu


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_btn.pressed.connect(_on_resume)
	save_btn.pressed.connect(_on_save)
	setting_btn.pressed.connect(_on_setting)
	quit_btn.pressed.connect(_on_quit_to_menu)
	settings_panel.closed.connect(_on_close_settings)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	_center_panel.call_deferred()
	TouchBind.bind_tree(self)


func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_center_panel()


func _center_panel():
	if panel == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.custom_minimum_size = Vector2.ZERO
	panel.size = viewport


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		if settings_panel.visible:
			_on_close_settings()
		else:
			_on_resume()
		get_viewport().set_input_as_handled()


func _on_resume():
	visible = false
	get_tree().paused = false
	emit_signal("resume_game")


## 手动存档：把当前局快照写盘（单槽），并给轻提示。暂停时计时器按 process_always 走。
func _on_save() -> void:
	var ok := GameState.save_snapshot()
	save_btn.disabled = true
	save_btn.text = "已保存" if ok else "存档失败"
	await get_tree().create_timer(1.2).timeout
	save_btn.text = "保存"
	save_btn.disabled = false


func _on_quit_to_menu() -> void:
	get_tree().paused = false
	var error := get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		get_tree().paused = true
		push_error("无法返回主菜单：%s" % error_string(error))


func _on_setting():
	settings_panel.visible = true


func _on_close_settings():
	settings_panel.visible = false
	_on_resume()
