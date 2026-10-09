extends Control
## 百科全书（词条式）—— 每个机制一条，随时可查。
##
## 内容来源：`data/localization/encyclopedia.json`
##   { categories: [ { id, title, order, intro? } ],
##     entries:    [ { id, term, category, short, body, aliases, implemented, player_usable? } ] }
## 文案一律不进代码（`docs/localization/本地化说明.md` §2 禁止硬编码中文字面量）。
##
## 左侧是可折叠的分类树：点分类标题展开 / 收起，点词条看正文。
## 本页**不做悬停解释** —— 悬停组件是给别处（角色档案、简报）用的，见 scripts/ui/term_tooltip.gd。
##
## 信息纪律（§20.0.1 / §7）：词条只解释**机制**，不描述「此刻某人怎样」，
## 也不写 NPC 的隐藏数值。`implemented=false` 的条目**不列出**。

signal closed

const DATA_PATH := "res://data/localization/encyclopedia.json"

## 折叠标记（用符号，不用字母/数字编号）
const ARROW_COLLAPSED := "▶ "
const ARROW_EXPANDED := "▼ "

@onready var _toc: VBoxContainer = $CenterContainer/Panel/Margin/VBox/Body/TOCScroll/TOC
@onready
var _scroll: ScrollContainer = $CenterContainer/Panel/Margin/VBox/Body/ContentMargin/ContentScroll
@onready
var _content: RichTextLabel = $CenterContainer/Panel/Margin/VBox/Body/ContentMargin/ContentScroll/Content
@onready var _prev: Button = $CenterContainer/Panel/Margin/VBox/Footer/PrevBtn
@onready var _next: Button = $CenterContainer/Panel/Margin/VBox/Footer/NextBtn
@onready var _back: Button = $CenterContainer/Panel/Margin/VBox/Footer/BackBtn

## 可见词条（按分类顺序铺平）；目录里的词条按钮与它一一对应
var _entries: Array = []
## 每个分类一组：{ title, header: Button, entry_indices: Array[int], rows: Array[Button], expanded: bool }
var _cats: Array = []
var _index := 0
## 词条按钮列表，用于给当前项加高亮
var _entry_buttons: Array = []

static var _all_entries: Array = []


func _ready() -> void:
	_prev.pressed.connect(_on_prev)
	_next.pressed.connect(_on_next)
	_back.pressed.connect(_on_back)
	_load_data()
	if not _entries.is_empty():
		_show_entry(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()


# ------------------------------------------------------------------ 供外部查询

## 可见词条数（供测试与调试）。
func entry_count() -> int:
	return _entries.size()


func current_entry_term() -> String:
	if _entries.is_empty() or _index < 0 or _index >= _entries.size():
		return ""
	return str((_entries[_index] as Dictionary).get("term", ""))


## 当前展开的分类数（供测试）。
func expanded_category_count() -> int:
	var n := 0
	for c in _cats:
		if bool((c as Dictionary).get("expanded", false)):
			n += 1
	return n


## 兼容旧调用点：语义已由「章节」变为「词条」。
func chapter_count() -> int:
	return entry_count()


func current_chapter_title() -> String:
	return current_entry_term()


## 按 id 取词条（含未实装的）。找不到返回空字典。全局唯一取词入口。
static func find_entry(entry_id: String) -> Dictionary:
	if _all_entries.is_empty():
		_all_entries = _read_entries_from_disk()
	for e in _all_entries:
		if str((e as Dictionary).get("id", "")) == entry_id:
			return e
	return {}


## 按正文里出现的词（词条名或别名）反查词条 id。找不到返回空串。
static func id_for_term(word: String) -> String:
	if _all_entries.is_empty():
		_all_entries = _read_entries_from_disk()
	var w := word.strip_edges()
	if w.is_empty():
		return ""
	for e in _all_entries:
		var d: Dictionary = e
		if str(d.get("term", "")) == w:
			return str(d.get("id", ""))
		for a in d.get("aliases", []) as Array:
			if str(a) == w:
				return str(d.get("id", ""))
	return ""


# ------------------------------------------------------------------ 数据

static func _read_entries_from_disk() -> Array:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("Encyclopedia：读不到 %s" % DATA_PATH)
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_error("Encyclopedia：%s 不是合法 JSON" % DATA_PATH)
		return []
	var out: Array = []
	for e in (parsed as Dictionary).get("entries", []):
		if e is Dictionary:
			out.append(e)
	return out


func _load_data() -> void:
	_entries = []
	_cats = []
	_entry_buttons = []
	for child in _toc.get_children():
		child.queue_free()

	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("Encyclopedia：读不到 %s" % DATA_PATH)
		_content.clear()
		_content.append_text("[i]（百科全书内容文件缺失）[/i]")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_error("Encyclopedia：%s 不是合法 JSON" % DATA_PATH)
		return
	var data: Dictionary = parsed
	_all_entries = _read_entries_from_disk()

	var cats: Array = (data.get("categories", []) as Array).duplicate()
	cats.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	var all_entries: Array = data.get("entries", [])

	for cat in cats:
		var cat_id := str((cat as Dictionary).get("id", ""))
		var rows: Array = []
		for e in all_entries:
			var d: Dictionary = e
			if str(d.get("category", "")) != cat_id:
				continue
			if not bool(d.get("implemented", false)):
				continue  # 未实装的先不上线
			rows.append(d)
		if rows.is_empty():
			continue
		# _build_category 内部已把自己登记进 _cats，这里**不能再 append**（否则每类重复一次）
		_build_category(str((cat as Dictionary).get("title", cat_id)), rows)

	# 默认展开哪一类不在这里定：_show_entry(0) → _sync_toc_selection 会展开当前词条所在类


## 建一个分类：可点击的标题行 + 若干词条行（展开时才显示）。
func _build_category(title: String, rows: Array) -> Dictionary:
	var header := Button.new()
	header.name = "Cat_%s" % title
	header.text = ARROW_COLLAPSED + title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.focus_mode = Control.FOCUS_NONE
	header.add_theme_font_size_override("font_size", 24)
	_toc.add_child(header)

	var buttons: Array = []
	var indices: Array[int] = []
	for d in rows:
		_entries.append(d)
		var idx := _entries.size() - 1
		indices.append(idx)
		var btn := Button.new()
		btn.name = "Entry_%s" % str(d.get("id", idx)).replace(".", "_")
		btn.text = "　　%s" % str(d.get("term", ""))  # 全角空格缩进，不用编号
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 22)
		btn.visible = false
		# 当前词条用「按下」态高亮（走 Theme 的 pressed 样式），不再改 modulate 染色
		btn.toggle_mode = true
		btn.pressed.connect(_on_entry_pressed.bind(idx))
		_toc.add_child(btn)
		buttons.append(btn)
		_entry_buttons.append(btn)

	var cat := {"title": title, "header": header, "entry_indices": indices,
		"rows": buttons, "expanded": false}
	header.pressed.connect(_on_category_pressed.bind(_cats.size()))
	_cats.append(cat)
	return cat


# ------------------------------------------------------------------ 渲染

func _show_entry(i: int) -> void:
	if _entries.is_empty():
		return
	_index = clampi(i, 0, _entries.size() - 1)
	var e: Dictionary = _entries[_index]

	var out := "[font_size=32][b]%s[/b][/font_size]\n" % str(e.get("term", ""))
	var short := str(e.get("short", ""))
	if not short.is_empty():
		out += "[color=#6b7a5e][i]%s[/i][/color]\n" % short
	out += "\n%s\n" % _plain_refs(str(e.get("body", "")))

	_content.clear()
	_content.append_text(out.strip_edges())
	_sync_toc_selection()
	_update_buttons()
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 0


## 把文案里的 `[t]词条名[/t]` 跨引用标记去掉，只留文字。
##
## 百科页**不做悬停**：悬停组件（scripts/ui/term_tooltip.gd）是给**别处**用的 ——
## 角色档案、每日简报这类「正文里突然冒出一个术语」的地方。
## 百科本身就是解释术语的去处，再给它套悬停只会自相矛盾。
static func _plain_refs(body: String) -> String:
	var re := RegEx.new()
	re.compile("\\[t\\]([^\\[\\]]+)\\[/t\\]")
	var out := body
	for m in re.search_all(body):
		out = out.replace(m.get_string(0), m.get_string(1))
	return out


# ------------------------------------------------------------------ 目录交互

func _on_category_pressed(cat_index: int) -> void:
	if cat_index < 0 or cat_index >= _cats.size():
		return
	var cat: Dictionary = _cats[cat_index]
	_set_category_expanded(cat_index, not bool(cat.get("expanded", false)))


func _set_category_expanded(cat_index: int, expanded: bool) -> void:
	var cat: Dictionary = _cats[cat_index]
	cat["expanded"] = expanded
	(cat["header"] as Button).text = (ARROW_EXPANDED if expanded else ARROW_COLLAPSED) + str(cat.get("title", ""))
	for btn in cat.get("rows", []) as Array:
		(btn as Button).visible = expanded


func _on_entry_pressed(entry_index: int) -> void:
	_show_entry(entry_index)


## 目录高亮当前词条，并保证它所在分类是展开的。
func _sync_toc_selection() -> void:
	if _entries.is_empty():
		return
	for btn in _entry_buttons:
		(btn as Button).button_pressed = false
	if _index < 0 or _index >= _entry_buttons.size():
		return
	(_entry_buttons[_index] as Button).button_pressed = true
	for ci in range(_cats.size()):
		if (_cats[ci] as Dictionary).get("entry_indices", []).has(_index):
			if not bool((_cats[ci] as Dictionary).get("expanded", false)):
				_set_category_expanded(ci, true)
			return


func _update_buttons() -> void:
	_prev.disabled = _index <= 0
	_next.disabled = _index >= _entries.size() - 1


# ------------------------------------------------------------------ 交互

func _on_prev() -> void:
	_show_entry(_index - 1)


func _on_next() -> void:
	_show_entry(_index + 1)


func _on_back() -> void:
	emit_signal("closed")
