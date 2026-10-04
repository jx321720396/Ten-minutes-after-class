extends Control

@onready var pause_menu: Control = $PauseMenu

func _ready():
	pause_menu.resume_game.connect(_on_resume)

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel") and not pause_menu.visible:
		pause_menu.visible = true
		get_tree().paused = true

func _on_resume():
	pass
