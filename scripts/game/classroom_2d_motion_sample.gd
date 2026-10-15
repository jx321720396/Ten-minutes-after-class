extends Node2D
## 纯二维固定俯视美术试片，移动路径仅用于演示，不属于玩法决策。

const CONFIG := "res://data/ui/classroom_2d_motion_sample.json"
var settings: Dictionary
var actor: Sprite2D
var shadow: Polygon2D
var backrest: Sprite2D
var frames: Array[AtlasTexture] = []
var automatic := true
var elapsed := 0.0


func _ready() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	get_window().content_scale_size = Vector2i(settings["canvas"][0], settings["canvas"][1])
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var background := Sprite2D.new()
	background.texture = load(str(settings["background"]))
	background.centered = false
	add_child(background)
	var texture: Texture2D = load(str(settings["character"]))
	var cell := _v(settings["cell"])
	for index in 8:
		var frame := AtlasTexture.new()
		frame.atlas = texture
		frame.region = Rect2(Vector2(index % 4, index / 4) * cell, cell)
		frames.append(frame)
	actor = Sprite2D.new()
	shadow = Polygon2D.new()
	var points := PackedVector2Array()
	for index in 32:
		var angle := TAU * index / 32.0
		points.append(Vector2(cos(angle), sin(angle)) * _v(settings["shadow_size"]) * 0.5)
	shadow.polygon = points
	shadow.color = Color(str(settings["shadow_color"]))
	add_child(shadow)
	actor.name = "Student"
	actor.centered = false
	actor.scale = Vector2.ONE * float(settings["scale"])
	add_child(actor)
	backrest = Sprite2D.new()
	backrest.centered = false
	var region: Array = settings["backrest_region"]
	var chair := AtlasTexture.new()
	chair.atlas = background.texture
	chair.region = Rect2(region[0], region[1], region[2], region[3])
	backrest.texture = chair
	backrest.position = chair.region.position
	add_child(backrest)
	seek(0.0)


func _process(delta: float) -> void:
	if automatic:
		elapsed = fmod(elapsed + delta, duration())
		seek(elapsed)


func duration() -> float:
	return (
		float(settings["walk_duration"])
		+ float(settings["sit_duration"])
		+ float(settings["hold_duration"])
	)


func seek(time: float) -> void:
	var walk_time := float(settings["walk_duration"])
	var sit_time := float(settings["sit_duration"])
	var path: Array = settings["path"]
	if time < walk_time:
		actor.position = _path_position(path, clampf(time / walk_time, 0.0, 1.0))
		actor.offset = -_v(settings["walk_pivot"])
		_walk_pose(time)
		backrest.visible = false
		shadow.visible = true
		shadow.position = actor.position
	else:
		var progress := clampf((time - walk_time) / sit_time, 0.0, 1.0)
		actor.position = _v(path.back()).lerp(_v(settings["seat"]), smoothstep(0.0, 1.0, progress))
		actor.modulate.a = 1.0
		if progress < 1.0:
			actor.offset = -_v(settings["walk_pivot"])
			actor.texture = frames[1]
		else:
			actor.offset = -_v(settings["sit_pivots"][3])
			actor.texture = frames[7]
		backrest.visible = progress >= 1.0
		shadow.visible = false


func _walk_pose(time: float) -> void:
	var phase := time * float(settings["walk_fps"])
	var index := int(phase) % 4
	actor.texture = frames[index]
	actor.modulate.a = 1.0


func _path_position(path: Array, progress: float) -> Vector2:
	var total := 0.0
	for index in path.size() - 1:
		total += _v(path[index]).distance_to(_v(path[index + 1]))
	var remaining := total * progress
	for index in path.size() - 1:
		var start := _v(path[index])
		var end := _v(path[index + 1])
		var length := start.distance_to(end)
		if remaining <= length and length > 0.0:
			return start.lerp(end, remaining / length)
		remaining -= length
	return _v(path.back())


func _v(value: Array) -> Vector2:
	return Vector2(value[0], value[1])
