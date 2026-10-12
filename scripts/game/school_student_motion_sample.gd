extends Node3D
## 独立美术动作试片；不参与玩法行为决策，也不接入主教室。

const CONFIG := "res://data/ui/school_student_motion_sample.json"
var settings: Dictionary
var elapsed := 0.0
var automatic := true
var actor: Node3D
var sprite: Sprite3D
var walk_frames: Array[AtlasTexture] = []
var sit_frames: Array[AtlasTexture] = []


func _ready() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	get_node("Original").queue_free()
	get_node("Student").queue_free()
	get_node("Sample").position = Vector3.ZERO
	var camera := get_node("Camera3D") as Camera3D
	camera.size = float(settings["camera_size"])
	camera.look_at_from_position(_v(settings["camera_position"]), _v(settings["camera_target"]))
	actor = load("res://scenes/characters/school_student_sample.tscn").instantiate()
	actor.name = "MotionStudent"
	add_child(actor)
	sprite = actor.get_node("Sprite") as Sprite3D
	_make_frames("walk", walk_frames)
	_make_frames("sit", sit_frames)
	seek(0.0)


func _make_frames(clip: String, frames: Array[AtlasTexture]) -> void:
	var texture: Texture2D = load(str(settings[clip + "_texture"]))
	for region: Array in settings[clip + "_regions"]:
		var frame := AtlasTexture.new()
		frame.atlas = texture
		frame.region = Rect2(region[0], region[1], region[2], region[3])
		frames.append(frame)


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
		var progress := clampf(time / walk_time, 0.0, 1.0) * (path.size() - 1)
		var segment := mini(int(progress), path.size() - 2)
		actor.position = _v(path[segment]).lerp(_v(path[segment + 1]), progress - segment)
		_pose("walk", int(time * float(settings["walk_fps"])) % walk_frames.size())
	else:
		var progress := clampf((time - walk_time) / sit_time, 0.0, 1.0)
		actor.position = _v(path.back()).lerp(_v(settings["seat"]), smoothstep(0.0, 1.0, progress))
		_pose("sit", mini(int(progress * sit_frames.size()), sit_frames.size() - 1))


func _pose(clip: String, index: int) -> void:
	var frames := walk_frames if clip == "walk" else sit_frames
	var frame := frames[index]
	var pixels := float(settings[clip + "_pixel_size"])
	sprite.texture = frame
	sprite.pixel_size = pixels
	sprite.position.y = (float(settings[clip + "_baseline"]) - frame.region.size.y * 0.5) * pixels
	sprite.offset.x = frame.region.size.x * 0.5 - float(settings[clip + "_pivots"][index])


func _v(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
