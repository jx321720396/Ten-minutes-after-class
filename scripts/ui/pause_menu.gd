extends Control

signal resume_game

@onready var panel: PanelContainer = $Panel
@onready var resume_btn: Button = $Panel/VBox/MenuVBox/ResumeBtn
@onready var setting_btn: Button = $Panel/VBox/MenuVBox/SettingBtn
@onready var quit_btn: Button = $Panel/VBox/MenuVBox/QuitBtn
@onready var settings_panel: Control = $SettingsMenu


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_btn.pressed.connect(_on_resume)
	setting_btn.pressed.connect(_on_setting)
	quit_btn.pressed.connect(_on_quit_to_menu)
	settings_panel.closed.connect(_on_close_settings)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	_center_panel.call_deferred()


func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_center_panel()


func _center_panel():
	if panel == null:
		return
	var ps := panel.size
	panel.offset_left = -ps.x / 2.0
	panel.offset_top = -ps.y / 2.0
	panel.offset_right = ps.x / 2.0
	panel.offset_bottom = ps.y / 2.0


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
