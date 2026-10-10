class_name TermTooltip
extends CanvasLayer
## 术语悬停解释 —— 把「百科词条」接到界面上的通用入口。
##
## 用法一（正文里的高亮词）：
## [codeblock]
## var tt := preload("res://scenes/ui/term_tooltip.tscn").instantiate()
## add_child(tt)
## tt.bind_rich_text(some_rich_text_label)
## some_rich_text_label.text = TermTooltip.mark_terms(原文)
## [/codeblock]
## `mark_terms()` 会把正文里出现的词条名 / 别名包成 `[url=entry:<id>]…[/url]`，
## 鼠标移上去就弹出该词条的短解释。
##
## 用法二（旁边的问号）：
## [codeblock]
## tt.attach_question(row_of_a_profile_page, "attr.affinity")
## [/codeblock]
##
## 数据一律来自 `data/localization/encyclopedia.json`，本脚本**不写任何文案**
## （`docs/localization/本地化说明.md` §2 禁止硬编码中文字面量）。
##
## 信息纪律（§20.0.1 / §7）：只解释机制，不写 NPC 的隐藏数值，也不描述「此刻某人怎样」。

const ENCYCLOPEDIA := preload("res://scripts/ui/encyclopedia.gd")
const META_PREFIX := "entry:"

## 面板锚点与尺寸（屏幕空间）
const PANEL_MAX_WIDTH := 420.0
const MOUSE_OFFSET := Vector2(18.0, 18.0)

@onready var _panel: PanelContainer = $Panel
@onready var _term_label: RichTextLabel = $Panel/Margin/VBox/TermLabel
@onready var _body_label: RichTextLabel = $Panel/Margin/VBox/BodyLabel

## 每个被绑定过的 RichTextLabel → true（避免重复连接）
var _bound: Dictionary = {}
var _showing := ""


func _ready() -> void:
	_panel.visible = false
	# 悬停面板不吃鼠标，否则会挡住下面的词、导致 hover 反复进出
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 宽度以脚本常量为准（场景里的值只是编辑器里的预览）
	_panel.custom_minimum_size = Vector2(PANEL_MAX_WIDTH, 0.0)


func _input(event: InputEvent) -> void:
	# 点击任意处收起
	if (
		_showing != ""
		and event is InputEventMouseButton
		and (event as InputEventMouseButton).pressed
	):
		hide_term()


# ------------------------------------------------------------------ 用法一：正文高亮


## 绑定一个 RichTextLabel：它的 `[url=entry:…]` 悬停时会弹出词条。
func bind_rich_text(label: RichTextLabel) -> void:
	if label == null or _bound.has(label):
		return
	_bound[label] = true
	label.meta_hover_started.connect(_on_meta_hover_started.bind(label))
	label.meta_hover_ended.connect(_on_meta_hover_ended)


## 把正文里出现的词条名 / 别名包成可悬停标记。
##
## 规则：
## - 长名字优先（`好感度` 先于 `好感`），避免短词把长词吃掉；
## - 同名区间只包一次，不做嵌套；
## - 已经是 `[url=…]` 的区间不重复包。
static func mark_terms(text: String) -> String:
	if text.is_empty():
		return text
	var candidates := _name_candidates()
	if candidates.is_empty():
		return text

	# 1) 收集所有命中区间（含 id），**不动原文**
	var hits: Array = []
	var taken: Array = []  # [start, end]
	for cand in candidates:
		var name: String = cand["name"]
		var from := 0
		while true:
			var start := text.find(name, from)
			if start < 0:
				break
			var end := start + name.length()
			from = start + 1
			if _overlaps(taken, start, end):
				continue
			if _inside_existing_markup(text, start, end):
				continue
			taken.append([start, end])
			hits.append({"start": start, "end": end, "id": cand["id"], "name": name})

	# 2) 从后往前替换，避免下标错位
	hits.sort_custom(func(a, b): return int(a["start"]) > int(b["start"]))
	var out := text
	for hit in hits:
		var s: int = hit["start"]
		var e: int = hit["end"]
		out = (
			out.substr(0, s)
			+ "[url=%s%s]%s[/url]" % [META_PREFIX, hit["id"], out.substr(s, e - s)]
			+ out.substr(e)
		)
	return out


# ------------------------------------------------------------------ 用法二：问号


## 在 `anchor` 右侧挂一个问号，鼠标移上去弹出该词条。
## 返回挂上的按钮（一般不用管），entry_id 无效时返回 null。
func attach_question(anchor: Control, entry_id: String) -> Button:
	if anchor == null or ENCYCLOPEDIA.find_entry(entry_id).is_empty():
		push_warning("TermTooltip：词条不存在，问号未挂上：%s" % entry_id)
		return null
	var btn := Button.new()
	btn.name = "TermQuestion_%s" % entry_id.replace(".", "_")
	btn.text = "?"
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = ""
	btn.custom_minimum_size = Vector2(24, 24)
	anchor.add_child(btn)
	btn.mouse_entered.connect(func(): _show_entry(entry_id, btn.get_global_rect().end))
	btn.mouse_exited.connect(hide_term)
	return btn


# ------------------------------------------------------------------ 面板


## 直接按 id 弹出（供外部按需调用）。
func show_term(entry_id: String, at: Vector2 = Vector2.ZERO) -> void:
	_show_entry(entry_id, at)


func hide_term() -> void:
	_showing = ""
	_panel.visible = false


func _on_meta_hover_started(meta: Variant, _label: RichTextLabel) -> void:
	var m := str(meta)
	if not m.begins_with(META_PREFIX):
		return
	# 位置传 ZERO → _place() 改用鼠标当前位置，提示就贴在光标边上
	_show_entry(m.substr(META_PREFIX.length()), Vector2.ZERO)


func _on_meta_hover_ended() -> void:
	# 面板本身不吃鼠标，所以离开词就收起；点进百科看全文由点击另行处理
	hide_term()


func _show_entry(entry_id: String, at: Vector2) -> void:
	var entry := ENCYCLOPEDIA.find_entry(entry_id)
	if entry.is_empty():
		return
	_showing = entry_id
	var term := str(entry.get("term", ""))
	var short := str(entry.get("short", ""))
	var body := _first_paragraph(str(entry.get("body", "")))

	_term_label.clear()
	_term_label.append_text("[font_size=26][b]%s[/b][/font_size]" % term)
	if not short.is_empty():
		_term_label.append_text("\n[color=#6b7a5e][i]%s[/i][/color]" % short)

	_body_label.clear()
	_body_label.append_text(body)

	_panel.visible = true
	_place(at)


## 面板定位：以传入点为左上角，并夹在屏幕内。
func _place(at: Vector2) -> void:
	if at == Vector2.ZERO:
		at = get_viewport().get_mouse_position() + MOUSE_OFFSET
	_panel.size = Vector2.ZERO  # 先让容器按内容算一次
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	var size := _panel.size
	var pos := at
	if pos.x + size.x > vp.x - 8.0:
		pos.x = maxf(8.0, vp.x - size.x - 8.0)
	if pos.y + size.y > vp.y - 8.0:
		# 下面放不下就翻到光标上方
		pos.y = maxf(8.0, at.y - size.y - MOUSE_OFFSET.y)
	_panel.global_position = pos


## 取正文首段（悬停只给一小口，全文去看百科）。
static func _first_paragraph(body: String) -> String:
	var cut := body.find("\n\n")
	var first := body if cut < 0 else body.substr(0, cut)
	return first.strip_edges()


# ------------------------------------------------------------------ 匹配辅助


## 全部「词条名 + 别名」，按长度降序；同时给出所属词条 id。
static func _name_candidates() -> Array:
	var entries := _all_entries()
	var out: Array = []
	for e in entries:
		var d: Dictionary = e
		var id := str(d.get("id", ""))
		var names: Array = [str(d.get("term", ""))]
		names.append_array(d.get("aliases", []) as Array)
		for n in names:
			var name := str(n).strip_edges()
			if name.length() >= 2:
				out.append({"name": name, "id": id})
	out.sort_custom(func(a, b): return str(a["name"]).length() > str(b["name"]).length())
	return out


static func _all_entries() -> Array:
	var f := FileAccess.open("res://data/localization/encyclopedia.json", FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return []
	var out: Array = []
	for e in (parsed as Dictionary).get("entries", []):
		if e is Dictionary and bool((e as Dictionary).get("implemented", false)):
			out.append(e)
	return out


static func _overlaps(taken: Array, start: int, end: int) -> bool:
	for r in taken:
		var a: int = r[0]
		var b: int = r[1]
		if start < b and end > a:
			return true
	return false


## 该区间是否已经落在 `[url=…]…[/url]` 之内（避免把已有标记再包一层）。
##
## 判据：在 start 之前，最后一个 `[url=` 比最后一个 `[/url]` 更靠后 → 说明仍未闭合、我们在标记内部。
static func _inside_existing_markup(text: String, start: int, _end: int) -> bool:
	var last_open := text.rfind("[url=", start)
	if last_open < 0:
		return false
	var last_close := text.rfind("[/url]", start)
	return last_open > last_close
