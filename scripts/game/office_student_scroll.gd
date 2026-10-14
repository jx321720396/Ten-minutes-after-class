extends "res://scripts/ui/touch_scroll_container.gd"
## 滚动容器会在 _input 消费拖动；先取消按钮触摸，避免松手误选。


func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag and _touch_active:
		for button in get_child(0).get_children():
			if button is Button:
				button.remove_meta("office_touch")
	super._input(event)
