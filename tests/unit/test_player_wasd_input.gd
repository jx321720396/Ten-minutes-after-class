extends GutTest
## WASD 手动移动（PlayerController）单测。
##
## 验证两层：
##  1. **动作注册**：`move_up/down/left/right` 在 `project.godot` 的 `[input]` 段里静态声明
##     （编辑器 / 输入映射界面可见可改），`_register_actions()` 是幂等兜底，不重复添加；
##  2. **手动移动执行**：一旦某个 move_* 动作处于「按下」状态，`_process()` 就驱动
##     ActorWalker 让玩家节点真正位移（`can_control` / `_slide` 不阻挡时）。
##
## 测试里用 `Input.action_press()` 直接标记动作「按下」状态（而不是 `Input.parse_input_event()`
## 注入合成按键）——后者在无头 / 无 `DisplayServer` 真实输入通道时无法驱动
## `Input.is_action_pressed()`（已单独验证，这是测试环境固有局限，不代表真实运行时失灵；
## 真实游戏里这套静态映射走 `DisplayServer → Input → InputMap` 完整硬件通道）。
## 本测试验证的是「一旦按下状态成立，移动链路是否真的执行」。
##
## `pc` 不挂场景树（`_make_world` 里只 new 出来直接注入字段），`_process` 里
## `get_viewport()` 会返回 null —— 靠 `_input_direction()` 的 viewport null 保护兜底
## （走 raw 归一化分支），不崩溃；这条 null 保护本身就是本次测试要顺带确认的行为。

const SEED := 12345
const NPC := 8
const WALKER_SCENE := "res://scenes/components/actor_walker.tscn"


## 造一个「玩家人物节点 + 行走组件」，挂到场景树（ActorWalker._ready 需要读父节点
## global_position，不挂树会拿到无效值）。
func _make_actor() -> Node3D:
	var actor := Node3D.new()
	actor.name = "Player"
	add_child(actor)
	var walker: Node = load(WALKER_SCENE).instantiate()
	walker.name = "Walker"
	actor.add_child(walker)
	await get_tree().process_frame  # 等 ActorWalker._ready 跑完
	actor.global_position = Vector3(3.0, 0.0, 3.0)  # 空地上，远离桌子
	return actor


func _make_world() -> Dictionary:
	var pc := PlayerController.new()
	pc._bounds = Rect2(-5.0, -5.0, 10.0, 10.0)
	pc._obstacles = [Rect2(-1.0, -1.0, 2.0, 2.0)]
	pc._grid = 0.25
	pc._speed = 0.13
	pc._eps = 0.02
	var actor := await _make_actor()
	var walker: Node = actor.get_node("Walker")
	pc._player_actor = actor
	pc._walker = walker
	pc._core = SimCore.from_npc(SEED, NPC, ConfigLoader.new().load_all())
	pc._player_index = int(pc._core.node_count()) - 1
	pc._clock = null
	pc._snapshot = {}
	return {"pc": pc, "actor": actor, "walker": walker}


## 清掉 4 个 move_* 动作可能残留的「按下」状态（防止跨测试污染）。
func _reset_actions() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)


func test_wasd_actions_are_registered_static_and_runtime() -> void:
	# 静态映射（project.godot 的 [input] 段）+ 运行时兜底（_register_actions），
	# 两条路径都完成后，4 个动作必须都在 InputMap 里，且不重复。
	var pc := PlayerController.new()
	pc._register_actions()
	assert_true(InputMap.has_action("move_up"), "move_up 应已注册")
	assert_true(InputMap.has_action("move_down"), "move_down 应已注册")
	assert_true(InputMap.has_action("move_left"), "move_left 应已注册")
	assert_true(InputMap.has_action("move_right"), "move_right 应已注册")
	var count_before := InputMap.get_actions().size()
	pc._register_actions()  # 再调一次（幂等兜底）
	assert_eq(InputMap.get_actions().size(), count_before, "重复注册不应新增动作（幂等）")


func test_move_left_action_drives_walker() -> void:
	var world := await _make_world()
	var pc: PlayerController = world.pc
	var actor: Node3D = world.actor
	_reset_actions()

	Input.action_press("move_left")
	var start_pos := actor.global_position
	for _i in range(30):
		pc._process(0.05)
	var end_pos := actor.global_position
	assert_true(pc.is_manual_walking(), "move_left 按下期间应处于手动行走")
	assert_gt(start_pos.x, end_pos.x, "move_left 应让 X 左移（减小）：%.2f → %.2f" % [start_pos.x, end_pos.x])
	assert_gt(start_pos.x - end_pos.x, 0.05, "位移应明显大于 0.05m")

	Input.action_release("move_left")
	var settled := end_pos
	for _i in range(5):
		pc._process(0.05)
		settled = actor.global_position
	assert_false(pc.is_manual_walking(), "松开后应退出手动行走")
	assert_eq(actor.global_position, settled, "停下后位置应不再变化")


func test_move_up_down_drives_z_axis() -> void:
	var world := await _make_world()
	var pc: PlayerController = world.pc
	var actor: Node3D = world.actor
	_reset_actions()

	Input.action_press("move_up")
	for _i in range(20):
		pc._process(0.05)
	var after_up := actor.global_position
	Input.action_release("move_up")

	actor.global_position = Vector3(3.0, 0.0, 3.0)
	Input.action_press("move_down")
	for _i in range(20):
		pc._process(0.05)
	var after_down := actor.global_position
	Input.action_release("move_down")

	# 无摄像机时 _input_direction 走 raw 归一化分支：W = 世界 -Z，S = 世界 +Z
	assert_lt(after_up.z, 3.0 - 0.05, "move_up 应让 Z 减小（画面上方）")
	assert_gt(after_down.z, 3.0 + 0.05, "move_down 应让 Z 增大（画面下方）")


func test_blocked_by_desk_slides_not_through() -> void:
	var world := await _make_world()
	var pc: PlayerController = world.pc
	var actor: Node3D = world.actor
	_reset_actions()
	# 桌子中心在原点，Rect2(-1,-1,2,2) 已按人物半径 0.24 外扩成 [-1.24, 1.24]；
	# 从 (-1.3, 0) 朝 +X 走 20 帧 × 0.05s × 0.13m/s ≈ 0.13m，会撞上桌子左沿（-1.24），
	# 按滑动逻辑应最多推进到 -1.24 附近，绝不会「穿过」桌子（不会大于 1.24）。
	actor.global_position = Vector3(-1.3, 0.0, 0.0)
	Input.action_press("move_right")
	for _i in range(20):
		pc._process(0.05)
	var end_x: float = actor.global_position.x
	assert_true(end_x <= 1.24 + 0.01, "不得穿过桌子右沿（%.2f）" % end_x)
	assert_gt(end_x, -1.3, "应沿桌沿滑动前进（不是完全卡死在原地）")

	Input.action_release("move_right")
