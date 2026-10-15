extends Node3D
## Standalone art probe. No simulation, navigation or production actor writes.

const CONFIG := "res://data/ui/samples/chenyang_parts_sample.json"
var joints: Dictionary = {}
var settings: Dictionary


func _ready() -> void:
	settings = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var atlas := load(str(settings.atlas)) as Texture2D
	for part in settings.parts:
		var joint := Node3D.new()
		joint.name = part.name
		var parent: Node3D = self if part.parent == "" else joints[part.parent]
		parent.add_child(joint)
		joint.position = Vector3(part.position[0], part.position[1], part.position[2])
		joints[part.name] = joint
		var region := AtlasTexture.new()
		region.atlas = atlas
		region.region = Rect2(part.region[0], part.region[1], part.region[2], part.region[3])
		region.filter_clip = true
		var sprite := Sprite3D.new()
		sprite.texture = region
		sprite.pixel_size = 1.0 / region.get_height()
		sprite.scale = Vector3(
			part.size[0] / (region.get_width() * sprite.pixel_size), part.size[1], 1
		)
		sprite.offset = Vector2(
			(0.5 - part.anchor[0]) * region.get_width(),
			(part.anchor[1] - 0.5) * region.get_height()
		)
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.alpha_scissor_threshold = 0.5
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		sprite.shaded = false
		if part.has("blend"):
			var material := ShaderMaterial.new()
			material.shader = load("res://tools/art_samples/joint_overlap.gdshader")
			material.set_shader_parameter("atlas_texture", atlas)
			material.set_shader_parameter("region_top", float(part.region[1]) / atlas.get_height())
			material.set_shader_parameter(
				"region_height", float(part.region[3]) / atlas.get_height()
			)
			material.set_shader_parameter("fade_top", part.blend[0])
			material.set_shader_parameter("fade_bottom", part.blend[1])
			material.render_priority = int(part.blend[2])
			sprite.material_override = material
		joint.add_child(sprite)
	set_sample_pose("idle", 0.0)


func set_sample_pose(mode: String, time: float) -> void:
	for joint in joints.values():
		joint.rotation = Vector3.ZERO
	var pose: Dictionary = settings.poses[mode]
	for key in pose:
		var value: Array = pose[key]
		joints[key].rotation.z = deg_to_rad(value[0] + sin(time * value[2] + value[3]) * value[1])
	var pelvis: Node3D = joints.pelvis
	pelvis.position.y = settings.parts[0].position[1]
	if mode == "walk":
		pelvis.position.y += (
			absf(sin(time * settings.walk_bob.frequency)) * settings.walk_bob.height
		)
		for key in settings.walk_depth:
			var cycle: Array = settings.walk_depth[key]
			var angle: float = sin(time * cycle[1] + cycle[2]) * cycle[0]
			if str(key).begins_with("shin"):
				angle = maxf(angle, 0.0)
			joints[key].rotation.x = deg_to_rad(angle)
