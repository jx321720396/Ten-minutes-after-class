extends Control

signal closed

@onready var back_btn: Button = $CenterContainer/Panel/VBox/BackBtn


func _ready():
	back_btn.pressed.connect(_on_back)
	TouchBind.bind_tree(self)


func _on_back():
	emit_signal("closed")


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()
