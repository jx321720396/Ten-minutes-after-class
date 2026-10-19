class_name ChatActivityBubble
extends CanvasLayer
## 公开行为符号粒子：只读会话 / activity_of，独立 RNG，不参与内核结算。
## 保留聊天加入揭晓的 hide_member / show_member 接口；双方独立发射。

const STYLE_PATH := "res://data/ui/behavior_particles.json"
const Fonts = preload("res://scripts/ui/game_fonts.gd")

var _core: Variant = null
var _actors: Node3D = null
var _clock: SimulationClock = null
var _time_flow: TimeFlow = null
var _bubbles: Dictionary = {}
var _hidden: Dictionary = {}
var _settings: Dictionary = {}
var _styles: Dictionary = {}
var _chat_settings: Dictionary = {}
var _retiring: Array[Dictionary] = []
var _icons: Dictionary = {}
## 位图字形（白色贴图，运行时按 style 配色 modulate）；缺失或未导入时静默回退字体字形。
var _bitmaps: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_load_style()


func bind_core(core: Variant) -> void:
	if _core == core:
		return
	clear()
	_core = core
	_load_style()
	if is_instance_valid(_core):
		_rng.seed = int(_core.seed()) + int(_settings["seed_offset"])
	_sync()


func bind_actors(actors: Node3D) -> void:
	_actors = actors


func bind_clock(clock: SimulationClock) -> void:
	_clock = clock


func bind_time_flow(flow: TimeFlow) -> void:
	_time_flow = flow


func hide_member(index: int) -> void:
	_hidden[index] = true
	for k in range(_retiring.size() - 1, -1, -1):
		if int(_retiring[k]["index"]) == index:
			(_retiring[k]["root"] as Control).queue_free()
			_retiring.remove_at(k)
	_sync()


func show_member(index: int) -> void:
	_hidden.erase(index)
	_sync()


func clear_hidden() -> void:
	_hidden.clear()
	_sync()


func clear() -> void:
	for emitter in _bubbles.values():
		(emitter["root"] as Control).queue_free()
	for emitter in _retiring:
		(emitter["root"] as Control).queue_free()
	_retiring.clear()
	_bubbles.clear()
	_hidden.clear()


func bubble_count() -> int:
	var count := 0
	for index in _bubbles:
		if has_bubble(int(index)):
			count += 1
	return count


func has_bubble(index: int) -> bool:
	return emitter_kind(index) == "chat"


func emitter_kind(index: int) -> String:
	return str(_bubbles.get(index, {}).get("kind", ""))


func particle_snapshot(index: int) -> Array:
	var out: Array = []
	for particle in _bubbles.get(index, {}).get("particles", []):
		out.append(_sample(particle))
	return out


func _process(delta: float) -> void:
	_sync()
	if not is_instance_valid(_core):
		return
	var stopped := is_instance_valid(_clock) and _clock.is_paused()
	if is_instance_valid(_time_flow):
		# TimeFlow 仅提供冻结门禁，不把世界倍速乘入粒子动画。
		stopped = stopped or _time_flow.scale_delta(delta) <= 0.0
	var visual_delta := 0.0 if stopped else maxf(delta, 0.0)
	if visual_delta > 0.0:
		_advance(visual_delta)
	_layout()


func _sync() -> void:
	var wanted := {}
	var chat_groups := {}
	if is_instance_valid(_core):
		for i in range(int(_core.node_count())):
			var kind := str(_core.activity_of(i))
			if kind != "chat" and _styles.has(kind):
				wanted[i] = kind
		for session in _core.get_active_sessions():
			if str(session["kind"]) != "chat":
				continue
			var members: Array = session["members"]
			for member in members:
				if not _hidden.has(int(member)):
					wanted[int(member)] = "chat"
					chat_groups[int(member)] = {
						"slot": int(session["session_id"]) % _styles["chat"]["colors"].size(),
						"phase":
						members.find(member) * float(_chat_settings["member_stagger_seconds"])
					}
	for index in _bubbles.keys():
		if not wanted.has(index) or wanted[index] != emitter_kind(index):
			var old: Dictionary = _bubbles[index]
			if old["kind"] == "chat" and not _hidden.has(index):
				old["retire_left"] = float(_chat_settings["end_fade_seconds"])
				_retiring.append(old)
			else:
				(old["root"] as Control).queue_free()
			_bubbles.erase(index)
	for index in wanted:
		if _bubbles.has(index):
			if chat_groups.has(index):
				_bubbles[index]["slot"] = chat_groups[index]["slot"]
			continue
		var root := Control.new()
		root.name = "Symbols_%d" % index
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		var group: Dictionary = chat_groups.get(index, {})
		_bubbles[index] = {
			"root": root,
			"index": index,
			"kind": wanted[index],
			"timer": group.get("phase", 0.0),
			"slot": group.get("slot", 0),
			"particles": []
		}


func _advance(delta: float) -> void:
	for k in range(_retiring.size() - 1, -1, -1):
		var emitter: Dictionary = _retiring[k]
		emitter["retire_left"] = float(emitter["retire_left"]) - delta
		(emitter["root"] as Control).modulate.a = maxf(
			0.0, float(emitter["retire_left"]) / float(_chat_settings["end_fade_seconds"])
		)
		if float(emitter["retire_left"]) <= 0.0:
			(emitter["root"] as Control).queue_free()
			_retiring.remove_at(k)
	for index in _bubbles:
		var emitter: Dictionary = _bubbles[index]
		var settings := _settings_for(str(emitter["kind"]))
		var particles: Array = emitter["particles"]
		for k in range(particles.size() - 1, -1, -1):
			var particle: Dictionary = particles[k]
			particle["age"] = float(particle["age"]) + delta
			if float(particle["age"]) >= float(settings["lifetime_seconds"]):
				(particle["node"] as Control).queue_free()
				particles.remove_at(k)
		emitter["timer"] = float(emitter["timer"]) - delta
		# 大倍率不补喷积压粒子，保持画面稀疏与节点数有界。
		if float(emitter["timer"]) <= 0.0:
			emitter["timer"] = (
				_rng.randf_range(
					float(settings["interval_min_seconds"]), float(settings["interval_max_seconds"])
				)
				if emitter["kind"] == "chat"
				else float(settings["interval_seconds"])
			)
			if particles.size() < int(settings["max_per_actor"]):
				_spawn(int(index), emitter)


func _spawn(index: int, emitter: Dictionary) -> void:
	var settings := _settings_for(str(emitter["kind"]))
	var style: Dictionary = _styles[str(emitter["kind"])]
	var symbols: Array = style["symbols"]
	var colors: Array = style["colors"]
	var symbol := str(symbols[_rng.randi_range(0, symbols.size() - 1)])
	var color_index := _rng.randi_range(0, colors.size() - 1)
	if emitter["kind"] == "chat":
		color_index = (int(emitter["slot"]) + _rng.randi_range(0, 1)) % colors.size()
	var color := Color(str(colors[color_index]))
	var side := -1.0 if _rng.randi_range(0, 1) == 0 else 1.0
	# 每个粒子单独扰动速度与大小：同批粒子不再像复制粘贴（只用独立 RNG，不碰模拟随机流）
	var speed_scale := (
		1.0
		+ _rng.randf_range(
			-float(_settings["speed_variation"]), float(_settings["speed_variation"])
		)
	)
	var size_scale := (
		1.0
		+ _rng.randf_range(-float(_settings["size_variation"]), float(_settings["size_variation"]))
	)
	var visual := _make_symbol(symbol, color)
	(emitter["root"] as Control).add_child(visual)
	var origin := _anchor_of(index)
	if emitter["kind"] == "chat":
		origin = _chat_anchor_of(index)
	origin.x += side * float(settings["spread_m"])
	(emitter["particles"] as Array).append(
		{
			"index": index,
			"kind": emitter["kind"],
			"settings": settings,
			"node": visual,
			"age": 0.0,
			"origin": origin,
			"side": side,
			"speed_scale": speed_scale,
			"size_scale": size_scale,
			"rotation":
			_rng.randf_range(
				-float(settings["rotation_radians"]), float(settings["rotation_radians"])
			)
		}
	)


func _make_symbol(symbol: String, color: Color) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 光圈默认关闭：2026-10-12 用户裁定「只要符号本身的形状」；halo_enabled 置 true 即恢复
	if bool(_settings.get("halo_enabled", false)):
		var halo := Polygon2D.new()
		var radius := float(_settings["halo_radius_pixels"])
		var points := PackedVector2Array()
		var segments := int(_settings["halo_segments"])
		for k in range(segments):
			points.append(Vector2.from_angle(TAU * float(k) / float(segments)) * radius)
		halo.polygon = points
		halo.color = Color(color, float(_settings["halo_alpha"]))
		root.add_child(halo)
	if _bitmaps.has(symbol):
		var glyph := TextureRect.new()
		glyph.texture = _bitmaps[symbol]
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.size = Vector2.ONE * float(_settings["font_size"])
		glyph.position = -glyph.size * 0.5
		glyph.modulate = color
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(glyph)
	elif _icons.has(symbol):
		var sprite := TextureRect.new()
		sprite.texture = _icons[symbol]
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.size = Vector2.ONE * float(_settings["font_size"])
		sprite.position = -sprite.size * 0.5
		sprite.modulate = color
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(sprite)
	else:
		var label := Label.new()
		label.text = symbol
		label.add_theme_font_override("font", Fonts.regular())
		label.add_theme_font_size_override("font_size", int(_settings["font_size"]))
		label.add_theme_color_override("font_color", color)
		label.add_theme_color_override("font_outline_color", Color(str(_settings["outline_color"])))
		label.add_theme_constant_override("outline_size", int(_settings["outline_size"]))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(label)
		label.position = -label.get_minimum_size() * 0.5
	return root


## 缓出曲线：power = 1 即线性（与旧行为一致），越大越"先快后慢"。
static func _ease_out(t: float, power: float) -> float:
	return 1.0 - pow(1.0 - t, power)


func _sample(particle: Dictionary) -> Dictionary:
	var settings: Dictionary = particle.get("settings", _settings)
	var age := float(particle["age"])
	var lifetime := float(settings["lifetime_seconds"])
	var t := clampf(age / lifetime, 0.0, 1.0)
	var origin: Vector3 = particle["origin"]
	if particle.get("kind", "") == "chat":
		origin = _chat_anchor_of(int(particle["index"]))
		origin.x += float(particle["side"]) * float(settings["spread_m"])
	var speed := float(particle.get("speed_scale", 1.0))
	var height := maxf(
		float(settings["floor_height_m"]),
		(
			origin.y
			+ float(settings["rise_speed_m"]) * speed * age
			- float(settings["gravity_m"]) * speed * age * age * 0.5
		)
	)
	# 弹入：刚出现的一小段由小到大，避免"凭空突然出现"
	var appear := clampf(t / float(settings["appear_span"]), 0.0, 1.0)
	var appear_factor := lerpf(float(settings["appear_scale"]), 1.0, _ease_out(appear, 2.0))
	# 缩小改用幂曲线（1.0 = 旧的线性）：前期保持大小，末段才快速收敛
	var shrink := pow(t, float(settings["scale_ease_power"]))
	# 横向漂移改为减速（1.0 = 旧的匀速）
	var drift := _ease_out(t, float(settings["drift_ease_power"]))
	return {
		"height": height,
		"scale":
		(
			(
				lerpf(1.0, float(settings["minimum_scale"]), shrink)
				* float(particle.get("size_scale", 1.0))
			)
			* appear_factor
		),
		"alpha": 1.0 - smoothstep(float(settings["fade_start"]), 1.0, t),
		"position":
		Vector3(
			(
				origin.x
				+ (
					float(particle["side"])
					* float(settings["side_speed_m"])
					* speed
					* lifetime
					* drift
				)
			),
			height,
			origin.z
		)
	}


func _layout() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var view_scale := clampf(
		get_viewport().get_visible_rect().size.y / float(_settings["reference_height_pixels"]),
		float(_settings["minimum_view_scale"]),
		float(_settings["maximum_view_scale"])
	)
	for emitter in _bubbles.values() + _retiring:
		for particle in emitter["particles"]:
			var sample := _sample(particle)
			var node: Control = particle["node"]
			var world: Vector3 = sample["position"]
			node.visible = not camera.is_position_behind(world)
			var screen := camera.unproject_position(world)
			var particle_scale := view_scale
			if particle.get("kind", "") == "chat":
				particle_scale = clampf(
					view_scale,
					float(_chat_settings["minimum_view_scale"]),
					float(_chat_settings["maximum_view_scale"])
				)
				screen += (
					Vector2(
						float(particle["side"]) * float(_chat_settings["screen_side_pixels"]),
						-float(_chat_settings["screen_lift_pixels"])
					)
					* particle_scale
				)
				var margin := float(_chat_settings["edge_margin_pixels"]) * particle_scale
				var viewport_size := get_viewport().get_visible_rect().size
				# 完全离屏的学生不在边缘留下符号。
				node.visible = (
					node.visible
					and Rect2(Vector2.ZERO, viewport_size).has_point(
						camera.unproject_position(world)
					)
				)
				screen = screen.clamp(Vector2.ONE * margin, viewport_size - Vector2.ONE * margin)
			node.position = screen
			node.scale = Vector2.ONE * float(sample["scale"]) * particle_scale
			node.modulate.a = float(sample["alpha"])
			node.rotation = float(particle["rotation"])


func _anchor_of(index: int) -> Vector3:
	if is_instance_valid(_actors):
		var anchor: Node3D = _actors.feedback_anchor_of(index)
		if is_instance_valid(anchor):
			return anchor.global_position + Vector3.UP * float(_settings["head_lift_m"])
	var position: Vector2 = _core.position_of(index)
	return Vector3(
		position.x,
		float(_settings["fallback_height_m"]) + float(_settings["head_lift_m"]),
		position.y
	)


func _load_style() -> void:
	if not _settings.is_empty():
		return
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STYLE_PATH))
	_settings = config["settings"]
	_styles = config["styles"]
	_chat_settings = _settings.duplicate()
	_chat_settings.merge(config["chat_settings"], true)
	for key in config["icons"]:
		var image := Image.new()
		if image.load_svg_from_string(str(config["icons"][key])) == OK:
			_icons[key] = ImageTexture.create_from_image(image)
	for key in config.get("bitmaps", {}):
		var path := str(config["bitmaps"][key])
		if ResourceLoader.exists(path):
			_bitmaps[key] = load(path)
		else:
			push_warning("符号贴图缺失，回退字体字形：%s" % path)


func _settings_for(kind: String) -> Dictionary:
	return _chat_settings if kind == "chat" else _settings


func _chat_anchor_of(index: int) -> Vector3:
	if is_instance_valid(_actors):
		return _actors.head_position_of(index) + Vector3.UP * float(_chat_settings["head_lift_m"])
	return (
		_anchor_of(index)
		+ Vector3.UP * (float(_chat_settings["head_lift_m"]) - float(_settings["head_lift_m"]))
	)
