extends Control

signal closed

@onready var back_btn: Button = $Overlay/CenterContainer/Panel/VBox/BackBtn


func _ready():
	back_btn.pressed.connect(_on_back)


func _on_back():
	emit_signal("closed")


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()
		get_viewport().set_input_as_handled()
