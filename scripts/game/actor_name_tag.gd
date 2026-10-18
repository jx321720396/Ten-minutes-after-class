class_name ActorNameTag
extends Label3D
## 角色名字牌（竖排）：坐姿贴在图片左侧、站姿回到头顶，并做温和的近大远小。
##
## 两种布局，每帧按角色当前姿态切换（不写死高度，全部取自贴图实际包围盒）：
##   · 坐姿：名字整体摆在**坐姿图片的屏幕左侧**，且**垂直与图片中心对齐** —— 不挡脸、不挡身体；
##   · 站姿：名字回到**头顶正上方**（文字底边贴头顶），横向居中于角色。
##
## 为什么用 top_level：坐姿图片挂在座位节点的分层里、站姿贴图挂在 actor 上，两者不是同一个
## 坐标系；这里统一按**世界坐标**每帧重算位置，省掉来回换算。
##
## 口径：只读相机与贴图包围盒，不读写任何矩阵 / 时间数值；不设 fixed_size（名字随距离变化）。

## 该距离（米）上缩放系数为 1；比它近略放大、比它远略缩小。
@export var reference_distance: float = 12.0
## 近处上限：前排离相机近本来就会被透视放大，这里不再额外放大。
@export var max_scale: float = 0.95
## 远处下限：太小的名字等于没写。
@export var min_scale: float = 0.82
## 名字中心离坐姿图片中心的横向距离（米）：约等于人物半宽 + 一点间隙，
## 用固定值而不用素材包围盒宽 —— 坐姿素材两侧留了大量透明区，按盒宽算会飘太远。
@export var side_offset: float = 0.34
## 站姿时文字底边离头顶的高度（米）
@export var head_gap: float = 0.04
## 竖排的行距（像素，负值收紧）：默认行距太大，两字名会拉得很散。
@export var row_spacing: int = -18

## 站姿贴图（actor 下的 `Sprite`）：坐姿时它会被隐藏，名字据此判断当前姿态。
var stand_sprite: Sprite3D = null
## 坐姿分层节点（`layered_student_pose`）：由 ClassroomActors 挂好坐姿后填进来。
var seat_pose: Node3D = null
## 坐姿用的竖排文本 / 站姿用的横排文本（都带换行差异，由 ClassroomActors 填）。
var seat_text: String = ""
var stand_text: String = ""
## 站姿头顶高度（actor 局部坐标，米）：拿不到贴图包围盒时的兜底值。
var head_y: float = 1.35


func _ready() -> void:
	# 坐姿图与站姿图不在一个坐标系里，统一用世界坐标重算；首帧算出来之前先不画。
	top_level = true
	visible = false
	line_spacing = row_spacing


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var seated := _is_seated()
	_apply_layout(seated)
	var anchor := _seated_anchor(camera) if seated else _standing_anchor()
	global_position = anchor
	var distance := camera.global_position.distance_to(anchor)
	if distance > 0.01:
		scale = Vector3.ONE * clampf(reference_distance / distance, min_scale, max_scale)
	visible = true


## 坐姿：竖排 + 与胸口平齐；站姿：横排 + 底边贴头顶。切换只在真的变了时写一次。
func _apply_layout(seated: bool) -> void:
	var wanted := seat_text if seated else stand_text
	if wanted.is_empty():
		return
	if text != wanted:
		text = wanted
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER if seated else VERTICAL_ALIGNMENT_BOTTOM


## 坐姿 = 站姿贴图被藏起来（ClassroomActors 每帧按姿态切换这个可见性）。
func _is_seated() -> bool:
	if seat_pose == null or not is_instance_valid(seat_pose):
		return false
	if stand_sprite != null and is_instance_valid(stand_sprite) and stand_sprite.visible:
		return false
	return true


## 站姿：头顶正上方、横向居中于角色。
func _standing_anchor() -> Vector3:
	var owner_actor := get_parent() as Node3D
	if owner_actor == null:
		return global_position
	var top := owner_actor.to_global(Vector3(0.0, _stand_top_y(), 0.0))
	top.y += head_gap
	return top


## 站姿头顶（actor 局部坐标）：实时取贴图包围盒 —— build 阶段 sprite 还没入树，
## `get_aabb()` 是空的，所以不能在那一刻算好写死（会偏到肩膀高度）。
func _stand_top_y() -> float:
	var sprite := stand_sprite
	if sprite == null or not is_instance_valid(sprite):
		return head_y
	var box := sprite.get_aabb()
	if box.size.y <= 0.0:
		return head_y
	return sprite.position.y + box.position.y + box.size.y


## 坐姿：图片左侧、垂直与图片中心对齐（「左侧」= 相机右向量的反方向）。
func _seated_anchor(camera: Camera3D) -> Vector3:
	var box := _seated_bounds()
	if box.size == Vector3.ZERO:
		return _standing_anchor()
	var right := camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return box.get_center()
	return box.get_center() - right.normalized() * side_offset


## 坐姿「胸口」高度用的包围盒：取上半身那张贴图（`Upper`）。
## 不能用整体 AABB —— 它把桌面和腿一起算进去，中心正好落在桌面高度，名字就跑到桌角了。
func _seated_bounds() -> AABB:
	var upper := seat_pose.get_node_or_null("Upper") as Sprite3D
	if upper != null and upper.is_visible_in_tree():
		return upper.global_transform * upper.get_aabb()
	var merged := AABB()
	var found := false
	for child in seat_pose.get_children():
		var sprite := child as Sprite3D
		if sprite == null or not sprite.is_visible_in_tree():
			continue
		var box: AABB = sprite.global_transform * sprite.get_aabb()
		merged = box if not found else merged.merge(box)
		found = true
	return merged if found else AABB()
