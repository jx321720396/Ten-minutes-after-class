extends Node3D
const TERM_REPORT_SCENE := preload("res://scenes/ui/term_report.tscn")

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
@onready var behavior_badge: BehaviorBadgePresenter = $BehaviorBadge
@onready var npc_profile: NpcProfile = $UI/NpcProfile
@onready var tutorial: TutorialOverlay = $TutorialOverlay

var _term_report: CanvasLayer
var _outcome_screen: CanvasLayer
## 开场漫画实例：教程模式下等它播完再启动报到日步骤。
var _opening_comic: Node = null
## 教程步进用：最近一次被选中的行为栏 kind（提交时连同状态一起转发给教程）
var _tutorial_armed: StringName = &""


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
	# ⚠️ 开幕漫画必须早于 transition.bind_clock 与 _wait_navigation：前者会让黑幕立刻
	# 淡出、后者要等导航网格就绪（可能数秒）。排在它们之后会出现「教室先露脸、漫画后出现」。
	_bind_opening_comic()
	# 存档接线：把时钟引用交给 GameState（存档用）；读档时应用暂存时钟状态；日末自动存档。
	GameState.clock = clock
	if not GameState.pending_clock_state.is_empty():
		clock.restore_state(GameState.pending_clock_state)
		GameState.pending_clock_state = {}
	clock.report_ready.connect(_on_report_ready)
	if not _bind_time_flow(core):
		clock.hold(&"time_flow_config")
		transition.force_hide()
		return
	time_hud.bind_clock(clock)
	# 读档进入 report 边界时，HUD 会立刻开始「自动进入次日」倒计时；continue_requested 必须
	# 在 _wait_navigation 之前接上 —— 否则导航就绪慢于一倍 report_hold_seconds 时，信号在
	# 无人监听时发出，时钟会永远停在 report，NPC 归位后不再走动。
	time_hud.continue_requested.connect(_on_continue_requested)
	# 相位环境声：上课循环 amb_class（每天第一节课加晨鸟叫），课间 / 放学停。
	# bind_core 不会补发 phase_changed，所以连上后先按当前快照复查一次。
	clock.phase_changed.connect(SFX.on_phase_changed)
	SFX.on_phase_changed(clock.snapshot())
	# 学期最终结算（第 30 天结束 / 被辞退）放学声收尾；正常结束与 day_settled 同帧，SFX 内已去重。
	clock.term_finished.connect(SFX.on_term_finished)
	_term_report = TERM_REPORT_SCENE.instantiate()
	add_child(_term_report)
	_term_report.bind_sources(core, clock, actors, false)
	_outcome_screen = preload("res://scenes/ui/outcome_screen.tscn").instantiate()
	add_child(_outcome_screen)
	_outcome_screen.bind_sources(core, clock, _term_report)
	_outcome_screen.continue_requested.connect(_on_continue_requested)
	var exam_comic := preload("res://scripts/ui/exam_comic.gd").new()
	exam_comic.name = "ExamComic"
	add_child(exam_comic)
	exam_comic.bind_sources(core, clock)
	transition.bind_clock(clock)
	# 黑幕开始退场的瞬间就应用挂起的相位（含上课 / 每日归位），不等淡出结束
	transition.dismiss_started.connect(_on_transition_dismiss_started)
	# ⚠️ 绑定 Roam 之前先等导航就绪：bind_clock 会立刻触发一次相位回调（上课归位），
	#    地图没同步时那批走动会被全部判成「取不到路线」。
	var nav_ok := await _wait_navigation()
	if not is_inside_tree():
		# 等待期间场景已被释放（回主菜单 / 重建教室 / 无头 smoke 脚本）：不再继续绑定，
		# 否则会在已释放的节点上访问子节点配置并报错。
		return
	if nav_ok:
		roam.bind_clock(clock)
	# 读档落在课间时（GameState.load_game 置位）：绑定后立即强制一批离座决策，
	# 而不是被 Roam 当成一天之始、首批离座顺延 0.7 秒。
	if GameState.force_roam_decide:
		GameState.force_roam_decide = false
		roam.force_decide()
	player.bind_clock(clock)
	_bind_feedback(core)
	clock.time_updated.connect(_sync_state_mirror)
	_install_office()


func _bind_opening_comic() -> void:
	var comic := preload("res://scripts/ui/opening_comic.gd").new()
	comic.name = "OpeningComic"
	add_child(comic)
	_opening_comic = comic
	var settings: Control = pause_menu.settings_panel
	settings.replay_btn.disabled = false
	settings.replay_btn.tooltip_text = ""
	settings.replay_requested.connect(func(): comic.start(clock))
	if GameState.tutorial_pending:
		GameState.tutorial_pending = false
		if GameState.tutorial_mode:
			comic.finished.connect(_start_tutorial, CONNECT_ONE_SHOT)
		comic.start(clock)


func _install_office() -> void:
	var hub := preload("res://scripts/game/office_hub.gd").new()
	hub.name = "OfficeHub"
	add_child(hub)
	hub.bind_classroom(self)


## 第 0 天报到日（docs/design/新手教程-报到日-2026-10-19.md）：
## 开场漫画播完后启动；教程期间不写存档，结束时同种子重建正式局。
func _start_tutorial() -> void:
	if not GameState.tutorial_mode:
		return
	var core: Variant = actors.call("current_core")
	if core != null:
		_seed_tutorial_state(core)
	var hub: Node = get_node_or_null("OfficeHub")
	var anchors := {"time_hud": time_hud._panel}
	var card: Variant = time_hud._attention_card
	if card != null:
		anchors["attention_card"] = card
		if card.has_signal("details_opened"):
			card.details_opened.connect(_on_tutorial_risk_details_opened)
	if hub != null:
		if hub.has_signal("tutorial_event"):
			hub.connect("tutorial_event", _on_tutorial_event)
		if hub.has_method("tutorial_anchors"):
			var extra: Variant = hub.call("tutorial_anchors")
			if extra is Dictionary:
				anchors.merge(extra, true)
	if npc_profile.has_signal("opened"):
		npc_profile.opened.connect(_on_tutorial_profile_opened)
	tutorial.bind_world(clock, player, anchors)
	if not tutorial.intro_closed.is_connected(_on_tutorial_intro_closed):
		tutorial.intro_closed.connect(_on_tutorial_intro_closed, CONNECT_ONE_SHOT)
	if not tutorial.tutorial_finished.is_connected(_on_tutorial_finished):
		tutorial.tutorial_finished.connect(_on_tutorial_finished, CONNECT_ONE_SHOT)
	clock.hold(&"tutorial")
	tutorial.start_first_run()


## 教学情境只设初始状态，不指定学生之后做什么（不违反不脚本化原则）。
## 直接写内核平铺数组：教程局独立、结束后整体丢弃，不进入正式局。
func _seed_tutorial_state(core: Variant) -> void:
	var n := int(core.node_count())
	if n < 2:
		return
	core._stress[0] = 80.0
	core._a[0 * n + 1] = 60.0
	core._h[0 * n + 1] = 60.0
	core._h[1 * n + 0] = 60.0


func _on_tutorial_event(event: StringName) -> void:
	tutorial.notify_event(event)


func _on_tutorial_profile_opened(_index: int) -> void:
	tutorial.notify_event(&"profile_opened")


func _on_tutorial_risk_details_opened() -> void:
	tutorial.notify_event(&"risk_card_opened")


func _on_tutorial_intro_closed() -> void:
	clock.release(&"tutorial")


func _on_tutorial_finished() -> void:
	clock.release(&"tutorial")
	GameState.finish_tutorial()
	GameState.opening_day_shown = true
	var error := get_tree().change_scene_to_file("res://scenes/game/classroom3D.tscn")
	if error != OK:
		push_error("无法进入正式第一天：%s" % error_string(error))


func _on_tutorial_armed(kind: StringName) -> void:
	_tutorial_armed = kind
	tutorial.notify_armed(kind)


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
	rings.bind_actors(actors)
	var facing := preload("res://scripts/game/group_facing_presenter.gd").new()
	facing.name = "GroupFacing"
	add_child(facing)
	facing.bind_sources(core, actors)
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
	_inject_seat_zones(core)
	npc_profile.bind_sources(core, actors, null)
	$UI/StudyNavigation.bind_sources(core)
	action_bar.profile_requested.connect(npc_profile.open_profile)
	if not time_hud.student_profile_requested.is_connected(npc_profile.open_profile):
		time_hud.student_profile_requested.connect(npc_profile.open_profile)


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
	var rect := Rect2(
		origin.x - box.size.x * 0.5, origin.z - box.size.z * 0.5, box.size.x, box.size.z
	)
	# 桌椅占位只盖到桌面（desk_chair 的 Blocker z 到 0.23），而考生实际站在
	# 桌子外侧的 StandSpot（z = -0.80）上 —— 那也是自己座位的一部分，并进去。
	var stand := seat.get_node_or_null("StandSpot") as Marker3D
	if stand != null:
		var spot := stand.global_transform.origin
		rect = rect.merge(Rect2(spot.x, spot.z, 0.0, 0.0))
	return rect


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
	if str(clock.snapshot().mode) == SimulationClock.MODE_FINISHED:
		_outcome_screen.show_overview()
		return
	if clock.continue_after_report():
		# 转场黑幕任务：确认进入次日 → 显示「第 N 天」黑幕；
		# 黑幕结束后的归位停留（0.7 秒）由走动组件在退场补跑时接管
		var snap: Dictionary = clock.snapshot()
		if not bool(snap.get("is_exam_day", false)):
			transition.show_day_start(int(snap.get("day", 0)), str(snap.get("display_name", "")))
		return
	push_warning("Classroom：未能进入下一天（学期已结束，或完整存档 / 简报组件尚未接入）——" + "时间停留在当前边界。")


## 黑幕开始退场：立刻应用挂起的相位（含上课 / 每日归位），避免淡出期间闪现旧位置。
func _on_transition_dismiss_started() -> void:
	roam.flush_pending_phase()


## 日末简报边界自动存档（mode=report，时钟可安全恢复的边界）。
func _on_report_ready(_ended_day: int) -> void:
	GameState.auto_save()


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
		if tutorial != null and tutorial.is_intro_open():
			return  # 开场卡期间 Esc 由教程自己处理（跳过），不开暂停菜单
		pause_menu.show()
		get_tree().paused = true
		get_viewport().set_input_as_handled()
