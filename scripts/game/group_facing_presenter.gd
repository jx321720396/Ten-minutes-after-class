class_name GroupFacingPresenter
extends Node
## 真实共同活动的站立朝向；只读会话与站位，不影响行为与随机数。

const SETTINGS := "res://data/ui/student_poses.json"

var _core: Variant
var _actors: Node3D
var _style: Dictionary
var _sprites: Dictionary = {}
var _back: Dictionary = {}


func bind_sources(core: Variant, actors: Node3D) -> void:
	_core = core
	_actors = actors
	process_priority = 2
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	_style = settings["group_facing"]
	for index in range(actors.actor_count()):
		var actor: Node3D = actors.actor_for(index)
		var sprite := actor.get_node_or_null("Sprite") as Sprite3D
		var binding: Dictionary = settings["bindings"].get(
			actor.get_meta("appearance_sprite", ""), {}
		)
		if sprite == null or not binding.has("standing_back"):
			continue
		var texture := load(str(binding["standing_back"])) as Texture2D
		if texture == null:
			continue
		var back_pixel_size := sprite.pixel_size * float(binding["back_pixel_scale"])
		var foot_y := (
			sprite.position.y
			+ (
				(sprite.texture.get_height() * 0.5 - float(binding["standing_floor_pixel"]))
				* sprite.pixel_size
			)
		)
		_sprites[index] = {
			"sprite": sprite,
			"front": sprite.texture,
			"back": texture,
			"front_y": sprite.position.y,
			"front_pixel_size": sprite.pixel_size,
			"back_pixel_size": back_pixel_size,
			"back_y":
			(
				foot_y
				- (
					(texture.get_height() * 0.5 - float(binding["back_floor_pixel"]))
					* back_pixel_size
				)
			),
			"showing_back": false,
		}


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	if _core == null or not is_instance_valid(_actors):
		return
	var camera := _actors.get_viewport().get_camera_3d()
	if camera == null:
		return
	var direction := -camera.global_basis.z
	var forward := Vector2(direction.x, direction.z).normalized()
	var positions := {}
	var standing := {}
	for index in _sprites:
		var actor: Node3D = _actors.actor_for(index)
		var sprite: Sprite3D = _sprites[index]["sprite"]
		var walker := actor.get_node_or_null("Walker")
		if not _core.is_present(index) or not actor.visible:
			continue
		if walker != null and walker.is_moving():
			continue
		var position := actor.global_position
		if sprite.visible:
			standing[index] = true
		else:
			# 坐姿同伴仍是站立请教者的面向目标，但不换成站立背影。
			position = _actors.sit_position_of(index)
		positions[index] = Vector2(position.x, position.z)
	_back = back_members(_core.get_active_sessions(), positions, forward, _style, _back)
	for index in _sprites:
		var seated: Node = _actors._seated_poses.get(index)
		if seated != null:
			seated.set_group_back(not standing.has(index) and _back.has(index))
		_apply(_sprites[index], standing.has(index) and _back.has(index))


func _apply(entry: Dictionary, back: bool) -> void:
	if bool(entry["showing_back"]) == back:
		return
	var sprite: Sprite3D = entry["sprite"]
	sprite.texture = entry["back"] if back else entry["front"]
	sprite.pixel_size = entry["back_pixel_size"] if back else entry["front_pixel_size"]
	sprite.position.y = entry["back_y"] if back else entry["front_y"]
	if back:
		sprite.flip_h = false
	entry["showing_back"] = back


static func back_members(
	sessions: Array,
	positions: Dictionary,
	forward: Vector2,
	style: Dictionary,
	previous: Dictionary = {}
) -> Dictionary:
	var result := {}
	var side := Vector2(-forward.y, forward.x)
	for session in sessions:
		var members: Array = []
		var center := Vector2.ZERO
		for index in session["members"]:
			if positions.has(index):
				members.append(index)
				center += positions[index]
		if members.size() < 2:
			continue
		for index in members:
			var position: Vector2 = positions[index]
			var toward := (center - position) / float(members.size() - 1) - position
			var depth := toward.dot(forward)
			var threshold := float(style["min_depth_m"])
			if previous.has(index):
				threshold -= float(style["hysteresis_m"])
			if (
				depth > threshold
				and depth > absf(toward.dot(side)) * float(style["depth_to_side_ratio"])
			):
				result[index] = true
	return result
