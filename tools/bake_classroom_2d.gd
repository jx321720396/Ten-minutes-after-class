extends SceneTree
## 一次性「烘焙」脚本：在内存里搭好 2D 教室原型，然后写成静态场景 res://scenes/Classroom2D.tscn。
##
## 为什么需要它：以前的版本把教室/桌椅/学生放在运行时代码里生成，编辑器里打开场景是空的。
## 现在改成静态场景——节点真正写进 .tscn，编辑器里点开就能看到、能选中、能拖、能换贴图。
##
## 用法（改完下面参数后重跑即可；会覆盖 res://scenes/Classroom2D.tscn）：
##   godot --headless --path . --script res://tools/bake_classroom_2d.gd
## ⚠️ 重跑会覆盖场景文件，编辑器里对 Classroom2D.tscn 的手工调整会丢失（换贴图建议直接在编辑器里做）。

const OUTPUT_SCENE := "res://scenes/Classroom2D.tscn"

# ---------------------------------------------------------------------------
# 布局参数
# ---------------------------------------------------------------------------
const ROOM_SIZE := Vector2(1920.0, 1080.0)
const WALL_HEIGHT: float = 300.0
const ROWS: int = 2
const COLUMNS: int = 4
## 第一排第一列的课桌桌面左上角
const FIRST_DESK_POSITION := Vector2(320.0, 600.0)
## 相邻课桌的间距（横 / 纵）
const DESK_STEP := Vector2(420.0, 300.0)

const DESK_WIDTH: float = 200.0
const DESK_TOP_HEIGHT: float = 18.0
const DESK_LEG_WIDTH: float = 14.0
const DESK_LEG_HEIGHT: float = 92.0
const CHAIR_SEAT_WIDTH: float = 120.0
const CHAIR_SEAT_HEIGHT: float = 16.0
const CHAIR_BACK_BAR_HEIGHT: float = 14.0
const CHAIR_BACK_POST_WIDTH: float = 10.0
## 椅面与桌腿底之间的空隙
const CHAIR_GAP: float = 6.0
## 椅背（横条）离椅面的高度
const CHAIR_BACK_LIFT: float = 40.0

const BLACKBOARD_POSITION := Vector2(660.0, 60.0)
const BLACKBOARD_SIZE := Vector2(600.0, 240.0)
const WINDOW_SIZE := Vector2(400.0, 180.0)

# ---------------------------------------------------------------------------
# 人物素材与动作参数
# ---------------------------------------------------------------------------
const CHARACTER_DIR := "res://assets/textures/characters/"
## 学生统一缩放后的显示高度（像素）
const STUDENT_TARGET_HEIGHT: float = 200.0
## 8 个学生对应的素材名（2 排 x 4 列，按行依次摆放，男女交替）
const CHARACTER_NAMES: Array[String] = [
	"活泼男", "活泼女", "安静男", "安静女",
	"热情男", "热情女", "社恐男", "社恐女",
]
const BOB_MIN: float = 2.0
const BOB_MAX: float = 5.0
const TILT_DEGREES: float = 2.0
const PERIOD_MIN: float = 0.8
const PERIOD_MAX: float = 1.5
## 固定种子：保证每次烘焙出来的动作参数一致（改这个数就是另一套随机）
const RANDOM_SEED: int = 20260214

const STUDENT_SCRIPT: GDScript = preload("res://scripts/game/student_bob.gd")

# ---------------------------------------------------------------------------
# 占位配色（临时色块，等美术素材到位后替换）
# ---------------------------------------------------------------------------
const COLOR_WALL := Color(0.87, 0.86, 0.82)
const COLOR_FLOOR := Color(0.78, 0.63, 0.47)
const COLOR_SKIRT := Color(0.62, 0.58, 0.52)
const COLOR_BLACKBOARD_FRAME := Color(0.42, 0.33, 0.22)
const COLOR_BLACKBOARD := Color(0.16, 0.35, 0.26)
const COLOR_CHALK_TRAY := Color(0.55, 0.45, 0.32)
const COLOR_PODIUM := Color(0.66, 0.55, 0.40)
const COLOR_WINDOW_GLASS := Color(0.68, 0.82, 0.92)
const COLOR_WINDOW_FRAME := Color(0.55, 0.60, 0.65)
const COLOR_DESK_TOP := Color(0.80, 0.60, 0.36)
const COLOR_DESK_LEG := Color(0.46, 0.34, 0.22)
const COLOR_CHAIR_SEAT := Color(0.56, 0.42, 0.28)
const COLOR_CHAIR_BACK := Color(0.40, 0.30, 0.20)
const COLOR_PLACEHOLDER_SKIN := Color(0.95, 0.80, 0.68)
const PLACEHOLDER_BODY_COLORS: Array[Color] = [
	Color(0.90, 0.35, 0.35), Color(0.35, 0.60, 0.90), Color(0.95, 0.70, 0.25),
	Color(0.40, 0.75, 0.45), Color(0.75, 0.45, 0.85), Color(0.30, 0.75, 0.80),
	Color(0.85, 0.55, 0.75), Color(0.60, 0.60, 0.90),
]

var _rng := RandomNumberGenerator.new()
var _missing_textures: Array[String] = []


func _initialize() -> void:
	_rng.seed = RANDOM_SEED

	var scene_root := Node2D.new()
	scene_root.name = "Classroom2D"
	var room := Node2D.new()
	room.name = "Room"
	scene_root.add_child(room)
	var desks := Node2D.new()
	desks.name = "Desks"
	scene_root.add_child(desks)
	var students := Node2D.new()
	students.name = "Students"
	scene_root.add_child(students)

	_build_room(room)
	for index in CHARACTER_NAMES.size():
		_build_desk(desks, index)
		_build_student(students, index)

	# 只有 owner 指向场景根的节点才会被写进 .tscn
	_assign_owner(scene_root, scene_root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(scene_root)
	if pack_error != OK:
		push_error("打包场景失败：%s" % error_string(pack_error))
		quit(1)
		return
	var save_error := ResourceSaver.save(packed, OUTPUT_SCENE)
	if save_error != OK:
		push_error("保存场景失败：%s" % error_string(save_error))
		quit(1)
		return

	print("[bake] 已生成 %s：课桌椅 %d 套、学生 %d 人" % [
		OUTPUT_SCENE, desks.get_child_count(), students.get_child_count(),
	])
	if not _missing_textures.is_empty():
		push_warning("[bake] 素材未找到，待替换路径：" + ", ".join(_missing_textures))

	# 立即释放临时节点，免得引擎在退出时报一堆 “leaked” 警告
	packed = null
	scene_root.free()
	quit(0)


func _assign_owner(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_assign_owner(child, scene_root)


# ---------------------------------------------------------------------------
# 教室：地板、后墙、黑板、讲台、窗户
# ---------------------------------------------------------------------------
func _build_room(parent: Node2D) -> void:
	_rect(parent, "后墙", Rect2(0.0, 0.0, ROOM_SIZE.x, WALL_HEIGHT), COLOR_WALL)
	_rect(parent, "地板", Rect2(0.0, WALL_HEIGHT, ROOM_SIZE.x, ROOM_SIZE.y - WALL_HEIGHT), COLOR_FLOOR)
	_rect(parent, "踢脚线", Rect2(0.0, WALL_HEIGHT - 10.0, ROOM_SIZE.x, 10.0), COLOR_SKIRT)

	var board := Rect2(BLACKBOARD_POSITION, BLACKBOARD_SIZE)
	_rect(parent, "黑板外框", board.grow(12.0), COLOR_BLACKBOARD_FRAME)
	_rect(parent, "黑板", board, COLOR_BLACKBOARD)
	_rect(parent, "粉笔槽",
			Rect2(board.position.x - 12.0, board.end.y + 12.0, board.size.x + 24.0, 12.0),
			COLOR_CHALK_TRAY)

	_rect(parent, "讲台", Rect2(880.0, WALL_HEIGHT + 20.0, 160.0, 56.0), COLOR_PODIUM)

	_build_window(parent, "左窗", Rect2(120.0, 70.0, WINDOW_SIZE.x, WINDOW_SIZE.y))
	_build_window(parent, "右窗",
			Rect2(ROOM_SIZE.x - 120.0 - WINDOW_SIZE.x, 70.0, WINDOW_SIZE.x, WINDOW_SIZE.y))


func _build_window(parent: Node2D, window_name: String, rect: Rect2) -> void:
	var window := Node2D.new()
	window.name = window_name
	window.position = rect.position
	parent.add_child(window)

	_rect(window, "玻璃", Rect2(Vector2.ZERO, rect.size), COLOR_WINDOW_GLASS)
	var center := rect.size * 0.5
	_line(window, "外框", PackedVector2Array([
		Vector2.ZERO, Vector2(rect.size.x, 0.0), rect.size,
		Vector2(0.0, rect.size.y), Vector2.ZERO,
	]), 6.0, COLOR_WINDOW_FRAME)
	_line(window, "竖框", PackedVector2Array([
		Vector2(center.x, 0.0), Vector2(center.x, rect.size.y),
	]), 5.0, COLOR_WINDOW_FRAME)
	_line(window, "横框", PackedVector2Array([
		Vector2(0.0, center.y), Vector2(rect.size.x, center.y),
	]), 5.0, COLOR_WINDOW_FRAME)


# ---------------------------------------------------------------------------
# 课桌 + 椅子（每个座位 1 套：桌面、两条桌腿、椅背、椅面）
# ---------------------------------------------------------------------------
func _build_desk(parent: Node2D, index: int) -> void:
	var desk := Node2D.new()
	desk.name = "Desk%02d" % (index + 1)
	desk.position = _desk_origin(index)
	parent.add_child(desk)

	_rect(desk, "桌面", Rect2(0.0, 0.0, DESK_WIDTH, DESK_TOP_HEIGHT), COLOR_DESK_TOP)
	_rect(desk, "左桌腿",
			Rect2(18.0, DESK_TOP_HEIGHT, DESK_LEG_WIDTH, DESK_LEG_HEIGHT), COLOR_DESK_LEG)
	_rect(desk, "右桌腿",
			Rect2(DESK_WIDTH - 18.0 - DESK_LEG_WIDTH, DESK_TOP_HEIGHT,
					DESK_LEG_WIDTH, DESK_LEG_HEIGHT), COLOR_DESK_LEG)

	var seat_top := DESK_TOP_HEIGHT + DESK_LEG_HEIGHT + CHAIR_GAP
	var seat_left := (DESK_WIDTH - CHAIR_SEAT_WIDTH) * 0.5
	var back_top := seat_top - CHAIR_BACK_LIFT
	_rect(desk, "椅背横条",
			Rect2(seat_left, back_top, CHAIR_SEAT_WIDTH, CHAIR_BACK_BAR_HEIGHT), COLOR_CHAIR_BACK)
	_rect(desk, "椅背左柱",
			Rect2(seat_left, back_top + CHAIR_BACK_BAR_HEIGHT,
					CHAIR_BACK_POST_WIDTH, CHAIR_BACK_LIFT - CHAIR_BACK_BAR_HEIGHT),
			COLOR_CHAIR_BACK)
	_rect(desk, "椅背右柱",
			Rect2(seat_left + CHAIR_SEAT_WIDTH - CHAIR_BACK_POST_WIDTH,
					back_top + CHAIR_BACK_BAR_HEIGHT,
					CHAIR_BACK_POST_WIDTH, CHAIR_BACK_LIFT - CHAIR_BACK_BAR_HEIGHT),
			COLOR_CHAIR_BACK)
	_rect(desk, "椅面", Rect2(seat_left, seat_top, CHAIR_SEAT_WIDTH, CHAIR_SEAT_HEIGHT), COLOR_CHAIR_SEAT)


# ---------------------------------------------------------------------------
# 学生：1 张立绘 + 动作脚本
# ---------------------------------------------------------------------------
func _build_student(parent: Node2D, index: int) -> void:
	var character_name: String = CHARACTER_NAMES[index]
	var student := Node2D.new()
	student.name = "Student%02d_%s" % [index + 1, character_name]

	student.set_script(STUDENT_SCRIPT)
	student.set("bob_pixels", _rng.randf_range(BOB_MIN, BOB_MAX))
	student.set("tilt_degrees", TILT_DEGREES)
	student.set("period_seconds", _rng.randf_range(PERIOD_MIN, PERIOD_MAX))
	student.set("phase", _rng.randf_range(0.0, TAU))

	student.add_child(_build_student_body(index, character_name))
	student.position = _student_slot(index)
	parent.add_child(student)


func _build_student_body(index: int, character_name: String) -> Node2D:
	var body := Node2D.new()
	body.name = "Body"

	var texture_path := CHARACTER_DIR + character_name + ".png"
	var texture: Texture2D = null
	if ResourceLoader.exists(texture_path):
		# 用 CACHE_MODE_IGNORE 载入：脚本退出时贴图能立刻释放，免得引擎报 “RID/resource leaked” 噪声
		texture = ResourceLoader.load(texture_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D

	if texture != null:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.centered = true
		var scale_factor: float = STUDENT_TARGET_HEIGHT / float(texture.get_height())
		sprite.scale = Vector2(scale_factor, scale_factor)
		body.add_child(sprite)
	else:
		_missing_textures.append(texture_path)
		_build_placeholder_student_body(body, index)
	return body


func _build_placeholder_student_body(body: Node2D, index: int) -> void:
	var body_color: Color = PLACEHOLDER_BODY_COLORS[index % PLACEHOLDER_BODY_COLORS.size()]
	_rect(body, "头", Rect2(-26.0, -100.0, 52.0, 72.0), COLOR_PLACEHOLDER_SKIN)
	_rect(body, "躯干", Rect2(-30.0, -28.0, 60.0, 108.0), body_color)
	_rect(body, "左腿", Rect2(-26.0, 80.0, 20.0, 40.0), COLOR_DESK_LEG)
	_rect(body, "右腿", Rect2(6.0, 80.0, 20.0, 40.0), COLOR_DESK_LEG)


# ---------------------------------------------------------------------------
# 座位换算
# ---------------------------------------------------------------------------
func _desk_origin(index: int) -> Vector2:
	var row := floori(float(index) / float(COLUMNS))
	var column := index % COLUMNS
	return FIRST_DESK_POSITION + Vector2(DESK_STEP.x * float(column), DESK_STEP.y * float(row))


## 学生站在自己课桌后面（屏幕上位于桌面上方）
func _student_slot(index: int) -> Vector2:
	var origin := _desk_origin(index)
	return Vector2(origin.x + DESK_WIDTH * 0.5, origin.y - STUDENT_TARGET_HEIGHT * 0.5 - 6.0)


# ---------------------------------------------------------------------------
# 画色块的小工具
# ---------------------------------------------------------------------------
func _rect(parent: Node, node_name: String, rect: Rect2, color: Color) -> ColorRect:
	var block := ColorRect.new()
	block.name = node_name
	block.color = color
	block.position = rect.position
	block.size = rect.size
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(block)
	return block


func _line(parent: Node, node_name: String, points: PackedVector2Array, width: float, color: Color) -> Line2D:
	var line := Line2D.new()
	line.name = node_name
	line.points = points
	line.width = width
	line.default_color = color
	parent.add_child(line)
	return line
