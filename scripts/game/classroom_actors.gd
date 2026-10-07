extends Node3D
## 课间空间的人物摆放（表现层）：把本局内核的每个节点放到 seats.csv 对应的座位上。
##
## 数据流（单向、只读）：
##   GameState.sim_core（本局唯一内核实例）
##     → 只读访问器 node_count() / seat_of(i) / character_id(i) / alias(i) / is_player(i)
##     → 座位节点 Seats/<seat_id>（scenes/game/classroom3D.tscn，与 data/rules/seats.csv 同名）
##     → 立绘 scenes/characters/<sprite>.tscn（sprite 名查 data/characters/appearance.csv）
##
## 铁律：只读内核、不回写任何矩阵；**不在脚本里按角色名 / 角色编号分支**（主文档 §11.1）——
##      外观一律查 data/characters/appearance.csv。
##
## ⚠️ 人物是「纸片人」：Sprite3D 绕 Y 跟随相机（BILLBOARD_FIXED_Y），不参与碰撞与寻路；
##    走动 / 聚散是后续可视化层的事（§15.1），本脚本只负责「坐在自己的座位上」。

const APPEARANCE_TABLE := "characters/appearance"
const CHARACTER_SCENE_DIR := "res://scenes/characters/"
const PLAYER_LABEL := "我"
## 名字牌字体：优先中文字族，末位 sans-serif 兜底（Windows / macOS / Linux 都能命中一个）
const NAME_FONTS: Array[String] = [
	"Microsoft YaHei",
	"微软雅黑",
	"SimHei",
	"Noto Sans CJK SC",
	"PingFang SC",
	"sans-serif",
]

@export_group("数据来源")
## 座位父节点：其子节点名必须等于 data/rules/seats.csv 的 seat_id（P0…P16）
@export var seat_root_path: NodePath = ^"../Seats"

@export_group("立绘摆放")
## 纸片人在世界里的高度（米）
@export var character_height: float = 1.35
## 立绘底部离地高度（米）：0 = 踩在地面上
@export var foot_offset: float = 0.02
## 前后偏移（米）：座位原点在课桌中心，椅子在 -z 一侧
@export var chair_offset_z: float = -0.45
## 像素素材用最近邻过滤（保持像素风，不被插值糊掉）
@export var keep_pixel_edges: bool = true

@export_group("名字牌")
@export var show_name_tags: bool = true
@export var name_font_size: int = 64
@export var name_pixel_size: float = 0.0035
@export var name_outline_size: int = 10
## 名字牌离头顶的高度（米）
@export var name_gap: float = 0.14
@export var name_color: Color = Color(0.13, 0.14, 0.18)
@export var name_outline_color: Color = Color(1, 1, 1)
## 玩家自己的名字牌颜色（与 NPC 区分）
@export var player_name_color: Color = Color(0.85, 0.25, 0.22)

@export_group("占位标记")
## 玩家不是 NPC 角色 / 立绘缺失时的色块标记
@export var marker_radius: float = 0.13
@export var marker_height: float = 0.85
@export var player_marker_color: Color = Color(0.95, 0.72, 0.25)
## 立绘缺失时的占位色
@export var missing_marker_color: Color = Color(0.75, 0.45, 0.85)

@export_group("行走组件")
## 给每个人物挂上行走组件（scenes/components/actor_walker.tscn），
## 由教室里的驱动器（classroom_roam.gd / 或将来的内核 position）调用
@export var attach_walker: bool = true
## 行走组件场景；留空则不挂
@export var walker_scene: PackedScene = preload("res://scenes/components/actor_walker.tscn")

@export_group("单场景调试")
## 直接运行本场景（不经主菜单）时自动建一个演示局 —— 便于在编辑器 / MCP 里
## 直接跑 classroom3D.tscn 就能看到人物。正常流程由 main_menu 调 GameState.start_game。
@export var auto_start_demo: bool = true
## 演示局种子（0 = 按系统时间随机）
@export var demo_seed: int = 20261007

var _appearances: Dictionary = {}
## 名字牌字体只加载一次（SystemFont 会去查系统字体，逐人新建会拖慢进教室）
var _name_font_cache: Font = null


func _ready() -> void:
	var core: Variant = current_core()
	if core == null:
		core = _start_demo_game()
	if core == null:
		push_error("ClassroomActors：没有本局内核实例（GameState.sim_core 为空）——请从主菜单「新游戏」进入教室。")
		return
	build(core)


## 单场景调试：直接运行本场景（不经主菜单）时自动建一个演示局，并写入 GameState，
## 让同级的表现层组件（classroom_roam）读到同一个内核实例。正常流程不会走到这里。
func _start_demo_game() -> Variant:
	if not auto_start_demo:
		return null
	var state: Variant = get_node_or_null("/root/GameState")
	if state == null:
		return null
	var game_seed := demo_seed
	if game_seed == 0:
		game_seed = int(Time.get_unix_time_from_system())
	var difficulty := Config.default_difficulty()
	state.start_game(game_seed, difficulty)
	push_warning(
		(
			"ClassroomActors：单场景运行 —— 已自动建演示局（种子 %d，难度 %d）；" % [game_seed, difficulty]
			+ "正常流程请从主菜单「新游戏」进入。"
		)
	)
	return state.sim_core


## 本局内核实例；缺失返回 null。
## 用字符串路径取单例，便于无头测试注入一个同名节点（不依赖 autoload 是否加载）。
func current_core() -> Variant:
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return null
	return state.sim_core


## 按内核座位摆人，返回实际落位的人物数（等于内核节点数才算全部落位）。
func build(core: Variant) -> int:
	_clear_actors()
	if core == null:
		return 0
	var seat_root := get_node_or_null(seat_root_path)
	if seat_root == null:
		push_error("ClassroomActors：找不到座位父节点 %s" % str(seat_root_path))
		return 0
	_appearances = _load_appearances()

	var count := int(core.node_count())
	var placed := 0
	for i in range(count):
		var seat_id := str(core.seat_of(i))
		var seat := seat_root.get_node_or_null(seat_id) as Node3D
		if seat == null:
			push_warning(
				"ClassroomActors：座位 %s 不在 %s 下（seats.csv 与场景不一致）" % [seat_id, str(seat_root_path)]
			)
			continue
		var actor := _build_actor(core, i)
		add_child(actor)
		actor.global_position = seat.global_position + Vector3(0.0, foot_offset, chair_offset_z)
		_attach_walker(actor)
		placed += 1
	if placed != count:
		push_warning("ClassroomActors：内核 %d 个节点，实际落位 %d 个" % [count, placed])
	return placed


## 给人物挂上行走组件（组件只负责「怎么走」，不判断该不该走）。
func _attach_walker(actor: Node3D) -> void:
	if not attach_walker or walker_scene == null:
		return
	var walker := walker_scene.instantiate()
	walker.name = "Walker"
	actor.add_child(walker)


## 清掉上一次生成的人物（重复 build / 热重载时不会叠人）。
func _clear_actors() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _build_actor(core: Variant, i: int) -> Node3D:
	var actor := Node3D.new()
	if bool(core.is_player(i)):
		actor.name = "Player"
		actor.add_child(_build_marker(player_marker_color))
		if show_name_tags:
			actor.add_child(_build_name_tag(PLAYER_LABEL, player_name_color))
		return actor

	var character_id := str(core.character_id(i))
	actor.name = "Actor_%s" % (character_id if not character_id.is_empty() else str(i))
	var sprite_name := str(_appearances.get(character_id, ""))
	var texture := _load_texture(sprite_name)
	if texture == null:
		push_warning(
			(
				"ClassroomActors：角色 %s 的外观未命中（appearance.csv 的 sprite=「%s」）——用色块占位。"
				% [character_id, sprite_name]
			)
		)
		actor.add_child(_build_marker(missing_marker_color))
	else:
		actor.add_child(_build_sprite(texture))
	if show_name_tags:
		actor.add_child(_build_name_tag(str(core.alias(i)), name_color))
	return actor


## 立绘（纸片人）：高度统一到 character_height，宽度按素材比例。
func _build_sprite(texture: Texture2D) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	if keep_pixel_edges:
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var pixel_height := maxi(texture.get_height(), 1)
	sprite.pixel_size = character_height / float(pixel_height)
	# Sprite3D 默认以自身中心为原点（centered）→ 抬高半个身高，底部落在脚底
	sprite.position = Vector3(0.0, character_height * 0.5, 0.0)
	return sprite


func _build_name_tag(text: String, color: Color) -> Label3D:
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.text = text
	tag.font = _name_font()
	tag.font_size = name_font_size
	tag.pixel_size = name_pixel_size
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = name_outline_size
	tag.modulate = color
	tag.outline_modulate = name_outline_color
	tag.no_depth_test = true
	tag.position = Vector3(0.0, character_height + name_gap, 0.0)
	return tag


func _name_font() -> Font:
	if _name_font_cache == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(NAME_FONTS)
		_name_font_cache = font
	return _name_font_cache


## 色块占位（本人 / 立绘缺失）：一眼能看出「这里有人」。
func _build_marker(color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = marker_radius
	mesh.height = marker_radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	marker.mesh = mesh
	marker.material_override = material
	marker.position = Vector3(0.0, marker_height, 0.0)
	return marker


## 角色编号 → 立绘名（data/characters/appearance.csv）。
func _load_appearances() -> Dictionary:
	var out := {}
	var rows: Array = ConfigLoader.new().get_table(APPEARANCE_TABLE).get("rows", [])
	for row in rows:
		out[str(row.get("id", ""))] = str(row.get("sprite", ""))
	return out


## 从 scenes/characters/<sprite>.tscn 里取贴图（贴图路径只在角色场景里写一次）。
func _load_texture(sprite_name: String) -> Texture2D:
	if sprite_name.is_empty():
		return null
	var path := CHARACTER_SCENE_DIR + sprite_name + ".tscn"
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate()
	var texture := _find_texture(node)
	node.free()
	return texture


func _find_texture(node: Node) -> Texture2D:
	if node is Sprite2D:
		return (node as Sprite2D).texture
	for child in node.get_children():
		var found := _find_texture(child)
		if found != null:
			return found
	return null
