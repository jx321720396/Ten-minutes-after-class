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
		# 消费掉本次返回：否则会继续传给教室，顺带打开暂停菜单。
		get_viewport().set_input_as_handled()
