extends Node3D
## 教室场景导航；模拟逻辑由内核独立负责。

@onready var pause_menu: Control = $UI/PauseMenu


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		pause_menu.show()
		get_tree().paused = true
		get_viewport().set_input_as_handled()
