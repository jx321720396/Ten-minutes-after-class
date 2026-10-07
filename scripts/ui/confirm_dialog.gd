extends Control

signal confirmed_clear
signal confirmed_keep
signal cancelled

@onready var clear_btn: Button = $CenterContainer/Panel/VBox/ClearBtn
@onready var keep_btn: Button = $CenterContainer/Panel/VBox/KeepBtn
@onready var cancel_btn: Button = $CenterContainer/Panel/VBox/CancelBtn


func _ready():
	clear_btn.pressed.connect(_on_clear)
	keep_btn.pressed.connect(_on_keep)
	cancel_btn.pressed.connect(_on_cancel)


func _on_clear():
	emit_signal("confirmed_clear")


func _on_keep():
	emit_signal("confirmed_keep")


func _on_cancel():
	emit_signal("cancelled")


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_cancel()
