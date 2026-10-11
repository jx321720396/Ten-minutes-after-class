extends Node3D
## 教室场景导航 + 时间接线；模拟逻辑由内核独立负责。
##
## 只有**一处**绑定内核（避免重复连接）：Actors 在自己的 _ready 里准备内核（必要时
## 自动建演示局）→ 本节点等一帧 → 注入交互几何 → Clock.bind_core(内核) → HUD / Roam /
## 玩家 / 交互控制器 / 圈 / 气泡 / 情绪这一批表现组件依次绑定 →
## 时钟每次推进把 day / phase 同步到 GameState 镜像。
##
## 统一绑定顺序（计划 §9）：**人物与几何准备 → 位置写回 → Clock 绑定 → Player/Roam 绑定
## → 交互控制器、HUD、圈、气泡绑定**。顺序错了就会出现「内核还没几何，界面已经能点人」。

@onready var pause_menu: Control = $UI/PauseMenu
@onready var clock: SimulationClock = $Clock
@onready var time_flow: TimeFlow = $TimeFlow
@onready var time_hud: TimeHUD = $TimeHUD
@onready var transition: TransitionOverlay = $TransitionOverlay
@onready var roam: Node = $Roam
@onready var player: PlayerController = $Player
@onready var actors: Node3D = $Actors
@onready var rings: ActivityRingPresenter = $Rings
@onready var chat_bubble: ChatActivityBubble = $ChatBubble
@onready var emotion: PlayerEmotionFeedback = $Emotion
@onready var chat_hud: ChatFeedbackHUD = $ChatHUD
@onready var action_bar: PlayerActionBar = $ActionBar
@onready var interaction: PlayerInteractionController = $Interaction
@onready var note_prompt: NotePrompt = $NotePrompt
@onready var behavior_badge: BehaviorBadgePresenter = $BehaviorBadge
@onready var npc_profile: NpcProfile = $UI/NpcProfile


func _ready() -> void:
	# 人物由 Actors 在自己的 _ready 里生成，等一帧再接线（确定性 > 巧合）
	await get_tree().process_frame
	var core: Variant = _core_from_state()
	if core == null:
		push_warning("Classroom：没有本局内核实例 —— 时间与走动都不启动（请从主菜单「新游戏」进教室）。")
		transition.force_hide()
		return
	if not _inject_interaction_geometry(core):
		push_warning("Classroom：交互几何未就绪（房间范围 / 桌椅矩形读不到）—— 玩家交互会明确失败，不会放行。")
	if not clock.bind_core(core):
		push_error("Classroom：时钟绑定失败（时间配置有问题），时间系统未启动。")
		transition.force_hide()
		return
	if not _bind_time_flow(core):
		clock.hold(&"time_flow_config")
		transition.force_hide()
		return
	time_hud.bind_clock(clock)
	transition.bind_clock(clock)
	_bind_clue_board()
	# 黑幕开始退场的瞬间就应用挂起的相位（含每日归位），不等淡出结束
	transition.dismiss_started.connect(_on_transition_dismiss_started)
	# ⚠️ 绑定 Roam 之前先等导航就绪：bind_clock 会立刻触发一次相位回调（上课归位），
	#    地图没同步时那批走动会被全部判成「取不到路线」。
	if await _wait_navigation():
		roam.bind_clock(clock)
	player.bind_clock(clock)
	_bind_feedback(core)
	clock.time_updated.connect(_sync_state_mirror)
	time_hud.continue_requested.connect(_on_continue_requested)


## 黑板跟这一局走：学期结束才清板。新开一局会换一间教室，板面本来就是空的。
func _bind_clue_board() -> void:
	var entry := get_node_or_null("UI/ClueBoardEntry")
	if entry != null and entry.has_method("clear_board"):
		clock.term_finished.connect(entry.clear_board)


func _bind_time_flow(core: SimCore) -> bool:
	if not time_flow.bind_sources(core, clock):
		return false
	clock.bind_time_flow(time_flow)
	roam.bind_time_flow(time_flow)
	player.bind_time_flow(time_flow)
	chat_bubble.bind_time_flow(time_flow)
	for actor in actors.get_children():
		var walker := actor.get_node_or_null("Walker") as ActorWalker
		if walker != null:
			walker.bind_time_flow(time_flow)
	return true


## 等导航网格可用（教室内所有走动的唯一路线来源）。
## 未就绪时**明确报错并停用走动**（人物仍站着、时间仍走），不静默降级成直线穿桌。
func _wait_navigation() -> bool:
	var probe := global_position
	var first := actors.get_child(0) as Node3D
	if first != null:
		probe = first.global_position
	if await NavReady.wait(self, probe):
		return true
	push_error(
		(
			"Classroom：导航网格未同步 —— NavigationRegion3D 是否已烘焙？"
			+ "（godot --headless --path . --script tools/bake_classroom_nav.gd）"
		)
	)
	return false


## 把玩家控制器派生出的**纯几何**注入内核：内核据此判定范围与「连不连得过去」。
## 一次注入，游戏运行期不再变；未就绪时明确返回 false（不假装成功）。
func _inject_interaction_geometry(core: Variant) -> bool:
	var geometry: Dictionary = player.interaction_geometry()
	var bounds: Rect2 = geometry.get("bounds", Rect2())
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return false
	core.set_interaction_geometry(geometry.get("obstacles", []), bounds)
	return bool(core.interaction_space_ready())


## 表现组件只读绑定：核心 / 人物 / 时钟，各自的可见性由内核真实会话决定。
func _bind_feedback(core: Variant) -> void:
	rings.bind_core(core)
	chat_bubble.bind_core(core)
	chat_bubble.bind_actors(actors)
	chat_bubble.bind_clock(clock)
	emotion.bind_core(core)
	emotion.bind_actors(actors)
	emotion.bind_clock(clock)
	chat_hud.bind_core(core)
	chat_hud.bind_clock(clock)
	# 头顶行为徽标（§20.1.4）：本批只接「手里拿着纸条」（§21.2.9）
	behavior_badge.bind_core(core)
	behavior_badge.bind_actors(actors)
	interaction.bind_feedback(action_bar, chat_hud, rings, chat_bubble, emotion, note_prompt)
	_inject_seat_zones(core)
	interaction.bind_sources(core, player, actors, clock)
	npc_profile.bind_sources(core, actors, interaction)
	action_bar.profile_requested.connect(npc_profile.open_profile)


## 座位范围（§8.23 / §20.1.1）：把每个人的座位世界坐标注入内核（供「是否在自己座位上」判定），
## 并只给**玩家自己**画一个地面圈 —— 需要在座位上才能做的行为有了可见的边界。
func _inject_seat_zones(core: Variant) -> void:
	if actors == null or core == null:
		return
	var zones := {}
	for i in range(int(core.node_count())):
		var rect := _seat_rect_of(i)
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			zones[i] = rect
	core.set_seat_zones(zones)
	_build_player_seat_rect(core, zones)


## 座位的**桌椅占位矩形**（世界 xz）：直接取该座位 NavBlocker 的形状与位置，
## 不另立尺寸 —— 判定与可视化因此天然与场景里那张桌椅对齐。
func _seat_rect_of(i: int) -> Rect2:
	var seat: Node3D = actors.seat_node_of(i)
	if seat == null:
		return Rect2()
	var blocker := seat.get_node_or_null("NavBlocker/Blocker") as CollisionShape3D
	if blocker == null or not (blocker.shape is BoxShape3D):
		return Rect2()
	var box := blocker.shape as BoxShape3D
	var origin := blocker.global_transform.origin
	return Rect2(origin.x - box.size.x * 0.5, origin.z - box.size.z * 0.5, box.size.x, box.size.z)


## 玩家座位的地面方框（与上面那个矩形同尺寸）。
func _build_player_seat_rect(core: Variant, zones: Dictionary) -> void:
	var me := int(core.node_count()) - 1
	if not zones.has(me):
		return
	var rect: Rect2 = zones[me]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(rect.size.x, 0.012, rect.size.y)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.72, 0.35, 0.22)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var ring := MeshInstance3D.new()
	ring.name = "PlayerSeatZone"
	ring.mesh = mesh
	ring.position = Vector3(
		rect.position.x + rect.size.x * 0.5, 0.008, rect.position.y + rect.size.y * 0.5
	)
	add_child(ring)


## 日末简报的「进入第 N 天」：只有在 report 状态才成功；学期结束或依赖缺失时明确报开发状态，
## 不假装成功（计划 §6：不提供虚假的成功恢复）。
func _on_continue_requested() -> void:
	if clock.continue_after_report():
		# 转场黑幕任务：确认进入次日 → 显示「第 N 天」黑幕；
		# 黑幕结束后的归位停留（0.7 秒）由走动组件在退场补跑时接管
		var snap: Dictionary = clock.snapshot()
		transition.show_day_start(int(snap.get("day", 0)), str(snap.get("display_name", "")))
		return
	push_warning("Classroom：未能进入下一天（学期已结束，或完整存档 / 简报组件尚未接入）——" + "时间停留在当前边界。")


## 黑幕开始退场：立刻应用挂起的相位（含每日归位），避免淡出期间闪现旧位置。
func _on_transition_dismiss_started() -> void:
	roam.flush_pending_phase()


func _core_from_state() -> Variant:
	var state: Variant = get_node_or_null("/root/GameState")
	if state == null:
		return null
	return state.sim_core


## GameState 的 day / phase 只作镜像，统一从时钟快照更新（不独立自增）。
func _sync_state_mirror(snapshot_data: Dictionary) -> void:
	var state: Variant = get_node_or_null("/root/GameState")
	if state == null:
		return
	state.sync_time(snapshot_data)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		pause_menu.show()
		get_tree().paused = true
		get_viewport().set_input_as_handled()
