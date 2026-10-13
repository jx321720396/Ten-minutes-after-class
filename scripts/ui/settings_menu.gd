extends Control

signal closed
## 「重看教程」被点击：教室里直接重放；主菜单里记标记下局生效。
signal replay_requested

@onready var back_btn: Button = $Overlay/CenterContainer/Panel/VBox/BackBtn
@onready var replay_btn: Button = $Overlay/CenterContainer/Panel/VBox/ReplayBtn


func _ready():
	back_btn.pressed.connect(_on_back)
	replay_btn.pressed.connect(_on_replay)


func _on_replay():
	replay_requested.emit()
	emit_signal("closed")


func _on_back():
	emit_signal("closed")


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()
		get_viewport().set_input_as_handled()
