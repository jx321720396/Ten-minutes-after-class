class_name PlayerEmotionFeedback
extends CanvasLayer
## 玩家四情绪反馈（表现层，只读）：只展示**玩家自己这一侧**已结算的效果。
##
## 依据：主文档 §8（压力与情绪）、§12.1（玩家不扫别人内心）；
##      docs/superpowers/plans/2026-10-07-player-click-emotion-feedback.md、
##      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §8.3。
##
## ⚠️ **素材状态**：用户已有的「放松 / 生气 / 哭泣 / 开心」男女八图**实际文件路径尚未收录**，
##    因此本组件用**公开文字 + 颜色**呈现（计划 §8.3 明确允许阶段开发这样做），
##    **不得**在情绪图片验收里勾选完成，也**不得**凭空填一个不存在的图片路径。
##    图片收录后只需替换 `_texture_for()` 一处，映射与判定不变。
##
## 映射只用「本次已结算的玩家自身效果摘要 + 玩家当前压力」，不看 NPC 内心、不看角色身份：
##   · 敌对上升（或好感下降）→ 生气；
##   · 自身压力上升 → 伤心；
##   · 好感上升且当前压力高 → 放松（总算松口气）；否则 → 开心。
## 全部阈值来自 data/ui/chat_feedback_style.csv。

const STYLE_TABLE := "ui/chat_feedback_style"
const FACE_TABLE := "ui/emotion_faces"
const EMOTION_RELAXED := "relaxed"
const EMOTION_ANGRY := "angry"
const EMOTION_CRYING := "crying"
const EMOTION_HAPPY := "happy"
## 学习态（§8.23）：不是情绪，但一样走气泡反馈，让玩家看得出自己在学
const EMOTION_STUDYING := "studying"
const BUBBLE_SIZE := Vector2(112.0, 40.0)
## 气泡里表情图的边长（像素）
const FACE_SIZE := 28.0
## 玩家情绪气泡相对头顶锚点的抬高量（米）：与聊天气泡错开，不叠在一起
const ANCHOR_LIFT := 0.34

const TEXTS := {
	EMOTION_RELAXED: "放松",
	EMOTION_ANGRY: "生气",
	EMOTION_CRYING: "难受",
	EMOTION_HAPPY: "开心",
	EMOTION_STUDYING: "学习中",
}
const COLORS := {
	EMOTION_RELAXED: Color(0.28, 0.58, 0.52, 0.95),
	EMOTION_ANGRY: Color(0.72, 0.30, 0.24, 0.95),
	EMOTION_CRYING: Color(0.30, 0.42, 0.68, 0.95),
	EMOTION_HAPPY: Color(0.78, 0.58, 0.20, 0.95),
	EMOTION_STUDYING: Color(0.20, 0.42, 0.30, 0.95),
}

var _core: Variant = null
var _actors: Node3D = null
var _clock: SimulationClock = null
var _bubble: PanelContainer = null
var _label: Label = null
var _face: TextureRect = null
## 情绪（含学习态）→ 表情图路径；来自 data/ui/emotion_faces.csv
var _faces: Dictionary = {}
var _current := ""
var _left := 0.0
## 映射阈值（全部来自呈现表）
var _positive_affinity := 1.0
var _negative_hostility := 1.0
var _crying_stress := 1.0
var _high_stress := 60.0
var _anchor_height := 1.5


func _ready() -> void:
	_load_style()
	_load_faces()
	_build_ui()
	_bubble.visible = false


func bind_core(core: Variant) -> void:
	_core = core


func bind_actors(actors: Node3D) -> void:
	_actors = actors


func bind_clock(clock: SimulationClock) -> void:
	_clock = clock


# ------------------------------------------------------------------ 映射（可测的纯函数）


## 本次已结算的玩家自身效果 → 一个表情。effects 见 PlayerInteractions 的 player_effects。
func pick_emotion(effects: Dictionary, stress: float) -> String:
	var hostility := float(effects.get("hostility_delta", 0.0))
	var affinity := float(effects.get("affinity_delta", 0.0))
	var stress_delta := float(effects.get("stress_delta", 0.0))
	if hostility >= _negative_hostility or affinity <= -_negative_hostility:
		return EMOTION_ANGRY
	if stress_delta >= _crying_stress:
		return EMOTION_CRYING
	if affinity >= _positive_affinity:
		if stress >= _high_stress:
			return EMOTION_RELAXED
		return EMOTION_HAPPY
	if stress_delta <= -_crying_stress:
		return EMOTION_RELAXED
	return EMOTION_HAPPY


func emotion_text(kind: String) -> String:
	return str(TEXTS.get(kind, ""))


func current_emotion() -> String:
	return _current


func is_visible_now() -> bool:
	return _bubble != null and _bubble.visible


# ------------------------------------------------------------------ 展示


## 显示一次情绪（seconds 后自动淡出）。
func show_emotion(kind: String, seconds: float = 4.0) -> void:
	if _bubble == null or not TEXTS.has(kind):
		return
	_current = kind
	_left = maxf(0.5, seconds)
	_label.text = emotion_text(kind)
	_label.add_theme_color_override("font_color", COLORS[kind])
	var face := face_for(kind)
	if _face != null:
		_face.texture = face
		_face.visible = face != null
	_bubble.visible = true


## 该情绪对应的表情图（按玩家性别）；无配图返回 null。
func face_for(kind: String) -> Texture2D:
	# 安全读：测试（GUT）里 GameState.player_gender 可能尚未设定，直接取会报错
	var gs := get_node_or_null("/root/GameState")
	var gender := "male"
	var raw_gender: Variant = gs.get("player_gender") if gs != null else null
	if raw_gender != null and str(raw_gender) == "female":
		gender = "female"
	var path := str(_faces.get("face_%s_%s" % [kind, gender], ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path)


func clear() -> void:
	_current = ""
	_left = 0.0
	if _bubble != null:
		_bubble.visible = false


func _process(delta: float) -> void:
	if _bubble == null or not _bubble.visible:
		return
	_follow()
	if _left <= 0.0:
		return
	_left = maxf(0.0, _left - delta)
	_bubble.modulate.a = minf(1.0, _left / 0.6)
	if _left <= 0.0:
		clear()


## 贴在玩家头顶（相机投影）；暂停与切场景都不留残留。
func _follow() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _core == null:
		clear()
		return
	var world := _player_anchor()
	if camera.is_position_behind(world):
		_bubble.visible = false
		return
	_bubble.visible = true
	_bubble.position = camera.unproject_position(world) - BUBBLE_SIZE * 0.5


func _player_anchor() -> Vector3:
	var index := -1
	if _core != null:
		index = int(_core.node_count()) - 1
	if _actors != null and index >= 0 and _actors.has_method("feedback_anchor_of"):
		var anchor: Node3D = _actors.feedback_anchor_of(index)
		if anchor != null:
			return anchor.global_position + Vector3(0.0, ANCHOR_LIFT, 0.0)
	var position: Vector2 = _core.position_of(index)
	return Vector3(position.x, _anchor_height + ANCHOR_LIFT, position.y)


func _build_ui() -> void:
	_bubble = PanelContainer.new()
	_bubble.name = "EmotionBubble"
	_bubble.custom_minimum_size = BUBBLE_SIZE
	_bubble.size = BUBBLE_SIZE
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1.0, 0.99, 0.96, 0.92)
	box.set_corner_radius_all(12)
	box.set_content_margin_all(6.0)
	_bubble.add_theme_stylebox_override("panel", box)
	# Label 没有 icon 属性（那是 Button 的）—— 图与字并排得用容器。
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_face = TextureRect.new()
	_face.name = "Face"
	_face.custom_minimum_size = Vector2(FACE_SIZE, FACE_SIZE)
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_face.visible = false
	row.add_child(_face)
	_label = Label.new()
	_label.name = "Text"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_font_override("font", _font())
	row.add_child(_label)
	_bubble.add_child(row)
	add_child(_bubble)


func _font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(
		["Microsoft YaHei", "微软雅黑", "SimHei", "Noto Sans CJK SC", "PingFang SC", "sans-serif"]
	)
	return font


## 情绪 → 表情图（data/ui/emotion_faces.csv）。
func _load_faces() -> void:
	for row in ConfigLoader.new().get_table(FACE_TABLE).get("rows", []):
		_faces[str(row.get("param", ""))] = str(row.get("value", ""))


func _load_style() -> void:
	for row in ConfigLoader.new().get_table(STYLE_TABLE).get("rows", []):
		var value := float(str(row.get("value", "0")))
		match str(row.get("param", "")):
			"emotion_positive_affinity_delta":
				_positive_affinity = value
			"emotion_negative_hostility_delta":
				_negative_hostility = value
			"emotion_crying_stress_delta":
				_crying_stress = value
			"emotion_high_stress":
				_high_stress = value
			"bubble_follow_height_m":
				_anchor_height = value
