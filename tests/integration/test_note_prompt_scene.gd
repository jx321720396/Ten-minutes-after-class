extends GutTest
## 纸条链的**场景集成**用例：真实教室场景 + 真实内核 + 纸条提示接线（§8.6、§21.2.9）。
##
## 覆盖四件事：
##   ① 场景里存在纸条提示节点，并且真的被交互控制器绑上（接线不是"看着像"）；
##   ② 纸条到手**不打断**玩家当前的状态 —— 只在角落提示，第一步三选一；
##   ③ 选「看看写的什么」切到第二步三选一，并且内核只结算一次；
##   ④ 「去告诉老师」只能看完之后做，把柄记给**上一个递纸条给我的人**。
##
## 契约：夹具只摆真实状态（内核里放一张纸条），不伪造判定结果；
## 界面推进由显式驱动的一帧完成（与项目「时钟先 hold、需要推进时直接调内核」的
## 测试契约一致），因此本用例与真实帧率无关、同种子可复现。

const SCENE_PATH := "res://scenes/game/classroom3D.tscn"
const SEED := 20261010
const DIFFICULTY := 1
## 难度 1 = 8 个 NPC；玩家另算，所以本局共 9 个节点（§3.1）
const EXPECTED_NODES := 9


func before_each() -> void:
	var state: Variant = get_node("/root/GameState")
	state.start_game(SEED, DIFFICULTY)


func after_each() -> void:
	var state: Variant = get_node("/root/GameState")
	state.end_game()


## 打开真实教室场景并等交互接线完成（与闲聊场景用例同一套等待策略）。
func _open_scene() -> Node3D:
	var packed := load(SCENE_PATH) as PackedScene
	assert_not_null(packed, "教室场景必须可加载")
	var scene := packed.instantiate() as Node3D
	var roam: Node = scene.get_node("Roam")
	roam.enabled = false
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	for _frame in range(60):
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


## 驱动交互控制器的一帧：引擎每帧都会调 `_process`，这里显式调用，
## 让本用例不依赖真实帧率（纸条到手靠这条轮询）。
func _tick_ui(interaction: PlayerInteractionController) -> void:
	interaction._process(1.0 / 60.0)


func test_note_prompt_node_is_wired_to_the_controller() -> void:
	var scene := await _open_scene()
	var prompt := scene.get_node_or_null("NotePrompt") as NotePrompt
	assert_not_null(prompt, "场景里必须有纸条提示节点（§21.2.9）")
	var interaction: PlayerInteractionController = scene.get_node("Interaction")
	assert_eq(interaction._note, prompt, "交互控制器必须绑上纸条提示")
	assert_true(interaction.is_processing(), "每帧轮询已开启")


func test_difficulty_one_has_eight_npcs_plus_the_player() -> void:
	var scene := await _open_scene()
	var sim: Variant = _sim(scene)
	assert_eq(int(sim.node_count()), EXPECTED_NODES, "难度 1 = 8 NPC + 玩家")


func test_offered_note_shows_prompt_without_interrupting_the_player() -> void:
	var scene := await _open_scene()
	var sim: Variant = _sim(scene)
	var me := _player_index(sim)
	var interaction: PlayerInteractionController = scene.get_node("Interaction")
	var prompt: NotePrompt = scene.get_node("NotePrompt")
	# 记下玩家此刻的状态：纸条到手不该动它
	var busy_before := int(sim._busy_until[me])
	var act_before = sim._current_act[me]
	sim._note_create(0, 1, -1, 0, me)
	_tick_ui(interaction)
	assert_true(prompt.is_open(), "纸条到手要提示")
	assert_eq(prompt.step(), "offer", "先问看不看")
	assert_eq(prompt.body_text(), NotePrompt.TEXT_HINT, "提示不暴露写者与内容")
	assert_eq(prompt.button_labels(), ["不看，传下去", "不看，撕掉", "看看写的什么"])
	assert_eq(int(sim._busy_until[me]), busy_before, "纸条到手**不占用**玩家时间")
	assert_eq(sim._current_act[me], act_before, "纸条到手**不打断**玩家正在做的事")
	assert_false(interaction._menu.is_open(), "纸条不影响别处的界面状态")


func test_note_leaving_the_hand_closes_the_prompt() -> void:
	var scene := await _open_scene()
	var sim: Variant = _sim(scene)
	var me := _player_index(sim)
	var interaction: PlayerInteractionController = scene.get_node("Interaction")
	var prompt: NotePrompt = scene.get_node("NotePrompt")
	sim._note_create(0, 1, -1, 0, me)
	_tick_ui(interaction)
	assert_true(prompt.is_open())
	# 纸条传走（等价于玩家选了「不看，传下去」之后的状态）
	sim.finish_note(true, false)
	_tick_ui(interaction)
	assert_false(prompt.is_open(), "手上没纸条就不该再提示")


func test_reading_the_note_moves_to_the_second_step() -> void:
	var scene := await _open_scene()
	var sim: Variant = _sim(scene)
	var me := _player_index(sim)
	var interaction: PlayerInteractionController = scene.get_node("Interaction")
	var prompt: NotePrompt = scene.get_node("NotePrompt")
	sim._note_create(0, 1, -1, 0, me)
	_tick_ui(interaction)
	interaction._on_note_choice(&"read")
	assert_eq(prompt.step(), "after_read", "看完再问一次去向")
	assert_eq(prompt.button_labels(), ["撕掉", "继续传给别人", "去告诉老师"])
	assert_eq(int(sim._stats["notes_read"]), 1, "看只结算一次")
	interaction._on_note_choice(&"read")
	assert_eq(int(sim._stats["notes_read"]), 1, "重复点不会二次结算")
	_tick_ui(interaction)
	assert_eq(prompt.step(), "after_read", "已读的纸条仍停在第二步，不退回第一步")


func test_report_only_possible_after_reading() -> void:
	var scene := await _open_scene()
	var sim: Variant = _sim(scene)
	var me := _player_index(sim)
	var interaction: PlayerInteractionController = scene.get_node("Interaction")
	var prompt: NotePrompt = scene.get_node("NotePrompt")
	var author := 3
	sim._note_create(author, 1, -1, 0, me)
	_tick_ui(interaction)
	# 没看就举报：内核拒绝、提示还停在第一步
	sim.finish_note(false, true)
	assert_eq(prompt.step(), "offer", "没看过仍停在第一步")
	interaction._on_note_choice(&"read")
	interaction._on_note_choice(&"report")
	assert_eq(int(sim._witness_day[me * int(sim.node_count()) + author]), int(sim._day), "把柄记给上一手")
	assert_false(prompt.is_open(), "举报后提示收掉")
	assert_eq(sim._notes.size(), 0, "纸条不再往下传")


func test_note_holder_gets_a_badge_in_the_classroom() -> void:
	var scene := await _open_scene()
	var sim: Variant = _sim(scene)
	var badge := scene.get_node_or_null("BehaviorBadge") as BehaviorBadgePresenter
	assert_not_null(badge, "场景里必须有行为徽标组件（§20.1.4）")
	assert_eq(badge._core, sim, "徽标组件绑定的是本局内核")
	assert_eq(badge.badge_count(), 0, "开局没人拿着纸条")
	sim._note_create(0, 1, -1, 0, 1)
	badge._process(1.0 / 60.0)
	assert_true(badge.has_badge(1), "拿着纸条的人在场景里看得见（§21.2.9）")
	badge._process(1.0 / 60.0)
	assert_eq(badge.badge_count(), 1, "重复刷新不重复挂徽标")


func test_badge_follows_the_note_away_from_the_player() -> void:
	var scene := await _open_scene()
	var sim: Variant = _sim(scene)
	var me := _player_index(sim)
	var badge := scene.get_node("BehaviorBadge") as BehaviorBadgePresenter
	sim._note_create(0, 1, -1, 0, me)
	badge._process(1.0 / 60.0)
	assert_true(badge.has_badge(me), "玩家手里的纸条也有徽标")
	sim.finish_note(true, false)
	badge._process(1.0 / 60.0)
	assert_false(badge.has_badge(me), "纸条传走，徽标跟着收")
