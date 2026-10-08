extends GutTest
## 闲聊完整流程的**场景集成**用例：真实教室场景 + 真实内核 + 真实表现组件接线。
##
## 依据：docs/superpowers/plans/2026-10-07-chat-playable-loop.md §12 Task 6、§13。
##
## 三条用例（计划要求的三类）：
##   ① 近距离直接闲聊：到场即聊，30 tick 自然完成后拿到线索；
##   ② 远处绕桌接近后闲聊：先成了接近请求，走到合法站位才提交；
##   ③ 既有近距离 NPC 双人会话中玩家加入闲聊：接受 / 拒绝两条分支。
##
## 契约：夹具**只摆位置、只清占用**，不伪造判定结果；时钟一律先 hold，
## 需要推进 tick 时直接调内核，测试因此与真实帧率无关（同种子可复现）。

const SCENE_PATH := "res://scenes/game/classroom3D.tscn"
const SEED := 20261007
const DIFFICULTY := 1


func before_each() -> void:
	var state: Variant = get_node("/root/GameState")
	state.start_game(SEED, DIFFICULTY)


func after_each() -> void:
	var state: Variant = get_node("/root/GameState")
	state.end_game()


## 打开真实教室场景：关掉 NPC 走动驱动器（否则对照位置会被随机走动打乱）。
func _open_scene() -> Node3D:
	var packed := load(SCENE_PATH) as PackedScene
	assert_not_null(packed, "教室场景必须可加载")
	var scene := packed.instantiate() as Node3D
	var roam: Node = scene.get_node("Roam")
	roam.enabled = false
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	# 教室现在等待导航稳定后才绑定交互；不能以两次渲染帧假定已经完成。
	for frame in range(60):
		if scene.get_node("Interaction")._core != null:
			break
		await get_tree().physics_frame
	assert_not_null(scene.get_node("Interaction")._core, "导航及交互接线必须完成")
	return scene


func _sim(scene: Node3D) -> Variant:
	var state: Variant = get_node("/root/GameState")
	return state.sim_core


func _player_index(sim: Variant) -> int:
	return int(sim.node_count()) - 1


## 把玩家瞬移到指定地面坐标（等价于「已经走到这儿」），并同步给内核。
func _teleport_player(scene: Node3D, x: float, z: float) -> void:
	var sim: Variant = _sim(scene)
	var player: PlayerController = scene.get_node("Player")
	var actor: Node3D = player._player_actor
	actor.global_position = Vector3(x, actor.global_position.y, z)
	sim.set_position(_player_index(sim), x, z)


## 把某个人物挪到指定坐标（只改位置，不改任何矩阵）。
func _place(scene: Node3D, index: int, x: float, z: float) -> void:
	var sim: Variant = _sim(scene)
	sim.set_position(index, x, z)
	var actors: Node3D = scene.get_node("Actors")
	var actor: Node3D = actors.actor_for(index)
	if actor != null:
		actor.global_position = Vector3(x, actor.global_position.y, z)


# ------------------------------------------------------------------ 夹具位置（不手填教室坐标）
## 位置一律从**寻路网格**里挑：教室改布局也不用改测试，且一定与内核几何判定一致。


## 找一对合法位置 [玩家位, 目标位]：都可站、相距约 want。
## in_range 为真时要求「连线不穿家具且够得着」；为假时只要求两人可站且在寻路网格上连通。
func _free_pair(scene: Node3D, want: float, in_range: bool) -> Array:
	var player: PlayerController = scene.get_node("Player")
	var nav: AStarGrid2D = player._nav
	var space: Variant = _sim(scene)._space
	var region: Rect2i = nav.region
	var steps_lo := int(maxf(1.0, (want - 0.45) / maxf(player._grid, 0.01)))
	var steps_hi := int(maxf(1.0, (want + 0.45) / maxf(player._grid, 0.01)))
	var directions := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]
	for y in range(1, region.size.y - 1, 3):
		for x in range(1, region.size.x - 1, 3):
			var cell := Vector2i(x, y)
			if nav.is_point_solid(cell):
				continue
			var origin := player._cell_center(cell)
			for direction in directions:
				for step in range(steps_lo, steps_hi + 1):
					var other: Vector2i = cell + direction * step
					if not nav.region.has_point(other) or nav.is_point_solid(other):
						continue
					var goal := player._cell_center(other)
					if in_range:
						if not space.valid_position_for(
							Vector2(origin.x, origin.z), [Vector2(goal.x, goal.z)], 1.2
						):
							continue
					elif nav.get_point_path(cell, other).is_empty():
						continue
					return [origin, goal]
	return []


## 从 start 格沿 +x（允许 ±1 格 z 偏移）找一个可站、距离不小于 want 的位置。
func _scan_at_distance(
	player: PlayerController, nav: AStarGrid2D, start: Vector2i, want: float
) -> Variant:
	var steps := int(ceil(want / maxf(player._grid, 0.01)))
	var here := player._cell_center(start)
	for dz in range(-1, 2):
		for dx in range(steps, steps + 4):
			var cell := start + Vector2i(dx, dz)
			if not nav.region.has_point(cell) or nav.is_point_solid(cell):
				continue
			var point := player._cell_center(cell)
			if Vector2(point.x, point.z).distance_to(Vector2(here.x, here.z)) >= want - 0.35:
				return point
	return null


## 找一组「一场闲聊 + 玩家可加入」的合法位置：[0 号位, 1 号位, 玩家位]。
func _free_trio(scene: Node3D) -> Array:
	var player: PlayerController = scene.get_node("Player")
	var nav: AStarGrid2D = player._nav
	var space: Variant = _sim(scene)._space
	var region: Rect2i = nav.region
	for y in range(0, region.size.y, 2):
		for x in range(0, region.size.x, 2):
			var first_cell := Vector2i(x, y)
			if nav.is_point_solid(first_cell):
				continue
			var first := player._cell_center(first_cell)
			var second: Variant = _scan_at_distance(player, nav, first_cell, 0.7)
			if second == null:
				continue
			var targets := [Vector2(first.x, first.z), Vector2(second.x, second.z)]
			if not space.valid_position_for(targets[0], [targets[1]], 1.2):
				continue
			var stand: Variant = _stand_for(player, nav, space, targets)
			if stand == null:
				continue
			return [first, second, stand]
	return []


## 一个能同时够到所有目标、且连线不穿家具的站位（从目标附近向外扩一圈找）。
func _stand_for(
	player: PlayerController, nav: AStarGrid2D, space: Variant, targets: Array
) -> Variant:
	var first: Vector2 = targets[0]
	var base := player._cell_id(Vector3(first.x, 0.0, first.y))
	for radius in range(1, 6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var cell := base + Vector2i(dx, dy)
				if not nav.region.has_point(cell) or nav.is_point_solid(cell):
					continue
				var point := player._cell_center(cell)
				if space.valid_position_for(Vector2(point.x, point.z), targets, 1.2):
					return point
	return null


## 清掉某人的占用 / 睡眠 / 会话（夹具，只清状态，不伪造结果）。
func _free(scene: Node3D, index: int) -> void:
	var sim: Variant = _sim(scene)
	var sleeping: Array = sim._sleeping
	var busy: Array = sim._busy_until
	var acts: Array = sim._current_act
	var busy_act: Array = sim._busy_act
	var busy_phase: Array = sim._busy_phase
	sleeping[index] = false
	busy[index] = 0
	acts[index] = null
	busy_act[index] = null
	busy_phase[index] = -1
	sim._sleeping = sleeping
	sim._busy_until = busy
	sim._current_act = acts
	sim._busy_act = busy_act
	sim._busy_phase = busy_phase


## 让「加入判定」必然通过 / 必然被拒：只改真值矩阵，不消费随机数。
func _force(scene: Node3D, accept: bool) -> void:
	var sim: Variant = _sim(scene)
	var me: int = _player_index(sim)
	var n: int = int(sim.node_count())
	var a: Variant = sim._a
	a[0 * n + me] = 100.0 if accept else 0.0
	sim._a = a
	var dims: Variant = sim._dims
	dims[0] = 100.0 if accept else 0.0
	sim._dims = dims
	var stress: Variant = sim._stress
	stress[0] = 0.0 if accept else 100.0
	sim._stress = stress


func _advance_to_free(scene: Node3D) -> void:
	# 请求到期（自然完成）需要推进内核；时钟被 hold，不会重复推进
	var sim: Variant = _sim(scene)
	var clock: SimulationClock = scene.get_node("Clock")
	clock.hold(&"integration_fixture")
	for _i in range(40):
		sim.advance_tick()


# ------------------------------------------------------------------ ① 近距离直接闲聊


func test_nearby_chat_runs_and_yields_intel_after_natural_completion() -> void:
	var scene: Node3D = await _open_scene()
	var sim: Variant = _sim(scene)
	var clock: SimulationClock = scene.get_node("Clock")
	clock.hold(&"integration_fixture")
	var interaction: PlayerInteractionController = scene.get_node("Interaction")
	var menu: PlayerInteractionMenu = scene.get_node("InteractionMenu")
	var hud: ChatFeedbackHUD = scene.get_node("ChatHUD")
	var rings: ActivityRingPresenter = scene.get_node("Rings")
	var emotion: PlayerEmotionFeedback = scene.get_node("Emotion")

	var pair := _free_pair(scene, 0.7, true)
	assert_eq(pair.size(), 2, "教室场景里必须找得到一对合法的相邻位置")
	_free(scene, 0)
	_place(scene, 0, pair[1].x, pair[1].z)
	_teleport_player(scene, pair[0].x, pair[0].z)
	assert_true(bool(sim.interaction_space_ready()), "教室几何已注入内核")

	interaction.select_actor(0)
	assert_eq(str(interaction.current_state()), "selected", "点人只选中，不走动")
	assert_true(menu.is_open(), "菜单打开")
	assert_eq(menu.action_text(), "闲聊", "空闲对象只有一个「闲聊」操作")
	assert_false(menu.button_disabled(), "够得着就能点")

	interaction.request_behavior("chat")
	assert_eq(str(interaction.current_state()), "active", "已提交 → 进入聊天")
	assert_false(menu.is_open(), "提交后菜单关闭")
	assert_true(str(hud._progress_text.text).begins_with("正在和同学"), "底部显示聊天进度")
	rings.refresh()
	assert_true(rings.is_merged(0), "闲聊成立 → 目标进入融合区域")
	assert_true(rings.is_merged(_player_index(sim)), "玩家自己也在同一块区域里")
	var bubbles: ChatActivityBubble = scene.get_node("ChatBubble")
	# process_frame 信号在节点 _process 之前发出；等待实际呈现条件，避免整套运行时抢一帧。
	await wait_until(
		func(): return bubbles.has_bubble(0) and bubbles.has_bubble(_player_index(sim)), 1.0
	)
	assert_true(bubbles.has_bubble(0), "聊的两个人各一个无字气泡（不是每条关系边一个）")
	assert_true(bubbles.has_bubble(_player_index(sim)), "玩家这边也有气泡")

	_advance_to_free(scene)
	assert_eq(str(interaction.current_state()), "idle", "自然完成后回到空闲")
	var lines := hud.history_lines()
	assert_gte(lines.size(), 1, "自然完成的玩家闲聊必有线索：%s" % str(lines))
	assert_true(str(lines[0]).contains("透露"), "线索写明来源与对象：%s" % lines[0])
	assert_ne(str(emotion.current_emotion()), "", "完成时给了一次玩家自身情绪反馈")
	var me := _player_index(sim)
	# 气泡与圈只跟**真实会话**一致：不多留、也不漏（NPC 可能又开始新闲聊，所以看一致性而不是看 0）
	await wait_until(
		func():
			return (
				bubbles.has_bubble(me) == (sim.session_of(me) >= 0)
				and bubbles.has_bubble(0) == (sim.session_of(0) >= 0)
			),
		1.0
	)
	assert_eq(bubbles.has_bubble(me), sim.session_of(me) >= 0, "玩家气泡与真实会话一致")
	assert_eq(bubbles.has_bubble(0), sim.session_of(0) >= 0, "NPC 气泡与真实会话一致")


# ------------------------------------------------------------------ ② 远处接近后闲聊


func test_far_target_requires_approach_before_commit() -> void:
	var scene: Node3D = await _open_scene()
	var sim: Variant = _sim(scene)
	var clock: SimulationClock = scene.get_node("Clock")
	clock.hold(&"integration_fixture")
	var interaction: PlayerInteractionController = scene.get_node("Interaction")
	var player: PlayerController = scene.get_node("Player")

	_free(scene, 2)
	var pair := _free_pair(scene, 3.0, false)
	assert_eq(pair.size(), 2, "需要一对相距约 3m 的合法位置")
	_place(scene, 2, pair[1].x, pair[1].z)
	_teleport_player(scene, pair[0].x, pair[0].z)

	interaction.select_actor(2)
	var preview: Dictionary = sim.preview_player_interaction("chat", 2)
	assert_true(bool(preview["eligible"]), "远处只是够不着，不是不能聊")
	assert_false(bool(preview["in_range"]), "3m 之外")

	interaction.request_behavior("chat")
	assert_eq(str(interaction.current_state()), "approaching", "距离不足 → 先走过去")
	assert_gt(int(interaction.state_snapshot()["request_id"]), 0, "接近请求带内核分配的编号")
	assert_false(bool(sim.is_busy(_player_index(sim))), "途中不预占目标，也不占用自己")

	# 走到合法站位（等价于跟随路径走完）后再报到达
	var plan := player.plan_approach([pair[1]], 1.2)
	assert_true(bool(plan["ok"]), "存在合法站位：%s" % str(plan))
	var destination: Vector3 = plan["destination"]
	assert_lte(Vector2(destination.x, destination.z).distance_to(Vector2(pair[1].x, pair[1].z)), 1.2, "终点在范围内")
	_teleport_player(scene, destination.x, destination.z)
	player._finish_path()
	assert_eq(str(interaction.current_state()), "active", "到达后再次校验并提交")
	assert_true(bool(sim.is_busy(_player_index(sim))), "提交后玩家被占用")


# ------------------------------------------------------------------ ③ 加入既有闲聊


func test_join_existing_chat_reveals_only_after_the_pen() -> void:
	var scene: Node3D = await _open_scene()
	var sim: Variant = _sim(scene)
	var clock: SimulationClock = scene.get_node("Clock")
	clock.hold(&"integration_fixture")
	var interaction: PlayerInteractionController = scene.get_node("Interaction")
	var hud: ChatFeedbackHUD = scene.get_node("ChatHUD")
	var rings: ActivityRingPresenter = scene.get_node("Rings")

	_free(scene, 0)
	_free(scene, 1)
	var trio := _free_trio(scene)
	assert_eq(trio.size(), 3, "需要一组「两人闲聊 + 玩家可加入」的合法位置")
	_place(scene, 0, trio[0].x, trio[0].z)
	_place(scene, 1, trio[1].x, trio[1].z)
	_teleport_player(scene, trio[2].x, trio[2].z)
	sim._do_chat(0, 1)
	var session_id: int = int(sim.session_of(0))
	assert_gte(session_id, 0, "0 号与 1 号已在一场真实闲聊里")
	rings.refresh()
	assert_true(rings.is_merged(0), "原组本来就画成一块")

	_force(scene, true)
	interaction.select_actor(0)
	var preview: Dictionary = sim.preview_player_interaction("chat", 0)
	assert_eq(str(preview["mode"]), "join", "目标是聊天成员 → 加入操作")
	interaction.request_behavior("chat")
	assert_eq(str(interaction.current_state()), "pen_presenting", "加入要先转笔揭晓")
	assert_true(clock._paused_by.has("player_pen_check"), "转笔期间世界被自己的 hold 停住")
	assert_true(hud.is_presenting(), "笔还在转，结果未揭晓")
	assert_true(rings.is_hidden(_player_index(sim)), "未揭晓前不把自己画进融合区域")
	rings.refresh()
	assert_false(rings.is_merged(_player_index(sim)), "揭晓前圈不泄露结果")
	assert_true(rings.is_merged(0), "原组继续可见")

	hud.skip()
	assert_eq(int(hud.revealed_request_id()), int(interaction.state_snapshot()["request_id"]), "揭晓带请求编号")
	assert_false(clock._paused_by.has("player_pen_check"), "揭晓后释放自己持有的 hold")
	var accepted: bool = bool(interaction.state_snapshot()["accepted"])
	assert_true(accepted, "夹具保证这次被接受")
	assert_eq(str(interaction.current_state()), "active", "接受 → 进入聊天")
	assert_eq(int(sim.session_of(_player_index(sim))), session_id, "玩家加入的是原会话")
	rings.refresh()
	assert_true(rings.is_merged(_player_index(sim)), "揭晓后玩家进入同一块融合区域")


func test_join_rejection_keeps_the_group_intact() -> void:
	var scene: Node3D = await _open_scene()
	var sim: Variant = _sim(scene)
	var clock: SimulationClock = scene.get_node("Clock")
	clock.hold(&"integration_fixture")
	var interaction: PlayerInteractionController = scene.get_node("Interaction")
	var hud: ChatFeedbackHUD = scene.get_node("ChatHUD")
	var rings: ActivityRingPresenter = scene.get_node("Rings")

	_free(scene, 0)
	_free(scene, 1)
	var trio := _free_trio(scene)
	assert_eq(trio.size(), 3, "需要一组「两人闲聊 + 玩家可加入」的合法位置")
	_place(scene, 0, trio[0].x, trio[0].z)
	_place(scene, 1, trio[1].x, trio[1].z)
	_teleport_player(scene, trio[2].x, trio[2].z)
	sim._do_chat(0, 1)
	var session_id: int = int(sim.session_of(0))
	var end_before: int = int(sim.session_end_tick(session_id))
	var member_end_before: int = int(sim._busy_until[1])

	_force(scene, false)
	interaction.select_actor(0)
	interaction.request_behavior("chat")
	assert_eq(str(interaction.current_state()), "pen_presenting", "加入要先转笔")
	hud.skip()
	assert_false(bool(interaction.state_snapshot()["accepted"]), "夹具保证这次被拒")
	assert_eq(str(interaction.current_state()), "rejected_busy", "拒绝后等占用到期")
	assert_eq(int(sim.session_end_tick(session_id)), end_before, "原组结束点不变")
	assert_eq(int(sim._busy_until[1]), member_end_before, "原成员占用不变")
	assert_false(int(sim.session_of(_player_index(sim))) == session_id, "玩家没有被塞进原会话")
	rings.refresh()
	assert_true(rings.is_merged(0), "原组的融合圈照旧")
	assert_false(rings.is_merged(_player_index(sim)), "拒绝不产生融合")

	_advance_to_free(scene)
	assert_eq(str(interaction.current_state()), "idle", "拒绝占用到期后解除操作锁")


# ------------------------------------------------------------------ ④ 暂停与清理


func test_hold_does_not_cancel_the_approach_and_exit_cleans_up() -> void:
	var scene: Node3D = await _open_scene()
	var sim: Variant = _sim(scene)
	var clock: SimulationClock = scene.get_node("Clock")
	var interaction: PlayerInteractionController = scene.get_node("Interaction")
	var player: PlayerController = scene.get_node("Player")
	var hud: ChatFeedbackHUD = scene.get_node("ChatHUD")

	_free(scene, 3)
	var pair := _free_pair(scene, 3.0, false)
	assert_eq(pair.size(), 2, "需要一对相距约 3m 的合法位置")
	_place(scene, 3, pair[1].x, pair[1].z)
	_teleport_player(scene, pair[0].x, pair[0].z)
	interaction.select_actor(3)
	interaction.request_behavior("chat")
	assert_eq(str(interaction.current_state()), "approaching", "先接近")
	# 世界被 hold（转笔演出 / 暂停）：接近请求**冻结**而不是取消
	clock.hold(&"hold_probe")
	var request_id: int = int(interaction.state_snapshot()["request_id"])
	player._process(0.1)
	assert_eq(str(interaction.current_state()), "approaching", "hold 期间请求仍在")
	assert_eq(int(interaction.state_snapshot()["request_id"]), request_id, "请求编号没变")
	clock.release(&"hold_probe")

	# 退出场景：取消未提交请求、释放自己持有的 hold、不残留提示
	interaction.cancel_pending(&"scene_exit")
	assert_eq(str(interaction.current_state()), "idle", "退出前取消未提交请求")
	hud.clear()
	assert_false(hud.is_presenting(), "退出后没有残留的笔")
	assert_false(clock.is_paused(), "自己持有的 hold 已释放")
