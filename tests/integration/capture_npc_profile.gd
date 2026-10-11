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
	state.start_game(20261010, 2)
	var scene: Node = load(SCENE).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in range(50):
		await process_frame
	var profile: Node = scene.get_node("UI/NpcProfile")
	var core: SimCore = state.sim_core
	scene.get_node("TransitionOverlay").force_hide()
	await create_timer(0.4).timeout
	if fixture:
		# 仅截图夹具：数据从真实PlayerChatIntel接口写入，不从UI读取隐藏矩阵。
		for i in range(18):
			(
				core
				. _intel
				. record(
					i + 1,
					i + 1,
					0,
					1,
					"trust",
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
				0,
				1,
				"affinity",
				0.0,
				{
					"day": 1,
					"phase_id": "morning_break",
					"global_tick": 19,
				}
			)
		)
	scene.get_node("Interaction").select_actor(0)
	scene.get_node("InteractionMenu").profile_requested.emit(0)
	if compact:
		root.content_scale_size = Vector2i(1280, 720)
		root.size = Vector2i(1280, 720)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var output := (
		"res://tmp/npc_profile_%s%s.png"
		% [
			"fixture" if fixture else "empty",
			"_720" if compact else "_1080",
		]
	)
	root.get_texture().get_image().save_png(output)
	var frame: Control = profile.get_node("%Frame")
	var footer: Control = profile.get_node("%Footer")
	print(
		"CAPTURE ", output, " frame=", frame.get_global_rect(), " footer=", footer.get_global_rect()
	)
	print("PROFILE_OPEN ", profile.is_open(), " PAUSED ", paused)
	profile.close()
	quit()
