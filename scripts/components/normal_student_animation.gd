extends Node3D
## 可复用纸片人物动画，仅消费表现状态；不引用模拟内核。

const CONFIG := "res://data/ui/normal_student_motion_sample.json"

var settings: Dictionary
var frames := SpriteFrames.new()
var sprite: Sprite3D
var clip := ""
var automatic := true
var _lower: Sprite3D
var _seated_upper: AtlasTexture
var _seated_lower: AtlasTexture
var _elapsed := 0.0
var _definitions: Dictionary


func _ready() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	_definitions = settings["clips"]
	frames.remove_animation("default")
	var atlas: Texture2D = load(str(settings["texture"]))
	for name: String in _definitions:
		var definition: Dictionary = _definitions[name]
		frames.add_animation(name)
		frames.set_animation_speed(name, float(definition["fps"]))
		frames.set_animation_loop(name, bool(definition["loop"]))
		for item: Dictionary in definition["frames"]:
			var region: Array = item["region"]
			var texture := AtlasTexture.new()
			texture.atlas = atlas
			texture.region = Rect2(region[0], region[1], region[2], region[3])
			texture.filter_clip = true
			frames.add_frame(name, texture)
	sprite = Sprite3D.new()
	sprite.name = "Sprite"
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = float(settings["alpha_threshold"])
	sprite.pixel_size = float(settings["pixel_size"])
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	_lower = sprite.duplicate() as Sprite3D
	_lower.name = "SeatedLegs"
	_lower.visible = false
	add_child(_lower)
	var seated: AtlasTexture = frames.get_frame_texture("sit_front", 0)
	var split := float(settings["seated_layers"]["split_y"])
	_seated_upper = AtlasTexture.new()
	_seated_upper.atlas = seated.atlas
	_seated_upper.region = Rect2(seated.region.position, Vector2(seated.region.size.x, split))
	_seated_upper.filter_clip = true
	_seated_lower = AtlasTexture.new()
	_seated_lower.atlas = seated.atlas
	_seated_lower.region = Rect2(
		seated.region.position + Vector2(0, split),
		Vector2(seated.region.size.x, seated.region.size.y - split)
	)
	_seated_lower.filter_clip = true
	clip = str(settings["default_clip"])
	advance(0.0)


func _process(delta: float) -> void:
	if automatic:
		advance(delta)


func play_pose(action: String, direction: String = "front") -> bool:
	var next := action + "_" + ("front" if action == "sit" else direction)
	if not frames.has_animation(next):
		return false
	if next != clip:
		clip = next
		_elapsed = 0.0
	advance(0.0)
	return true


func advance(delta: float) -> void:
	_elapsed += delta
	seek_frame(_elapsed)


func seek_frame(time: float) -> void:
	var count := frames.get_frame_count(clip)
	var index := int(maxf(time, 0.0) * frames.get_animation_speed(clip))
	if frames.get_animation_loop(clip):
		index %= count
	else:
		index = mini(index, count - 1)
	sprite.texture = frames.get_frame_texture(clip, index)
	var item: Dictionary = _definitions[clip]["frames"][index]
	var region: Array = item["region"]
	sprite.position.y = (float(item["baseline"]) - float(region[3]) * 0.5) * sprite.pixel_size
	sprite.offset.x = float(region[2]) * 0.5 - float(item["pivot_x"])
	sprite.flip_h = false
	_lower.visible = clip == "sit_front"
	sprite.billboard = (
		BaseMaterial3D.BILLBOARD_DISABLED if _lower.visible else BaseMaterial3D.BILLBOARD_FIXED_Y
	)
	if _lower.visible:
		var split := float(settings["seated_layers"]["split_y"])
		sprite.texture = _seated_upper
		sprite.position.y = (float(item["baseline"]) - split * 0.5) * sprite.pixel_size
		_lower.texture = _seated_lower
		_lower.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		_lower.position = Vector3(
			0,
			(
				(float(item["baseline"]) - split - (float(region[3]) - split) * 0.5)
				* sprite.pixel_size
			),
			float(settings["seated_layers"]["lower_depth"])
		)
		_lower.offset.x = sprite.offset.x
