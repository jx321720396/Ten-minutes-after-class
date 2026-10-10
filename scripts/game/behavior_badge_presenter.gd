class_name BehaviorBadgePresenter
extends CanvasLayer
## 头顶行为徽标（§20.1.4）：只反映**看得见的公开状态**，不做动画、不参与着色逻辑。
##
## 本批接线的第一种徽标（§21.2.9「持有者表现」）：**谁手里正拿着纸条** —— 在人物头侧挂一张
## 小纸片。**不显示纸条内容，也不显示是谁写的**；纸片上那两道线只是形状，不表达任何信息。
##
## 其余五种徽标（听音乐 / 吃零食 / 看课外书 / 睡着了 / 专注学习中）在对应行为实装后接**同一个**
## 组件：徽标数据完全由内核的公开状态给出，本组件不自己推断、也不缓存判定结果。
##
## ⚠️ 反例（§20.1.4 明确不做）：不给「压力高」「好感高」「正在被排挤」这类**隐藏状态**做徽标 ——
##    那等于把隐藏状态搬到脸上。新增徽标前先回到第二十章补定义。

const COLOR_PAPER := Color(0.99, 0.98, 0.90, 0.98)
const COLOR_EDGE := Color(0.45, 0.42, 0.34)
const COLOR_INK_LINE := Color(0.62, 0.60, 0.54)
## 小纸片尺寸与相对人物锚点的偏移（像素）：放头侧偏上，给头顶的气泡让位
const BADGE_SIZE := Vector2(22.0, 16.0)
const BADGE_OFFSET := Vector2(-36.0, -32.0)
## 纸上的两道线（只是形状）
const LINE_SIZE := Vector2(14.0, 1.5)
const LINE_SPACING := 4.0
## 没有 3D 锚点时的退化高度（米）
const FALLBACK_HEIGHT := 1.5

var _core: Variant = null
var _actors: Node3D = null
var _badges: Dictionary = {}


func _ready() -> void:
	set_process(true)


# ------------------------------------------------------------------ 绑定
func bind_core(core: Variant) -> void:
	_core = core


func bind_actors(actors: Node3D) -> void:
	_actors = actors


# ------------------------------------------------------------------ 只读查询（测试 / 调试）
## 当前挂着徽标的节点编号（升序）。
func badge_holders() -> Array:
	var out: Array = _badges.keys()
	out.sort()
	return out


func has_badge(index: int) -> bool:
	return _badges.has(index)


func badge_count() -> int:
	return _badges.size()


## 收掉所有徽标（换场景 / 退出时用；不撤销任何内核结算）。
func clear() -> void:
	for index in _badges.keys():
		var badge: Control = _badges[index]
		_badges.erase(index)
		badge.queue_free()


# ------------------------------------------------------------------ 每帧
func _process(_delta: float) -> void:
	_sync()
	_layout()


## 徽标集合完全跟随内核的公开状态：多出来的补、走掉的收。
func _sync() -> void:
	var wanted: Array = []
	if _core != null and is_instance_valid(_core):
		wanted = _core.note_holders()
	for index in _badges.keys():
		if not wanted.has(int(index)):
			var gone: Control = _badges[int(index)]
			_badges.erase(index)
			gone.queue_free()
	for index in wanted:
		var i := int(index)
		if _badges.has(i):
			continue
		var badge := _make_note_badge()
		add_child(badge)
		_badges[i] = badge


## 把每张徽标贴到人物头侧（与头顶气泡同一套投影方式）。
func _layout() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for index in _badges:
		var badge: Control = _badges[index]
		var screen := camera.unproject_position(_anchor_of(int(index)))
		badge.position = screen + BADGE_OFFSET


func _anchor_of(index: int) -> Vector3:
	if _actors != null and is_instance_valid(_actors):
		var anchor: Node3D = _actors.feedback_anchor_of(index)
		if anchor != null and is_instance_valid(anchor):
			return anchor.global_position
	if _core == null or not is_instance_valid(_core):
		return Vector3.ZERO
	var position: Vector2 = _core.position_of(index)
	return Vector3(position.x, FALLBACK_HEIGHT, position.y)


# ------------------------------------------------------------------ 徽标外观
## 一张小纸片：纸色底 + 描边 + 两道线。**不做动画**（§20.1.4）。
func _make_note_badge() -> Control:
	var root := Control.new()
	root.name = "NoteBadge"
	root.size = BADGE_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := Panel.new()
	paper.name = "Paper"
	paper.size = BADGE_SIZE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PAPER
	box.border_color = COLOR_EDGE
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	paper.add_theme_stylebox_override("panel", box)
	root.add_child(paper)
	for k in range(2):
		var line := Panel.new()
		line.name = "Line%d" % k
		line.size = LINE_SIZE
		line.position = Vector2(4.0, 4.5 + float(k) * LINE_SPACING)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var line_box := StyleBoxFlat.new()
		line_box.bg_color = COLOR_INK_LINE
		line.add_theme_stylebox_override("panel", line_box)
		root.add_child(line)
	return root
