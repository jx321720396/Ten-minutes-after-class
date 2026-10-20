class_name BehaviorBadgePresenter
extends CanvasLayer
## 头顶行为徽标（§20.1.4）：只反映**看得见的公开状态**，不做动画、不参与着色逻辑。
##
## 徽标白名单与文案都集中在 `data/ui/behavior_badges.json` 的 `activity_labels`：
## 聊天 / 听音乐 / 吃零食 / 玩手机 / 看课外书 / 吵架 / 推搡 / 打架。
## 徽标数据完全由内核的公开状态给出，本组件不自己推断、也不缓存判定结果。
##
## ⚠️ 反例（§20.1.4 明确不做）：不给「压力高」「好感高」「正在被排挤」这类**隐藏状态**做徽标 ——
##    那等于把隐藏状态搬到脸上。新增徽标前先回到第二十章补定义。

const COLOR_PAPER := Color(0.99, 0.98, 0.90, 0.98)
const COLOR_EDGE := Color(0.45, 0.42, 0.34)
## 字号、屏幕缩放、头顶间隙与活动文案统一配置。
const LAYOUT_PATH := "res://data/ui/behavior_badges.json"

var _core: Variant = null
var _actors: Node3D = null
var _activity_badges: Dictionary = {}
## 每个徽标对应的活动名（决定是否额外抬升给头顶符号让位）。
var _badge_kinds: Dictionary = {}
var _labels: Dictionary = {}
var _layout_settings: Dictionary = {}


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if parsed is Dictionary:
		_layout_settings = parsed
	_labels.clear()
	for key in _layout_settings.get("activity_labels", {}):
		_labels[str(key)] = str(_layout_settings["activity_labels"][key])
	set_process(true)


# ------------------------------------------------------------------ 绑定
func bind_core(core: Variant) -> void:
	_core = core


func bind_actors(actors: Node3D) -> void:
	_actors = actors


# ------------------------------------------------------------------ 只读查询（测试 / 调试）
## 当前挂徽标人物的活动文案（没挂则返回空串）。
func activity_badge_text(index: int) -> String:
	if not _activity_badges.has(index):
		return ""
	return str((_activity_badges[index] as Label).text)


## 当前挂徽标人物的活动名（没挂则返回空串）。
func activity_badge_kind(index: int) -> String:
	return str(_badge_kinds.get(index, ""))


## 收掉所有徽标（换场景 / 退出时用；不撤销任何内核结算）。
func clear() -> void:
	for badge in _activity_badges.values():
		badge.queue_free()
	_activity_badges.clear()
	_badge_kinds.clear()


# ------------------------------------------------------------------ 每帧
func _process(_delta: float) -> void:
	_sync()
	_layout()


## 徽标集合完全跟随内核的公开状态：多出来的补、走掉的收。
func _sync() -> void:
	_sync_activities()


## 公开活动的头顶文字徽标；白名单与文案来自 data/ui/behavior_badges.json。
func _sync_activities() -> void:
	var wanted := {}
	var wanted_kinds := {}
	if _core != null and is_instance_valid(_core):
		for i in range(int(_core.node_count())):
			var activity := str(_core.activity_of(i))
			if not _labels.has(activity):
				continue
			wanted[i] = str(_labels[activity])
			wanted_kinds[i] = activity
	for i in _activity_badges.keys():
		if not wanted.has(i):
			(_activity_badges[i] as Label).queue_free()
			_activity_badges.erase(i)
			_badge_kinds.erase(i)
	for i in wanted:
		if not _activity_badges.has(i):
			var badge := Label.new()
			badge.add_theme_font_override(
				"font", preload("res://scripts/ui/game_fonts.gd").regular()
			)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_theme_color_override("font_color", COLOR_PAPER)
			badge.add_theme_color_override("font_shadow_color", COLOR_EDGE)
			badge.add_theme_constant_override("shadow_offset_x", 1)
			badge.add_theme_constant_override("shadow_offset_y", 1)
			add_child(badge)
			_activity_badges[i] = badge
		(_activity_badges[i] as Label).text = str(wanted[i])
		_badge_kinds[i] = str(wanted_kinds[i])


func _layout() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if _layout_settings.is_empty():
		return
	var view_scale := clampf(
		get_viewport().get_visible_rect().size.y / float(_layout_settings.reference_height_pixels),
		float(_layout_settings.minimum_view_scale),
		float(_layout_settings.maximum_view_scale)
	)
	for index in _activity_badges:
		var badge := _activity_badges[index] as Label
		var world := _anchor_of(int(index))
		badge.visible = not camera.is_position_behind(world)
		badge.add_theme_font_size_override("font_size", int(_layout_settings.font_size))
		badge.size = badge.get_minimum_size()
		badge.scale = Vector2.ONE * view_scale
		# 聊天文字再抬高一点，避开头顶上浮的聊天符号（data 的 chat_lift_pixels）
		var lift := float(_layout_settings.head_gap_pixels)
		if str(_badge_kinds.get(int(index), "")) == "chat":
			lift += float(_layout_settings.get("chat_lift_pixels", 0.0))
		badge.position = (
			camera.unproject_position(world)
			- Vector2(badge.size.x * view_scale * 0.5, (badge.size.y + lift) * view_scale)
		)


func _anchor_of(index: int) -> Vector3:
	if _actors != null and is_instance_valid(_actors):
		if _actors.has_method("head_position_of"):
			return _actors.head_position_of(index)
		var anchor: Node3D = _actors.feedback_anchor_of(index)
		if anchor != null and is_instance_valid(anchor):
			return anchor.global_position
	if _core == null or not is_instance_valid(_core):
		return Vector3.ZERO
	var position: Vector2 = _core.position_of(index)
	return Vector3(position.x, float(_layout_settings.fallback_height_m), position.y)
