extends Node3D
## 课间走动驱动器（表现层；**不是玩法真相**）。
##
## 时间由内核驱动：本组件**不自造节拍**，课间 / 上课边界一律来自 `SimulationClock` 的
## `phase_changed`（而时钟只调用内核对拍接口）。这里负责把主文档 §10.4 的
## 「课间走动 → 段末 / 上课归位」表现出来。
##
## 做什么：
##   · **课间段**：段首与配置的间隔之后各判定一次离座，目标按 §10.4 的权重式挑
##     （`1 + Σ_j A[i][j]/100 − Σ_j H[i][j]/200`，目标点附近有活动圈则 ×1.5，下限 0.1）；
##   · **上课段**：进入上课时全体走回自己座位，整段不动（§10.4 第 6 条归位）；
##   · **占用**：每个站立点同时只容纳一个人（含玩家），先到者锁定（NPC移动决策 §2.2）；
##   · **玩家**：点击地面任意位置走过去（快照 `player_control` 为假时直接拒绝点击）。
##
## 数值口径：
##   · **课间离座**：速度统一取 `data/rules/movement.csv` 的 `meters_per_tick`（米 / 秒），
##     耗时随**导航路径长度**变化（§10.4 第 4 条，放弃固定 15 tick）；
##   · **上课归位**：用时限走（`move.duration` tick × 每 tick 真实秒数），
##     保证 §10.4 第 6 条「相位切换后回座位」在段内完成；
##   · 路线一律来自**导航网格**（`scenes/game/classroom3D.tscn` 的 NavigationRegion3D）：
##     取不到路线就留在原地并计数，**不用直线兜底**（直线会穿桌椅）；
##   · **离座概率走统一公式**：`p = base_p × 外向修正(E)`，
##     `base_p` 来自 `data/rules/behavior_probs.csv` 的 `move`（当前 0.20），
##     外向修正（§10.4）：E≥50 → ×(1+(E−50)/100)，E<50 → ×(1−(50−E)/200)，下限 0.1；

const BEHAVIORS_TABLE := "rules/behaviors"
const PHASES_TABLE := "rules/phases"
const PRESENTATION_TABLE := "rules/time_presentation"
const MOVEMENT_TABLE := "rules/movement"
const MOVE_BEHAVIOR := "move"
const SPEED_PARAM := "meters_per_tick"
const KIND_BREAK := "break"
## 座位可走站位名（desk_chair.tscn 的 Marker3D）：落位、站位、玩家路径共用这一个来源
const STAND_SPOT_NAME := "StandSpot"
## 旧落位偏移（米）：StandSpot 缺失时的兜底，保证老场景仍能跑
const LEGACY_CHAIR_OFFSET_Z := -0.45
## §10.4：想加入的活动圈所在位置额外 ×1.5
const CIRCLE_BONUS := 1.5
## §10.4：权重下限 0.1（再不喜欢也偶尔走动，不锁死）
const MIN_WEIGHT := 0.1
## 活动圈判定半径（米）：点附近这个范围内有 ≥2 人 → 视为可加入的活动圈（§15.1）
const CIRCLE_RADIUS := 1.2
## 归位后至少停留的秒数（点按钮 / 空格确认进入次日，转场黑幕任务；0 = 归位后立即恢复原节奏）
const SNAP_STAY_SECONDS := 0.0
## 「第 N 天」黑幕结束首次归位的停留秒数（日末等待期，比确认进入稍长）
const DAY_START_STAY_SECONDS := 0.7

@export_group("表现开关")
## 关掉即纯静态教室（便于截图 / 对比）
@export var enabled: bool = true
@export_group("节点路径")
@export var stand_points_path: NodePath = ^"../StandPoints"
@export var seats_path: NodePath = ^"../Seats"
@export var actors_path: NodePath = ^"../Actors"

@export_group("站立点标记")
## 画一圈可见标记（关掉即只保留逻辑点）
@export var show_stand_markers: bool = true
@export var marker_radius: float = 0.16
@export var marker_color: Color = Color(0.35, 0.62, 0.85, 0.45)

@export_group("调试")
## 打印每批离座与归位的汇总 —— 演示期默认开，便于在编辑器 / MCP 的调试输出里
## 确认走动真的在发生；接上内核后建议关掉。
@export var log_roam: bool = true

## 第二批离座距段首的秒数，来自 movement.csv 的 leave_decide_interval_seconds。
var decide_interval: float = 0.0

var _core: Variant = null
var _clock: SimulationClock = null
var _time_flow: TimeFlow = null

var _rng := RandomNumberGenerator.new()
var _batch_count := 0
var _actors: Array[Node3D] = []
var _walkers: Array = []
var _point_positions: Dictionary = {}
var _owner_of_point: Dictionary = {}
var _occupant: Dictionary = {}
var _point_of_actor: Dictionary = {}
var _actor_count := 0
var _player_index := -1
## 归位时限上限（秒）：由 move.duration（tick）× 每 tick 真实秒数推导
var _home_limit := 1.0
## 课间走动速度（米 / 秒）—— data/rules/movement.csv 的 meters_per_tick
var _speed := 0.8
## 取不到导航路线而放弃走动的次数：持续增长说明烘焙产物或几何出了问题（诊断用）
var _missed_walks := 0
var _snapshot: Dictionary = {}
## 转场黑幕期间挂起的相位快照（时钟 hold 时存下，退场后补跑）
var _pending_phase: Dictionary = {}
## 上一次瞬间归位的天数（每天首个课间归位一次）
var _last_snapped_day := -1
var _decide_timer := 0.0
## 每个课间最多触发几批离座决策（段首与课间中段）
var _max_decides_per_break: int = 2
## 本课间还剩几批决策额度
var _decides_remaining: int = 0


func bind_time_flow(flow: TimeFlow) -> void:
	_time_flow = flow


func _ready() -> void:
	# 等一帧：人物由 Actors 节点（classroom_actors.gd）在自己的 _ready 里生成，
	# 这里不依赖同级节点的 _ready 顺序（确定性 > 巧合）。
	await get_tree().process_frame
	_core = _current_core()
	if _core == null:
		push_warning("ClassroomRoam：没有本局内核实例 —— 走动演示关闭（请从主菜单「新游戏」进教室）。")
		return
	_actor_count = int(_core.node_count())
	_player_index = _actor_count - 1
	_home_limit = _load_home_limit()
	_speed = _load_speed()
	decide_interval = _load_decide_interval()
	_collect_points()
	_collect_actors()
	if show_stand_markers:
		_build_markers()
	_occupy_seats()


## 绑定时钟：课间 / 上课边界全部来自它的 phase_changed，本组件不再自己计时。
func bind_clock(clock: SimulationClock) -> void:
	if _clock == clock:
		return
	if _clock != null and is_instance_valid(_clock):
		_clock.phase_changed.disconnect(_on_phase_changed)
	_clock = clock
	if _clock == null:
		return
	_clock.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(_clock.snapshot())


func _process(delta: float) -> void:
	if not enabled or _core == null or _clock == null:
		return
	# 黑幕退场后补跑被挂起的相位反应（转场黑幕任务接入点）
	if not _pending_phase.is_empty() and not _clock.is_paused():
		var pending: Dictionary = _pending_phase
		_pending_phase = {}
		_apply_phase(pending)
	# 日末留白（晚自习 / 夜晚）：全员归位静坐，冻结走动，等待「进入第 N 天」（转场黑幕任务）
	if str(_clock.snapshot().get("mode", "")) != SimulationClock.MODE_RUNNING:
		return
	# 黑幕显示期间（时钟被 hold）：倒计时与走动全部冻结（转场黑幕任务）
	if _clock.is_paused():
		return
	if is_instance_valid(_time_flow):
		delta = _time_flow.scale_delta(delta)
	if delta <= 0.0:
		return
	# 只课间推进决策；上课段不发起新走动（§10.4）
	if not is_break_phase():
		_sync_positions_to_core()
		return
	_sync_positions_to_core()
	if _decides_remaining <= 0 or decide_interval <= 0.0:
		return
	_decide_timer += delta
	if _decide_timer < decide_interval:
		return
	_decide_timer = 0.0
	_decide_batch()


## 转场黑幕任务：全员（含玩家）瞬间贴回自己的座位（不走路），并终止在途行走。
## 触发时机：「第 N 天」黑幕结束 / 点「进入第 N 天」或按空格确认进入次日。
## 归位后全员在座位上停留 stay_seconds 秒，再按原逻辑开始活动。
func snap_to_seats(stay_seconds: float = SNAP_STAY_SECONDS) -> void:
	for i in range(_actor_count):
		var seat_id := str(_core.seat_of(i))
		if not _point_positions.has(seat_id):
			continue
		var actor: Node3D = _actors[i]
		if actor == null:
			continue
		if _walkers[i] != null:
			_walkers[i].stop()
		actor.global_position = _point_positions[seat_id]
		_core.set_position(i, actor.global_position.x, actor.global_position.z)
		_core.set_moving(i, false)
	# 归位后至少停留 stay_seconds 再进行下一批离座（计时为累加制，时钟节拍来自 data）
	_decide_timer = maxf(decide_interval - stay_seconds, 0.0)


## 转场黑幕任务：黑幕开始退场的瞬间立刻应用挂起的相位（含每日瞬间归位），
## 不等下一帧 —— 避免黑幕淡出期间闪现昨天的位置。
func flush_pending_phase() -> void:
	if _pending_phase.is_empty():
		return
	var pending: Dictionary = _pending_phase
	_pending_phase = {}
	_apply_phase(pending)


## 相位切换（由时钟驱动）：进课间 → 可以离座；进上课 → 全体归位（§10.4 第 6 条）。
## ⚠️ 转场黑幕期间（时钟被 hold）先存快照不执行，退场后由 _process 补跑 ——
## 保证倒计时与 NPC 走动都从黑幕结束后才开始（转场黑幕任务接入点）。
func _on_phase_changed(snapshot_data: Dictionary) -> void:
	if _clock != null and _clock.is_paused():
		_pending_phase = snapshot_data
		return
	_apply_phase(snapshot_data)


## 执行相位切换的实际反应（离座 / 归位），由 _on_phase_changed 或补跑调用。
func _apply_phase(snapshot_data: Dictionary) -> void:
	_snapshot = snapshot_data
	if not enabled or _core == null:
		return
	_occupy_seats()
	if is_break_phase():
		_decides_remaining = _max_decides_per_break
		# 每天首个课间（「第 N 天」黑幕刚结束）：全员瞬间归位，首批离座延后 stay 秒再按原节奏
		if int(snapshot_data.get("day", 0)) != _last_snapped_day:
			_last_snapped_day = int(snapshot_data.get("day", 0))
			snap_to_seats(DAY_START_STAY_SECONDS)
			return
		_decide_timer = 0.0
		_decide_batch()
		return
	_decides_remaining = 0
	var seconds := _home_seconds()
	for i in range(_actor_count):
		var seat_id := str(_core.seat_of(i))
		var target: Vector3 = _point_positions.get(seat_id, _point_positions.values()[0])
		_send_to_point(i, target, seconds)
	if log_roam:
		print("[roam] 进入上课：全体归位（本段共 %d 批离座）" % _batch_count)
	_batch_count = 0


## 归位时限：不超过上课段剩余时间的 80%，保证铃响后尽快坐好。
func _home_seconds() -> float:
	var remaining := float(_snapshot.get("remaining_seconds", 0.0))
	if remaining <= 0.0:
		return _home_limit
	return minf(_home_limit, maxf(remaining * 0.8, 0.5))


## ⚠️ 玩家输入**已移交** PlayerController（scripts/game/player_controller.gd）：
## 鼠标点击寻路 + WASD 手动行走共用一套移动执行与权限检查，避免两个组件同时拉动玩家。
## 本组件只管 NPC 走动；玩家的位置同样由这里同步给内核。
##
## 把每个人物（含玩家）的当前站位同步到内核（空间层接口）—— 内核据此判定交互范围。
## 位置是「表现层喂进来的只读状态」：内核不自己算移动，也不因位置改变任何矩阵。
func _sync_positions_to_core() -> void:
	if _core == null:
		return
	for i in range(_actor_count):
		var actor: Node3D = _actors[i]
		if actor == null:
			continue
		var pos := actor.global_position
		_core.set_position(i, pos.x, pos.z)
		if i != _player_index:
			_core.set_moving(i, _walkers[i] != null and _walkers[i].is_moving())


## 当前是否处于课间段（读时钟快照；尚未绑定时按课间处理）。
func is_break_phase() -> bool:
	if _snapshot.is_empty():
		return true
	return str(_snapshot.get("kind", "")) == KIND_BREAK


## 站立点总数（公共点 + 座位点）—— 供测试与调试。
func point_count() -> int:
	return _point_positions.size()


## 全部站立点编号（公共点 + 座位点）—— 供测试与调试。
func point_ids() -> Array:
	return _point_positions.keys()


## 某点当前被谁占用；-1 = 没人。越界返回 -1。
func occupant_of(point_id: String) -> int:
	return int(_occupant.get(point_id, -1))


## 归位时限上限（秒，由 move.duration × 每 tick 秒数换算）。
func home_limit_seconds() -> float:
	return _home_limit


## 课间走动速度（米 / 秒，来自 data/rules/movement.csv）。
func move_speed() -> float:
	return _speed


## 因取不到导航路线而放弃走动的次数（诊断用；持续增长说明烘焙产物或几何失效）。
func missed_walks() -> int:
	return _missed_walks


# ------------------------------------------------------------------ 装配
func _current_core() -> Variant:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return null
	return state.sim_core


## 收集站立点：公共点（StandPoints/<point_id>）+ 座位点（Seats/<seat_id>）。
func _collect_points() -> void:
	var stand_root := get_node_or_null(stand_points_path)
	if stand_root != null:
		for child in stand_root.get_children():
			var node := child as Node3D
			if node != null:
				_point_positions[node.name] = node.global_position
	var seat_root := get_node_or_null(seats_path)
	if seat_root != null:
		for i in range(_actor_count):
			var seat_id := str(_core.seat_of(i))
			var seat := seat_root.get_node_or_null(seat_id) as Node3D
			if seat == null:
				continue
			# 座位站位取 desk_chair.tscn 的 StandSpot（可走点）—— 与人物落位、玩家落位同一来源；
			# 缺失时回退旧偏移（椅子处），保证老场景 / 老测试仍能跑
			var spot := seat.get_node_or_null(STAND_SPOT_NAME) as Node3D
			if spot != null:
				_point_positions[seat_id] = spot.global_position
			else:
				_point_positions[seat_id] = (
					seat.global_position + Vector3(0.0, 0.0, LEGACY_CHAIR_OFFSET_Z)
				)
			_owner_of_point[seat_id] = i


func _collect_actors() -> void:
	var actors_root := get_node_or_null(actors_path)
	if actors_root == null:
		push_warning("ClassroomRoam：找不到人物父节点 %s" % str(actors_path))
		return
	for i in range(_actor_count):
		var actor := actors_root.get_child(i) as Node3D
		var home: Vector3 = _point_positions[str(_core.seat_of(i))]
		_core.set_seat_position(i, Vector2(home.x, home.z))
		_actors.append(actor)
		if actor == null:
			_walkers.append(null)
			continue
		var walker := actor.get_node_or_null("Walker") as ActorWalker
		_walkers.append(walker)
		if walker != null and i != _player_index:
			walker.walk_started.connect(_on_walk_started.bind(i))
			walker.walk_finished.connect(_on_walk_finished.bind(i))
	_sync_positions_to_core()


func _on_walk_started(_target: Vector3, i: int) -> void:
	_core.set_moving(i, true)


func _on_walk_finished(i: int) -> void:
	var pos: Vector3 = _actors[i].global_position
	_core.set_position(i, pos.x, pos.z)
	_core.set_moving(i, false)


func _occupy_seats() -> void:
	for i in range(_actor_count):
		var seat_id := str(_core.seat_of(i))
		if _point_positions.has(seat_id):
			_occupy(seat_id, i)


func _build_markers() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = marker_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := CylinderMesh.new()
	mesh.top_radius = marker_radius
	mesh.bottom_radius = marker_radius
	mesh.height = 0.01
	mesh.material = material
	for point_id in _point_positions.keys():
		var marker := MeshInstance3D.new()
		marker.name = "Marker_%s" % str(point_id)
		marker.mesh = mesh
		marker.position = _point_positions[point_id]
		add_child(marker)


## 归位时限：真读 data（move.duration × 每 tick 真实秒数）。
## 课间：15 tick × (100 秒 / 100 tick) = 15 秒 —— 数值全部来自 data，本组件不留常数。
func _load_home_limit() -> float:
	var loader := ConfigLoader.new()
	var duration_ticks := 0.0
	var rows: Array = loader.get_table(BEHAVIORS_TABLE).get("rows", [])
	for row in rows:
		if str(row.get("behavior", "")) == MOVE_BEHAVIOR:
			duration_ticks = float(str(row.get("duration", "0")))
			break
	var presentation_rows: Array = loader.get_table(PRESENTATION_TABLE).get("rows", [])
	var phase_rows: Array = loader.get_table(PHASES_TABLE).get("rows", [])
	var seconds_per_tick := 0.0
	for row in phase_rows:
		if str(row.get("kind", "")) == KIND_BREAK:
			seconds_per_tick = _break_seconds_per_tick(row, presentation_rows)
			break
	if duration_ticks <= 0.0 or seconds_per_tick <= 0.0:
		push_warning("ClassroomRoam：读不到 move.duration / 课间 tick 间隔，归位时限回退 1 秒。")
		return 1.0
	return duration_ticks * seconds_per_tick


## 课间走动速度（米 / 秒）：真读 data（movement.csv 的 meters_per_tick）。
## 1 个课间 tick = 1 真实秒，所以 meters_per_tick 同时就是「米 / 秒」（§10.4 第 4 条）。
func _load_speed() -> float:
	for row in ConfigLoader.new().get_table(MOVEMENT_TABLE).get("rows", []):
		if str(row.get("param", "")) == SPEED_PARAM:
			var value := float(str(row.get("value", "0")))
			if value > 0.0:
				return value
	push_warning("ClassroomRoam：读不到 movement.meters_per_tick —— 走动速度回退 0.8 米 / 秒。")
	return 0.8


## 第二次判定的间隔只读配置；缺失时禁用第二批，避免两批挤在段首。
func _load_decide_interval() -> float:
	for row in ConfigLoader.new().get_table(MOVEMENT_TABLE).get("rows", []):
		if str(row.get("param", "")) == "leave_decide_interval_seconds":
			var value := float(str(row.get("value", "0")))
			if value > 0.0:
				return value
	push_warning("ClassroomRoam：缺少有效的 leave_decide_interval_seconds，第二批离座关闭。")
	return 0.0


func _break_seconds_per_tick(phase_row: Dictionary, presentation_rows: Array) -> float:
	var ticks := float(str(phase_row.get("tick_count", "0")))
	var phase_id := str(phase_row.get("phase_id", ""))
	if ticks <= 0.0:
		return 0.0
	for row in presentation_rows:
		if str(row.get("phase_id", "")) == phase_id:
			return float(str(row.get("real_duration_seconds", "0"))) / ticks
	return 0.0


# ------------------------------------------------------------------ 决策


## 课间一批离座决策：按角色索引升序（NPC移动决策 §9 可复现性）。
## 离座概率走统一公式：p = base_p × 外向修正(E)
func _decide_batch() -> void:
	if _decides_remaining > 0:
		_decides_remaining -= 1
	_batch_count += 1
	var moved := 0
	var base_p: float = _core.behavior_base_p("move")
	for i in range(_actor_count):
		if i == _player_index:
			continue
		if _core.is_busy(i) or _core.session_of(i) >= 0 or _core._sleeping[i]:
			continue
		if _core.is_waiting_for_player(i):
			continue
		var walker: ActorWalker = _walkers[i]
		if walker == null or walker.is_moving():
			continue
		var p_move: float = base_p * _e_correction(i)
		if _rng.randf() > p_move:
			continue
		var point_id := _pick_point(i)
		if point_id.is_empty():
			continue
		_go_to_point(i, point_id)
		moved += 1
	if log_roam and moved > 0:
		print("[roam] 课间第 %d 批：%d 人离座" % [_batch_count, moved])


## 外向修正（主文档 §10.4）：E≥50 爱动，E<50 不爱动但概率永不为零（下限 0.1）。
func _e_correction(i: int) -> float:
	var e: float = _core.dimension(i, 0)
	if e >= 50.0:
		return 1.0 + (e - 50.0) / 100.0
	return maxf(0.1, 1.0 - (50.0 - e) / 200.0)


## 按 §10.4 权重抽一个站立点；没有候选返回空串。
func _pick_point(i: int) -> String:
	var ids: Array = []
	var weights: PackedFloat32Array = PackedFloat32Array()
	var total := 0.0
	for point_id in _point_positions.keys():
		var pid := str(point_id)
		if pid == str(_point_of_actor.get(i, "")):
			continue
		if _occupant.has(pid) and int(_occupant[pid]) != i:
			continue
		var weight := _point_weight(i, pid)
		ids.append(pid)
		weights.append(weight)
		total += weight
	if ids.is_empty() or total <= 0.0:
		return ""
	var roll := _rng.randf() * total
	for k in range(ids.size()):
		roll -= weights[k]
		if roll <= 0.0:
			return str(ids[k])
	return str(ids[ids.size() - 1])


## §10.4：权重 = 1 + Σ_j A[i][j]/100 − Σ_j H[i][j]/200；附近有活动圈 ×1.5；下限 0.1。
func _point_weight(i: int, point_id: String) -> float:
	var total_a := 0.0
	var total_h := 0.0
	for j in range(_actor_count):
		if j == i:
			continue
		total_a += float(_core.affinity(i, j))
		total_h += float(_core.hostility(i, j))
	var weight := 1.0 + total_a / 100.0 - total_h / 200.0
	if _people_near(i, point_id) >= 2:
		weight *= CIRCLE_BONUS
	return maxf(weight, MIN_WEIGHT)


## 该点附近（CIRCLE_RADIUS 内）站着多少人（不含自己）。
func _people_near(i: int, point_id: String) -> int:
	var pos: Vector3 = _point_positions[point_id]
	var count := 0
	for j in range(_actor_count):
		if j == i:
			continue
		var actor: Node3D = _actors[j]
		if actor == null:
			continue
		if actor.global_position.distance_to(pos) <= CIRCLE_RADIUS:
			count += 1
	return count


func _go_to_point(i: int, point_id: String) -> void:
	if _core.is_busy(i) or _core.session_of(i) >= 0 or _core._sleeping[i]:
		return
	_release_point(i)
	_occupy(point_id, i)
	_move_actor_to(i, _point_positions[point_id], false)


func _move_actor_to(i: int, pos: Vector3, keep_occupancy: bool) -> void:
	if _walkers[i] == null:
		return
	if keep_occupancy:
		_release_point(i)
		var nearest := _nearest_point(pos)
		if not nearest.is_empty():
			_occupy(nearest, i)
	_send_to_point(i, pos, -1.0)


## 让人物走到目标点（**导航折线**）。seconds > 0 = 按该时限走（归位）；否则按统一速度走（课间离座）。
## 取不到路线 = 留在原地 + 记一次失败 —— 不直线兜底（直线会穿桌椅，§10.4）。
func _send_to_point(i: int, target: Vector3, seconds: float) -> bool:
	var walker: ActorWalker = _walkers[i]
	if walker == null:
		return false
	var ok := false
	if seconds > 0.0:
		ok = walker.walk_to_navigated_in(target, seconds)
	else:
		ok = walker.walk_to_navigated(target, _speed)
	if not ok:
		_missed_walks += 1
		if log_roam:
			push_warning("[roam] 节点 %d 取不到导航路线 → 留在原地 (%.2f, %.2f)" % [i, target.x, target.z])
	return ok


# ------------------------------------------------------------------ 占用


func _occupy(point_id: String, i: int) -> void:
	_occupant[point_id] = i
	_point_of_actor[i] = point_id


func _release_point(i: int) -> void:
	var current := str(_point_of_actor.get(i, ""))
	if current.is_empty():
		return
	if int(_occupant.get(current, -1)) == i:
		_occupant.erase(current)
	_point_of_actor.erase(i)


# ------------------------------------------------------------------ 空间同步（→ 内核）


func _nearest_point(point: Vector3) -> String:
	var best := ""
	var best_distance := INF
	for point_id in _point_positions.keys():
		var candidate: Vector3 = _point_positions[point_id]
		if _occupant.has(point_id) and int(_occupant[point_id]) >= 0:
			continue
		var distance := candidate.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = str(point_id)
	return best
