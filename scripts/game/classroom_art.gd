class_name ClassroomArt
extends Node3D
## 中国高中教室表现：数据驱动装饰、共享材质、独立 RNG；不改变模拟或空间几何。

const STYLE_PATH := "res://data/ui/classroom_art.json"
const SHADOW_SHADER := "res://assets/shaders/classroom_contact_shadow.gdshader"

@export var enabled := true

var _style: Dictionary = {}
var _materials: Dictionary = {}
var _room: Node3D
var _clock: Node
var _font: Font
var _scene_cache: Dictionary = {}
var _camera_base := Transform3D.IDENTITY
var _camera_origin_x := 0.0
var _camera_follow_bound := false
var _camera_offset := 0.0
var _camera_follow_enabled := false


func _ready() -> void:
	if not enabled:
		return
	_style = JSON.parse_string(FileAccess.get_file_as_string(STYLE_PATH))
	if _style.is_empty():
		push_error("ClassroomArt：缺少教室美术配置")
		return
	_room = get_parent() as Node3D
	_font = load(str(_style["font"])) as Font
	_make_materials()
	_apply_materials(_room)
	_apply_lighting()
	_apply_camera()
	_hide_replaced_details()
	rebuild()
	_bind_clock.call_deferred()


func _apply_camera() -> void:
	var definition: Dictionary = _style.get("camera", {})
	if definition.is_empty():
		return
	var camera := _room.get_node("Camera3D") as Camera3D
	camera.fov = float(definition["fov"])
	camera.look_at_from_position(
		ClassroomArtProps.vector(definition["position"]),
		ClassroomArtProps.vector(definition["target"])
	)
	_camera_base = camera.global_transform
	_camera_follow_enabled = bool(definition.get("follow", {}).get("enabled", false))


func set_camera_follow_enabled(value: bool) -> void:
	_camera_follow_enabled = value
	if not value and _room != null:
		_camera_offset = 0.0
		_room.get_node("Camera3D").global_transform = _camera_base


func _unhandled_key_input(event: InputEvent) -> void:
	if not enabled or _style.get("camera", {}).get("follow", {}).is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		set_camera_follow_enabled(not _camera_follow_enabled)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not enabled or not _camera_follow_enabled or _room == null:
		return
	var player := _room.get_node("Player") as PlayerController
	if player._player_actor == null:
		return
	if not _camera_follow_bound:
		_camera_origin_x = player._player_actor.global_position.x
		_camera_follow_bound = true
	var follow: Dictionary = _style["camera"]["follow"]
	var displacement := player._player_actor.global_position.x - _camera_origin_x
	var desired := clampf(
		(displacement - float(follow["dead_zone"])) * float(follow["gain"]),
		0.0,
		float(follow["max_offset"])
	)
	_camera_offset = lerpf(_camera_offset, desired, 1.0 - exp(-float(follow["speed"]) * delta))
	_room.get_node("Camera3D").global_position = (
		_camera_base.origin + Vector3.RIGHT * _camera_offset
	)


func rebuild() -> void:
	if not enabled or _style.is_empty():
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var builder := ClassroomArtProps.new(_materials, _font)
	var desks := _group("DeskDetails")
	var rng := RandomNumberGenerator.new()
	var state := get_node_or_null("/root/GameState")
	var seed_value := int(state.seed) if state != null else 0
	rng.seed = seed_value ^ int(_style["decoration_seed_salt"])
	var variants: Array = _style["desk_variants"]
	var offset := rng.randi_range(0, variants.size() - 1)
	var seats := _room.get_node("Seats")
	for index in range(seats.get_child_count()):
		var seat := seats.get_child(index) as Node3D
		var variant_index := (index + offset) % variants.size()
		var variant := str(variants[variant_index])
		var placement := {"name": str(seat.name), "position": [0, 0, 0]}
		var anchor := Node3D.new()
		anchor.name = str(seat.name) + "Anchor"
		desks.add_child(anchor)
		anchor.global_transform = seat.global_transform
		var details := builder.add_prop(anchor, _style["props"][variant], placement)
		anchor.set_meta("variant", variant)
		details.set_meta("variant", variant)
	_build_placements(builder, _group("RoomDetails"), _style["room_details"])
	_build_placements(builder, _group("CampusExterior"), _style["exterior"])
	_build_scene_placements(_group("SceneDetails"))
	builder.flush(_group("Batches"))
	_add_actor_shadows()


func _group(group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	add_child(group)
	return group


func _build_placements(builder: ClassroomArtProps, parent: Node3D, placements: Array) -> void:
	for placement in placements:
		builder.add_prop(parent, _style["props"][placement["prop"]], placement)


func _build_scene_placements(parent: Node3D) -> void:
	for placement in _style.get("scene_details", []):
		var path := str(placement["scene"])
		if not _scene_cache.has(path):
			var resource := load(path) as PackedScene
			if resource == null:
				push_error("ClassroomArt：无法加载表现组件 " + path)
				continue
			_scene_cache[path] = resource
		var instance := (_scene_cache[path] as PackedScene).instantiate() as Node3D
		instance.name = str(placement["name"])
		parent.add_child(instance)
		if placement.has("anchor_node"):
			var anchor := _room.get_node(str(placement["anchor_node"])) as Node3D
			instance.global_transform = anchor.global_transform
			instance.translate(ClassroomArtProps.vector(placement.get("position", [0, 0, 0])))
			instance.rotate_y(deg_to_rad(float(placement.get("yaw", 0))))
		else:
			instance.position = ClassroomArtProps.vector(placement.get("position", [0, 0, 0]))
			instance.rotation_degrees = ClassroomArtProps.vector(
				placement.get("rotation", [0, 0, 0])
			)
		instance.scale *= ClassroomArtProps.vector(placement.get("scale", [1, 1, 1]))


func _make_materials() -> void:
	for key in _style["materials"]:
		var definition: Dictionary = _style["materials"][key]
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(str(definition["color"]))
		material.roughness = float(definition["roughness"])
		material.metallic = float(definition.get("metallic", 0.0))
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if definition.has("texture"):
			material.albedo_texture = load(str(definition["texture"]))
			material.uv1_scale = ClassroomArtProps.vector(definition.get("uv_scale", [1, 1, 1]))
			material.uv1_triplanar = bool(definition.get("triplanar", false))
		if definition.has("emission"):
			material.emission_enabled = true
			material.emission = Color(str(definition["emission"]))
			material.emission_energy_multiplier = float(definition["emission_energy"])
		_materials[key] = material


func _apply_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			var source := mesh_node.mesh.surface_get_material(0)
			if source != null:
				var source_name := source.resource_path.get_file().get_basename()
				if _style["material_replacements"].has(source_name):
					mesh_node.material_override = _materials[_style["material_replacements"][source_name]]
	for child in node.get_children():
		if child != self:
			_apply_materials(child)


func _hide_replaced_details() -> void:
	for path in _style["hide_nodes"]:
		var node := _room.get_node_or_null(str(path)) as Node3D
		if node != null:
			node.visible = false


func _apply_lighting() -> void:
	var lighting: Dictionary = _style["lighting"]
	var environment_node := _room.get_node("WorldEnvironment") as WorldEnvironment
	# 只复制运行时资源，原 .tres / 场景 Environment 不被写回。
	var environment := environment_node.environment.duplicate() as Environment
	environment_node.environment = environment
	environment.background_color = Color(str(lighting["background"]))
	environment.ambient_light_color = Color(str(lighting["ambient_color"]))
	environment.ambient_light_energy = float(lighting["ambient_energy"])
	for definition in lighting["lights"]:
		var light := _room.get_node(str(definition["path"])) as OmniLight3D
		light.light_energy = float(definition["energy"])
		light.light_color = Color(str(definition["color"]))
	var sunlight := DirectionalLight3D.new()
	sunlight.name = "WindowDaylight"
	sunlight.rotation_degrees = ClassroomArtProps.vector(lighting["sun_rotation"])
	sunlight.light_energy = float(lighting["sun_energy"])
	sunlight.light_color = Color(str(lighting["sun_color"]))
	sunlight.shadow_enabled = bool(lighting.get("sun_shadows", false))
	sunlight.directional_shadow_max_distance = float(lighting["shadow_distance"])
	if lighting.get("shadow_mode", "") == "orthogonal":
		sunlight.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# 灯光不归属可重建装饰，避免每次重建增加一盏灯。
	_room.add_child.call_deferred(sunlight)


func _add_actor_shadows() -> void:
	var definition: Dictionary = _style["contact_shadow"]
	var material := ShaderMaterial.new()
	material.shader = load(SHADOW_SHADER)
	material.set_shader_parameter("shadow_color", Color(str(definition["color"])))
	material.set_shader_parameter("softness", float(definition["softness"]))
	material.set_shader_parameter("floor_height", float(definition["height"]))
	var mesh := PlaneMesh.new()
	var size: Array = definition["size"]
	mesh.size = Vector2(float(size[0]), float(size[1]))
	mesh.material = material
	for actor in _room.get_node("Actors").get_children():
		var existing := actor.get_node_or_null("ContactShadow")
		if existing != null:
			actor.remove_child(existing)
			existing.queue_free()
		var shadow := MeshInstance3D.new()
		shadow.name = "ContactShadow"
		shadow.mesh = mesh
		shadow.position.y = float(definition["height"]) - float(actor.position.y)
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		actor.add_child(shadow)


func _bind_clock() -> void:
	_clock = _room.get_node("Clock")
	if not _clock.phase_changed.is_connected(_on_phase_changed):
		_clock.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(_clock.snapshot())


func _on_phase_changed(snapshot: Dictionary) -> void:
	var phase := str(snapshot.get("phase_id", "morning_break"))
	var definition: Dictionary = _style["phase_light"].get(
		phase, _style["phase_light"]["morning_break"]
	)
	var light := _room.get_node("WindowDaylight") as DirectionalLight3D
	light.light_color = Color(str(definition["color"]))
	light.light_energy = float(definition["energy"])


func generated_count() -> int:
	var count := 0
	var batches := get_node_or_null("Batches")
	if batches != null:
		for batch in batches.get_children():
			count += (batch as MultiMeshInstance3D).multimesh.instance_count
	return count
