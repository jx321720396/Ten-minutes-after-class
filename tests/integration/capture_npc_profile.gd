extends SceneTree
## 人工验收工具：真实教室底图；--fixture才写入测试用历史，不保存游戏、不进正式入口。
## godot --path . -s tests/integration/capture_npc_profile.gd -- --fixture

const SCENE := "res://scenes/game/classroom3D.tscn"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var compact := args.has("--compact")
	var fixture := args.has("--fixture")
	var state: Node = root.get_node("GameState")
	state.start_game(20261010, 16)
	var scene: Node = load(SCENE).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in range(50):
		await process_frame
	var profile: Node = scene.get_node("UI/NpcProfile")
	var core: SimCore = state.sim_core
	scene.get_node("TransitionOverlay").force_hide()
	await create_timer(0.4).timeout
	var target := 0
	var portrait_config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/ui/npc_profile.json")
	)
	for index in range(core.node_count()):
		if portrait_config.get("portraits", {}).has(core.character_id(index)):
			target = index
			break
	var subject := 1 if target == 0 else 0
	if fixture:
		# 仅截图夹具：数据从真实PlayerChatIntel接口写入，不从UI读取隐藏矩阵。
		for i in range(18):
			(
				core
				. _intel
				. record(
					i + 1,
					i + 1,
					target,
					subject,
					"hostility",
					50.0 + float(i),
					{
						"day": 1,
						"phase_id": "morning_break",
						"global_tick": i + 1,
					}
				)
			)
		(
			core
			. _intel
			. record(
				19,
				19,
				target,
				subject,
				"affinity",
				0.0,
				{
					"day": 1,
					"phase_id": "morning_break",
					"global_tick": 19,
				}
			)
		)
	scene.get_node("Interaction").select_actor(target)
	profile.open_profile(target)
	if args.has("--status"):
		profile._show_page(true)
	if fixture:
		var targets: OptionButton = profile.get_node("%Targets")
		targets.select(targets.get_item_index(subject))
		profile._on_target_selected(targets.get_item_index(subject))
	if args.has("--picker"):
		profile._open_target_picker()
	if compact:
		root.content_scale_size = Vector2i(1280, 720)
		root.size = Vector2i(1280, 720)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var output := (
		"res://tmp/npc_profile_%s%s%s.png"
		% [
			"fixture" if fixture else "empty",
			"_720" if compact else "_1080",
			"_picker" if args.has("--picker") else ("_status" if args.has("--status") else ""),
		]
	)
	root.get_texture().get_image().save_png(output)
	var frame: Control = profile.get_node("%Frame")
	var footer: Control = profile.get_node("%Footer")
	print(
		"CAPTURE ", output, " frame=", frame.get_global_rect(), " footer=", footer.get_global_rect()
	)
	print("PROFILE_OPEN ", profile.is_open(), " PAUSED ", paused)
	print("PORTRAIT ", core.alias(target), " ", profile.get_node("%Portrait").texture.resource_path)
	profile.close()
	quit()
