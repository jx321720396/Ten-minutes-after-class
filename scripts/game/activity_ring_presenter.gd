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
## 渲染：每个活动一块横置 PlaneMesh，片元用 SDF 求「成员圆 ∪ 连接胶囊」的并集 ——
## 融合区域因此没有内部双边框（见 assets/shaders/activity_ring.gdshader）。

const SHADER_PATH := "res://assets/shaders/activity_ring.gdshader"
const STYLE_TABLE := "ui/chat_feedback_style"
## 个人圈的高度（米）：略高于地面，避免与融合区域互相 z-fighting
const PERSONAL_HEIGHT := 0.016
## 融合区域的高度（米）：比个人圈低一点点，个人圈描边仍可见
const MERGED_HEIGHT := 0.010
## 最大成员数 / 边数（与着色器数组一致）
const MAX_MEMBERS := 8
const MAX_LINKS := 8

const COLOR_PERSONAL := Color(0.36, 0.41, 0.46, 0.75)
const COLOR_ACTIVE := Color(0.20, 0.62, 0.42, 0.85)

var _core: Variant = null
## 索引 → 个人圈节点（池化复用，不每帧新建）
var _personal: Dictionary = {}
## 会话编号 → 融合区域节点
var _merged: Dictionary = {}
## 未揭晓的成员（照旧只有个人圈）
var _hidden: Dictionary = {}
var _enabled := true
var _ring_radius := 0.3
var _line_width := 0.035
var _merge_gap := 0.16
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
	var count := int(_core.node_count())
	for index in range(count):
		var ring := _personal_ring(index)
		ring.visible = true
		ring.global_position = Vector3(_core.position_of(index).x, PERSONAL_HEIGHT, _core.position_of(index).y)
		_set_material(ring, [index], [], _ring_radius, 0.0, COLOR_PERSONAL)
	_sync_merged()


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
		node.global_position = Vector3(center.x, MERGED_HEIGHT, center.y)
		var quad := node.mesh as PlaneMesh
		quad.size = _quad_size_of(members)
		_set_material(node, members, session["links"], _ring_radius + _merge_gap, 0.26, COLOR_ACTIVE)
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
	var radius := _ring_radius + _merge_gap + _line_width
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
func _set_material(
	node: MeshInstance3D, members: Array, links: Array, radius: float, fill: float, color: Color
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
	material.set_shader_parameter("fill_alpha", fill)
	material.set_shader_parameter("line_width", _line_width)
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
			"ring_line_width_m":
				_line_width = value
			"ring_merge_gap_m":
				_merge_gap = value
