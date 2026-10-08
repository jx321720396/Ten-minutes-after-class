class_name InteractionSpace
extends RefCounted
## 交互空间（内核侧，纯几何）：范围判定与「两个人之间是否隔着一张桌子」。
##
## 依据：主文档 §10.4（走动 / 位置）、§10.5（闲聊范围）；
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §3.1。
##
## 为什么单独成类：`distance_between` 只回答「离多远」，回答不了「能不能走过去」。
## 玩家从教室另一头点一个人时，两人直线距离可能够近（隔着桌子），但那不是一次合法接触。
##
## 职责边界：
##   · 只吃**纯数据**（障碍矩形 + 房间边界），不引用 Node3D / 导航节点 / 相机；
##   · 只做判定，不改任何玩法状态、不掷骰；
##   · 几何由场景在初始化时一次注入（`set_geometry`），未注入时一律判定为「不可用」，
##     由调用方给出明确错误，不静默按「随便都能站」放行。

var _obstacles: Array[Rect2] = []
var _bounds := Rect2()
var _ready := false


## 注入几何（场景 → 内核的唯一入口）。bounds 为空矩形或障碍含 NaN 时保持未就绪。
func set_geometry(obstacles: Array, bounds: Rect2) -> void:
	_obstacles = []
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		_ready = false
		return
	for rect in obstacles:
		var r := rect as Rect2
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if is_nan(r.position.x) or is_nan(r.position.y) or is_nan(r.size.x) or is_nan(r.size.y):
			continue
		_obstacles.append(r)
	_bounds = bounds
	_ready = true


func is_ready() -> bool:
	return _ready


func reset() -> void:
	_obstacles = []
	_bounds = Rect2()
	_ready = false


func bounds() -> Rect2:
	return _bounds


func obstacle_count() -> int:
	return _obstacles.size()


## 该点是否可以站人（在房间内且不在任何家具矩形里）。p 取人物中心的 XZ。
func position_valid(p: Vector2) -> bool:
	if not _ready:
		return false
	if not _bounds.has_point(p):
		return false
	return not _blocked(p)


## 该点是否落在家具阻塞区内（含边界）。
func _blocked(p: Vector2) -> bool:
	for rect in _obstacles:
		if rect.has_point(p):
			return true
	return false


## 两点平面距离（米）。
func distance(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)


## 两点是否在交互范围内（含边界）。
func in_range(a: Vector2, b: Vector2, range_m: float) -> bool:
	return a.distance_to(b) <= range_m


## 直线段是否穿过家具（短连接段不得画穿桌子）。
## 采用采样判定：格子尺度几何 + 家具矩形是轴对齐的，采样步长取范围参数的一半即可稳定命中。
func segment_blocked(a: Vector2, b: Vector2, step_m: float = 0.1) -> bool:
	var length := a.distance_to(b)
	if length <= 0.0:
		return _blocked(a)
	var steps := maxi(1, int(ceil(length / maxf(step_m, 0.01))))
	for k in range(steps + 1):
		var t := float(k) / float(steps)
		if _blocked(a.lerp(b, t)):
			return true
	return false


## 「站得住 + 对每个目标都在范围内 + 连线不穿家具」—— 一次交互的完整空间合法性。
## targets 为空表示只检查站位本身。
func valid_position_for(origin: Vector2, targets: Array, range_m: float, step_m: float = 0.1) -> bool:
	if not _ready or not position_valid(origin):
		return false
	for t in targets:
		var point := t as Vector2
		if not in_range(origin, point, range_m):
			return false
		if segment_blocked(origin, point, step_m):
			return false
	return true


## 原组是否具有有效的近距离布局：每位成员至少与另一个成员在交互范围内。
## 用来拒绝「从教室另一头加入一场其实早已散开的组」——他们必须先真的在一起。
func group_layout_valid(positions: Array, range_m: float) -> bool:
	if positions.size() < 2:
		return false
	for a in range(positions.size()):
		var linked := false
		for b in range(positions.size()):
			if a == b:
				continue
			if in_range(positions[a] as Vector2, positions[b] as Vector2, range_m):
				linked = true
				break
		if not linked:
			return false
	return true
