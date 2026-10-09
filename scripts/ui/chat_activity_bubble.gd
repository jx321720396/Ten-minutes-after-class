class_name ChatActivityBubble
extends CanvasLayer
## 头顶**无字**聊天气泡（表现层，只读）：一次真实闲聊的成员各挂一个三点气泡。
##
## 依据：docs/superpowers/plans/2026-10-07-chat-playable-loop.md §8.1。
##
## 用意：不写对白也能看出「这两个人正在说话」 —— 三点依次淡入淡出即可，
## 不需要任何台词素材，也不给每个关系边各生成一个进度条。
##
## 约束：
##   · 只读真实会话（`get_active_sessions()`），不按行为名猜；
##   · 未揭晓的加入者在揭晓前**不出现气泡**（防止提前泄露结果）；
##   · 世界被 hold（转笔演出 / 暂停）时**停掉点动画**，恢复后接着来；
##   · 会话结束 / 中断 / 切场景都不残留（`_sync` 收掉多余节点）。

const BUBBLE_SIZE := Vector2(54.0, 26.0)
const DOT_SIZE := 8.0
const DOT_SPACING := 6.0
const STYLE_TABLE := "ui/chat_feedback_style"
const COLOR_PAPER := Color(0.99, 0.98, 0.94, 0.95)
const COLOR_DOT := Color(0.25, 0.30, 0.28)
## 气泡锚点相对人物锚点再抬高的量（米），避免压住名字牌
const ANCHOR_LIFT := 0.18

var _core: Variant = null
var _actors: Node3D = null
var _clock: SimulationClock = null
var _time_flow: TimeFlow = null
## 索引 → 气泡节点
var _bubbles: Dictionary = {}
var _hidden: Dictionary = {}
## 每个点的动画相位（三个点依次亮）
var _phase := 0.0
var _dot_seconds := 0.45
## 没有人物节点时的兜底锚点高度（米；来自 ui/chat_feedback_style.csv）
var _anchor_height := 1.5


func _ready() -> void:
	_load_style()


func bind_core(core: Variant) -> void:
	if _core == core:
		return
	_core = core
	_sync()


## 人物容器（取每个索引的反馈锚点；缺失时退化成内核坐标）。
func bind_actors(actors: Node3D) -> void:
	_actors = actors


func bind_clock(clock: SimulationClock) -> void:
	_clock = clock


func bind_time_flow(flow: TimeFlow) -> void:
	_time_flow = flow


func hide_member(index: int) -> void:
	_hidden[index] = true
	_sync()


func show_member(index: int) -> void:
	_hidden.erase(index)
	_sync()


func clear_hidden() -> void:
	_hidden.clear()
	_sync()


func bubble_count() -> int:
	var count := 0
	for index in _bubbles:
		if (_bubbles[index] as Control).visible:
			count += 1
	return count


## 这个人此刻有没有无字气泡（会话结束 / 未揭晓 / 越界都应返回 false）。
func has_bubble(index: int) -> bool:
	if not _bubbles.has(index):
		return false
	return (_bubbles[index] as Control).visible


func _process(delta: float) -> void:
	if _core == null:
		return
	var paused := _clock != null and is_instance_valid(_clock) and _clock.is_paused()
	if not paused:
		var world_delta := _time_flow.scale_delta(delta) if is_instance_valid(_time_flow) else delta
		_phase += world_delta / maxf(_dot_seconds, 0.01)
	_sync()
	_layout()


## 哪些人应该出现气泡：在真实会话里、且未被隐藏。
func _sync() -> void:
	if _core == null:
		return
	var wanted := {}
	for session in _core.get_active_sessions():
		if str(session["kind"]) != "chat":
			continue
		for member in session["members"]:
			var index := int(member)
			if _hidden.has(index):
				continue
			wanted[index] = true
	for index in wanted:
		_bubble(index).visible = true
	for index in _bubbles:
		if not wanted.has(index):
			(_bubbles[index] as Control).visible = false


## 每帧把气泡贴到人物头顶（相机投影），并推进三点动画。
func _layout() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for index in _bubbles:
		var bubble: Control = _bubbles[index]
		if not bubble.visible:
			continue
		var world := _anchor_of(int(index))
		if camera.is_position_behind(world):
			bubble.visible = false
			continue
		var screen := camera.unproject_position(world)
		bubble.position = screen - BUBBLE_SIZE * 0.5
		_animate(bubble)


func _anchor_of(index: int) -> Vector3:
	if _actors != null and _actors.has_method("feedback_anchor_of"):
		var anchor: Node3D = _actors.feedback_anchor_of(index)
		if anchor != null:
			return anchor.global_position + Vector3(0.0, ANCHOR_LIFT, 0.0)
	var position: Vector2 = _core.position_of(index)
	return Vector3(position.x, _anchor_height + ANCHOR_LIFT, position.y)


func _animate(bubble: Control) -> void:
	var dots := bubble.get_node_or_null("Dots")
	if dots == null:
		return
	var count := dots.get_child_count()
	for k in range(count):
		var dot := dots.get_child(k) as Control
		# 三个点依次亮：相位差 1/3 圈
		var t := fmod(_phase - float(k) / float(maxi(count, 1)), 1.0)
		dot.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * TAU))


func _bubble(index: int) -> Control:
	if _bubbles.has(index):
		return _bubbles[index]
	var root := Control.new()
	root.name = "Bubble_%d" % index
	root.position = Vector2.ZERO
	root.custom_minimum_size = BUBBLE_SIZE
	root.size = BUBBLE_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := Panel.new()
	body.name = "Body"
	body.size = BUBBLE_SIZE
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_stylebox_override("panel", _round_box(COLOR_PAPER, 12.0))
	root.add_child(body)
	var dots := HBoxContainer.new()
	dots.name = "Dots"
	dots.add_theme_constant_override("separation", int(DOT_SPACING))
	dots.position = Vector2(
		BUBBLE_SIZE.x * 0.5 - (DOT_SIZE * 3.0 + DOT_SPACING * 2.0) * 0.5,
		BUBBLE_SIZE.y * 0.5 - DOT_SIZE * 0.5
	)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dots)
	for _k in range(3):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.add_theme_stylebox_override("panel", _round_box(COLOR_DOT, DOT_SIZE * 0.5))
		dots.add_child(dot)
	add_child(root)
	_bubbles[index] = root
	return root


func _round_box(color: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(radius))
	box.content_margin_left = 0.0
	box.content_margin_right = 0.0
	return box


func _load_style() -> void:
	for row in ConfigLoader.new().get_table(STYLE_TABLE).get("rows", []):
		var value := float(str(row.get("value", "0")))
		match str(row.get("param", "")):
			"bubble_dot_seconds":
				_dot_seconds = maxf(0.05, value)
			"bubble_follow_height_m":
				_anchor_height = maxf(0.2, value)
