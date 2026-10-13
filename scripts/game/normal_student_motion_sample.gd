extends Node3D
## 正常比例人物独立动作试片；固定正面相机，坐姿始终正面。

const ACTOR := preload("res://scenes/components/normal_student_animation.tscn")
const CONFIG := "res://data/ui/normal_student_motion_sample.json"

var settings: Dictionary
var actor: Node3D
var automatic := true
var elapsed := 0.0
var _direction := "front"
var _status: Label


func _ready() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	get_node("Original").queue_free()
	get_node("Student").queue_free()
	get_node("Sample").position = Vector3.ZERO
	var camera := get_node("Camera3D") as Camera3D
	camera.size = float(settings["camera_size"])
	camera.look_at_from_position(_v(settings["camera_position"]), _v(settings["camera_target"]))
	actor = ACTOR.instantiate()
	add_child(actor)
	actor.automatic = false
	_build_controls()
	seek(0.0)


func _process(delta: float) -> void:
	if automatic:
		elapsed = fmod(elapsed + delta, duration())
		seek(elapsed)
	else:
		actor.advance(delta)
	_status.text = "当前：%s  |  %s" % [actor.clip, "自动演示" if automatic else "手动预览"]


func duration() -> float:
	return (
		float(settings["idle_duration"])
		+ float(settings["walk_duration"])
		+ float(settings["chat_duration"])
		+ float(settings["sit_duration"])
	)


func seat_floor_position() -> Vector3:
	return get_node("Sample/SitPoint").global_position


func seek(time: float) -> void:
	var idle := float(settings["idle_duration"])
	var walk := float(settings["walk_duration"])
	var chat := float(settings["chat_duration"])
	var start := _v(settings["path_start"])
	var goal := _v(settings["walk_goal"])
	var seat := seat_floor_position()
	if time < idle:
		actor.position = start
		actor.play_pose("idle", "front")
		actor.seek_frame(time)
	elif time < idle + walk:
		actor.position = start.lerp(goal, clampf((time - idle) / walk, 0.0, 1.0))
		actor.play_pose("walk", "right")
		actor.seek_frame(time - idle)
	elif time < idle + walk + chat:
		actor.position = goal
		actor.play_pose("chat", "front")
		actor.seek_frame(time - idle - walk)
	else:
		actor.position = seat
		actor.play_pose("sit", "front")
		actor.seek_frame(0.0)


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(24, 20)
	layer.add_child(panel)
	panel.add_theme_font_override("font", preload("res://scripts/ui/game_fonts.gd").regular())
	var title := Label.new()
	title.text = "正常比例人物 · 帧动画小样"
	panel.add_child(title)
	var actions := HBoxContainer.new()
	panel.add_child(actions)
	for entry: Array in [["站立", "idle"], ["行走", "walk"], ["聊天", "chat"], ["正面坐姿", "sit"]]:
		_button(actions, entry[0], _select_pose.bind(entry[1]))
	var directions := HBoxContainer.new()
	panel.add_child(directions)
	for entry: Array in [["正面", "front"], ["背面", "back"], ["左侧", "left"], ["右侧", "right"]]:
		_button(directions, entry[0], _select_direction.bind(entry[1]))
	_button(directions, "重播演示", _restart)
	_status = Label.new()
	panel.add_child(_status)


func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func _select_pose(action: String) -> void:
	automatic = false
	actor.position = seat_floor_position() if action == "sit" else _v(settings["path_start"])
	actor.play_pose(action, _direction)


func _select_direction(direction: String) -> void:
	_direction = direction
	automatic = false
	actor.play_pose(actor.clip.get_slice("_", 0), direction)


func _restart() -> void:
	automatic = true
	elapsed = 0.0
	seek(elapsed)


func _v(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
