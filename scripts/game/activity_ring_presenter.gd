class_name ActivityRingPresenter
extends Node3D
## 人物脚下活动圈（表现层，**只读**）：个人圈一律同色，真实成立的活动融成一块连续区域。
##
## 依据：主文档 §15.1（空间聚散）、§10.31.4（只读查询）；
##      docs/superpowers/plans/2026-10-07-activity-foot-rings.md、
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §8.2。
##
## 三条铁律：
##   ① 只看**真实共同活动**（`core.get_active_sessions()`），不按行为名聚合 ——
##      否则两场并行的闲聊会被并成一个圈，quiet 一方还会被漏掉；
##   ② 只读：不写回任何矩阵、不掷骰、不参与玩法判定；
##   ③ **未揭晓的加入结果不得泄露**：控制器把「已提交但还没揭晓」的成员登记为
##      hidden，这个人在揭晓前照旧只有个人圈。
##
## 渲染：每个活动一块横置 PlaneMesh，片元用 SDF 求「成员圆 ∪ 连接胶囊」的**平滑**并集 ——
## 融合区域因此没有内部双边框（见 assets/shaders/activity_ring.gdshader）。
##
## 2026-10-08 改版（按美术反馈）：
##   · **融合是「切换」不是「叠加」**：一旦某人被画进融合区域，他的个人圈立刻取消
##     （以前个人圈无条件常显、融合区又故意压在更低的层，于是融合后脚下还留着旧圈）；
##   · 圈只有**半透明实色填充**，不再有粗描边（透明度统一由 FILL_ALPHA 控制）；
##   · 个人圈与融合区**半径一致**（都用 `_ring_radius`），切换时不会一大一小。

const SHADER_PATH := "res://assets/shaders/activity_ring.gdshader"
const STYLE_TABLE := "ui/chat_feedback_style"
## 圈层高度（米）：个人圈与融合区**不会同时出现**，共用一个高度即可
## （既避开 z-fighting，也不会再出现"两层圈"）。
const RING_HEIGHT := 0.016
## 填充透明度：实色但透出地面 —— 美术要求「完全的颜色，但不是色块」
const FILL_ALPHA := 0.5
## 平滑并集宽度（米）：越大，两人相接处越圆润
const BLEND_RADIUS := 0.18
## 最大成员数 / 边数（与着色器数组一致）
const MAX_MEMBERS := 8
const MAX_LINKS := 8

## 颜色不带 alpha：透明度统一由 FILL_ALPHA 决定（个人圈灰蓝 / 活动圈绿）
const COLOR_PERSONAL := Color(0.36, 0.41, 0.46)
const COLOR_ACTIVE := Color(0.20, 0.62, 0.42)

var _core: Variant = null
## 索引 → 个人圈节点（池化复用，不每帧新建）
var _personal: Dictionary = {}
## 会话编号 → 融合区域节点
var _merged: Dictionary = {}
## 未揭晓的成员（照旧只有个人圈）
var _hidden: Dictionary = {}
var _enabled := true
var _ring_radius := 0.3
var _blend_radius := BLEND_RADIUS
var _fill_alpha := FILL_ALPHA
var _shader: Shader = null
var _refresh_timer := 0.0


func _ready() -> void:
	_load_style()
	_shader = load(SHADER_PATH) as Shader
	if _shader == null:
		push_warning("ActivityRingPresenter：找不到 %s —— 脚下圈不渲染。" % SHADER_PATH)
	_enabled = _shader != null


## 绑定本局内核（重复绑定同一个不重复连接）。
func bind_core(core: Variant) -> void:
	if _core == core:
		return
	_core = core
	_clear_all()


func set_enabled(value: bool) -> void:
	_enabled = value and _shader != null
	if not _enabled:
		_clear_all()


func _process(delta: float) -> void:
	if not _enabled or _core == null:
		return
	# 圈只跟位置与真实会话走，不需要每帧重建：10 Hz 足够，且避免频繁创建着色器材质
	_refresh_timer += delta
	if _refresh_timer < 0.1:
		return
	_refresh_timer = 0.0
	refresh()


## 未揭晓的成员：只画个人圈，不进融合区域（防止提前泄露加入结果）。
func hide_member(index: int) -> void:
	_hidden[index] = true
	refresh()


func show_member(index: int) -> void:
	_hidden.erase(index)
	refresh()


func clear_hidden() -> void:
	_hidden.clear()
	refresh()


func is_hidden(index: int) -> bool:
	return _hidden.has(index)


# ------------------------------------------------------------------ 查询（测试用）

## 这个人此刻是否被画成「一块融合区域的一部分」。
func is_merged(index: int) -> bool:
	if _hidden.has(index):
		return false
	var session_id := _session_of(index)
	if session_id < 0 or not _merged.has(session_id):
		return false
	return (_merged[session_id] as MeshInstance3D).visible


func merged_region_count() -> int:
	var count := 0
	for session_id in _merged:
		if (_merged[session_id] as MeshInstance3D).visible:
			count += 1
	return count


func personal_ring_count() -> int:
	return _personal.size()


## 某人此刻所在会话编号（-1 = 不在任何活动里）。
func _session_of(index: int) -> int:
	if _core == null:
		return -1
	return int(_core.session_of(index))


# ------------------------------------------------------------------ 刷新

## 按「个人圈 + 真实会话」重建可见集合（只改表现，不碰内核）。
func refresh() -> void:
	if not _enabled or _core == null:
		return
	var merged_indices := _merged_member_indices()
	var count := int(_core.node_count())
	for index in range(count):
		var ring := _personal_ring(index)
		# 融合是**切换**：已被画进融合区域的人，个人圈直接取消（不再叠一层）。
		if merged_indices.has(index):
			ring.visible = false
			continue
		var pos: Vector2 = _core.position_of(index)
		ring.visible = true
		ring.global_position = Vector3(pos.x, RING_HEIGHT, pos.y)
		_set_material(ring, [index], [], _ring_radius, COLOR_PERSONAL)
	_sync_merged()


## 此刻会被画进融合区域的成员索引（真实会话 + 已揭晓 + 至少两人）。
## 与 `_sync_merged` 用同一套判据，保证「个人圈取消」与「融合区出现」严格同步。
func _merged_member_indices() -> Dictionary:
	var out := {}
	for session in _core.get_active_sessions():
		var members := _visible_members(session)
		if members.size() < 2:
			continue
		for index in members:
			out[int(index)] = true
	return out


func _sync_merged() -> void:
	var sessions: Array = _core.get_active_sessions()
	var alive := {}
	for session in sessions:
		var session_id := int(session["session_id"])
		var members := _visible_members(session)
		if members.size() < 2:
			continue
		alive[session_id] = true
		var node := _merged_region(session_id)
		node.visible = true
		var center := _center_of(members)
		node.global_position = Vector3(center.x, RING_HEIGHT, center.y)
		var quad := node.mesh as PlaneMesh
		quad.size = _quad_size_of(members)
		# 半径与个人圈**一致**：切换时不会突然大一圈（相连交给 link 胶囊）。
		_set_material(node, members, session["links"], _ring_radius, COLOR_ACTIVE)
	for session_id in _merged.keys():
		if not alive.has(session_id):
			(_merged[session_id] as MeshInstance3D).visible = false


## 可用成员（排除未揭晓者与越界索引）。
func _visible_members(session: Dictionary) -> Array:
	var out: Array = []
	for member in session["members"]:
		var index := int(member)
		if _hidden.has(index):
			continue
		if index < 0 or index >= int(_core.node_count()):
			continue
		out.append(index)
	return out


func _center_of(members: Array) -> Vector2:
	var center := Vector2.ZERO
	for index in members:
		center += _core.position_of(int(index))
	return center / float(members.size())


## quad 必须覆盖所有成员圆与连线（否则会被裁掉）。
func _quad_size_of(members: Array) -> Vector2:
	var radius := _ring_radius + _blend_radius + 0.02
	var center := _center_of(members)
	var half := Vector2(radius, radius)
	for index in members:
		var offset: Vector2 = _core.position_of(int(index)) - center
		half = half.max(offset.abs() + Vector2(radius, radius))
	return half * 2.0


func _personal_ring(index: int) -> MeshInstance3D:
	if _personal.has(index):
		return _personal[index]
	var node := MeshInstance3D.new()
	node.name = "PersonalRing_%d" % index
	node.mesh = _plane_mesh()
	node.material_override = _new_material()
	add_child(node)
	_personal[index] = node
	return node


func _merged_region(session_id: int) -> MeshInstance3D:
	if _merged.has(session_id):
		return _merged[session_id]
	var node := MeshInstance3D.new()
	node.name = "MergedRegion_%d" % session_id
	node.mesh = _plane_mesh()
	node.material_override = _new_material()
	add_child(node)
	_merged[session_id] = node
	return node


func _plane_mesh() -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.orientation = PlaneMesh.FACE_Y
	mesh.size = Vector2(1.0, 1.0)
	return mesh


func _new_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _shader
	return material


## 把几何喂给着色器：成员圆 + 连接胶囊，全部换算成相对 quad 中心的局部坐标。
## 填充透明度与平滑融合宽度统一走本组件参数，保证个人圈与融合区观感一致。
func _set_material(
	node: MeshInstance3D, members: Array, links: Array, radius: float, color: Color
) -> void:
	var material := node.material_override as ShaderMaterial
	if material == null:
		return
	var center_pos := node.global_position
	var offset := Vector2(center_pos.x, center_pos.z)
	var points := PackedVector2Array()
	for _k in range(MAX_MEMBERS):
		points.append(Vector2.ZERO)
	var count := mini(members.size(), MAX_MEMBERS)
	for i in range(count):
		var index := int(members[i])
		var position: Vector2 = _core.position_of(index)
		points[i] = position - offset
	var link_a := PackedVector2Array()
	var link_b := PackedVector2Array()
	for _k in range(MAX_LINKS):
		link_a.append(Vector2.ZERO)
		link_b.append(Vector2.ZERO)
	var link_count := 0
	for link in links:
		if link_count >= MAX_LINKS:
			break
		var first := int(link[0])
		var second := int(link[1])
		if not members.has(first) or not members.has(second):
			continue
		link_a[link_count] = _core.position_of(first) - offset
		link_b[link_count] = _core.position_of(second) - offset
		link_count += 1
	material.set_shader_parameter("ring_color", color)
	material.set_shader_parameter("fill_alpha", _fill_alpha)
	material.set_shader_parameter("blend_radius", _blend_radius)
	material.set_shader_parameter("radius", radius)
	material.set_shader_parameter("quad_size", (node.mesh as PlaneMesh).size)
	material.set_shader_parameter("members", points)
	material.set_shader_parameter("member_count", count)
	material.set_shader_parameter("link_a", link_a)
	material.set_shader_parameter("link_b", link_b)
	material.set_shader_parameter("link_count", link_count)


func _clear_all() -> void:
	for node in _personal.values():
		(node as MeshInstance3D).queue_free()
	for node in _merged.values():
		(node as MeshInstance3D).queue_free()
	_personal.clear()
	_merged.clear()


func _load_style() -> void:
	for row in ConfigLoader.new().get_table(STYLE_TABLE).get("rows", []):
		var value := float(str(row.get("value", "0")))
		match str(row.get("param", "")):
			"ring_radius_m":
				_ring_radius = value
			"ring_fill_alpha":
				_fill_alpha = value
			"ring_blend_radius_m":
				_blend_radius = value
