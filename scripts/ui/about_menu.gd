extends Control

signal closed

@onready var back_btn: Button = $CenterContainer/Panel/VBox/BackBtn


func _ready():
	get_viewport().size_changed.connect(_fit_fullscreen)
	_fit_fullscreen()
	back_btn.pressed.connect(_on_back)
	TouchBind.bind_tree(self)


func _fit_fullscreen() -> void:
	preload("res://scripts/ui/fullscreen_panel.gd").fit(
		$CenterContainer, $CenterContainer/Panel, Vector2(1280, 720)
	)


func _on_back():
	emit_signal("closed")


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()
