extends Node3D
## 教室场景导航 + 时间接线；模拟逻辑由内核独立负责。
##
## 只有**一处**绑定内核（避免重复连接）：Actors 在自己的 _ready 里准备内核（必要时
## 自动建演示局）→ 本节点等一帧 → Clock.bind_core(内核) → HUD / Roam 绑定时钟 →
## 时钟每次推进把 day / phase 同步到 GameState 镜像。

@onready var pause_menu: Control = $UI/PauseMenu
@onready var clock: SimulationClock = $Clock
@onready var time_hud: TimeHUD = $TimeHUD
@onready var roam: Node = $Roam
@onready var player: PlayerController = $Player


func _ready() -> void:
	# 人物由 Actors 在自己的 _ready 里生成，等一帧再接线（确定性 > 巧合）
	await get_tree().process_frame
	var core: Variant = _core_from_state()
	if core == null:
		push_warning("Classroom：没有本局内核实例 —— 时间与走动都不启动（请从主菜单「新游戏」进教室）。")
		return
	if not clock.bind_core(core):
		push_error("Classroom：时钟绑定失败（时间配置有问题），时间系统未启动。")
		return
	time_hud.bind_clock(clock)
	roam.bind_clock(clock)
	player.bind_clock(clock)
	clock.time_updated.connect(_sync_state_mirror)
	time_hud.continue_requested.connect(_on_continue_requested)


## 日末简报的「进入第 N 天」：只有在 report 状态才成功；学期结束或依赖缺失时明确报开发状态，
## 不假装成功（计划 §6：不提供虚假的成功恢复）。
func _on_continue_requested() -> void:
	if clock.continue_after_report():
		return
	push_warning("Classroom：未能进入下一天（学期已结束，或完整存档 / 简报组件尚未接入）——" + "时间停留在当前边界。")


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
