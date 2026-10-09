extends Control
## 百科全书（词条式）—— 每个机制一条，随时可查。
##
## 内容来源：`data/localization/encyclopedia.json`
##   { categories: [ { id, title, order, intro? } ],
##     entries:    [ { id, term, category, short, body, aliases, implemented, player_usable? } ] }
## 文案一律不进代码（`docs/localization/本地化说明.md` §2 禁止硬编码中文字面量）。
##
## 与档案页 / 简报的关系：本页是**独立查阅**入口；档案页与正文里的「问号 / 高亮词」
## 走同一个数据源（见 `scripts/ui/term_tooltip.gd`）。为此每条的 `id` 是稳定引用键，
## 任何地方引用词条都用 id，不要用中文名去匹配。
##
## 信息纪律（§20.0.1 / §7）：词条只解释**机制**，不描述「此刻某人怎样」，
## 也不写 NPC 的隐藏数值。`implemented=false` 的条目**不列出**（占位文案先不上线）。
##
## 界面风格与其它窗口一致：半透明遮罩 + 米黄 PanelContainer，Esc / 返回按钮关闭。

signal closed

const DATA_PATH := "res://data/localization/encyclopedia.json"

@onready var _toc: ItemList = $CenterContainer/Panel/Margin/VBox/Body/TOC
@onready
var _scroll: ScrollContainer = $CenterContainer/Panel/Margin/VBox/Body/ContentMargin/ContentScroll
@onready
var _content: RichTextLabel = $CenterContainer/Panel/Margin/VBox/Body/ContentMargin/ContentScroll/Content
@onready var _prev: Button = $CenterContainer/Panel/Margin/VBox/Footer/PrevBtn
@onready var _next: Button = $CenterContainer/Panel/Margin/VBox/Footer/NextBtn
@onready var _back: Button = $CenterContainer/Panel/Margin/VBox/Footer/BackBtn

## 数据（按 presentable 过滤后的结果，目录顺序 = categories.order → entries 原序）
var _entries: Array = []
## 目录里第 i 项对应的 `_entries` 下标；类别标题行记 -1（不可选）
var _toc_to_entry: Array[int] = []
var _index := 0

## 词条库里全部条目（含未实装），供 tooltip 等按 id 取用
static var _all_entries: Array = []


func _ready() -> void:
	_prev.pressed.connect(_on_prev)
	_next.pressed.connect(_on_next)
	_back.pressed.connect(_on_back)
	_toc.item_selected.connect(_on_toc_selected)
	_load_data()
	_show_entry(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()


# ------------------------------------------------------------------ 供外部查询

## 词条总数（对外可见的那些；供测试与调试）。
func entry_count() -> int:
	return _entries.size()


## 当前词条名（供测试与调试）。
func current_entry_term() -> String:
	if _entries.is_empty() or _index < 0 or _index >= _entries.size():
		return ""
	return str((_entries[_index] as Dictionary).get("term", ""))


## 兼容旧调用点：语义已由「章节」变为「词条」。
func chapter_count() -> int:
	return entry_count()


func current_chapter_title() -> String:
	return current_entry_term()


## 按 id 取词条（含未实装的）。找不到返回空字典。
## 这是全局唯一取词入口 —— 档案页的问号、正文高亮都用它。
static func find_entry(entry_id: String) -> Dictionary:
	if _all_entries.is_empty():
		_all_entries = _read_entries_from_disk()
	for e in _all_entries:
		if str((e as Dictionary).get("id", "")) == entry_id:
			return e
	return {}


## 按正文里出现的词（词条名或别名）反查词条 id。找不到返回空串。
## 供「行为文字特殊化 + 悬停解释」使用：先把可见文字切出候选词，再用它匹配。
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


## 读文件 → 按类别顺序铺开成「可见词条」列表，并同步目录。
func _load_data() -> void:
	_entries = []
	_toc_to_entry = []
	_toc.clear()

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
		# 该类下**已实装**的条目；未实装的先不上线
		var rows: Array = []
		for e in all_entries:
			var d: Dictionary = e
			if str(d.get("category", "")) != cat_id:
				continue
			if not bool(d.get("implemented", false)):
				continue
			rows.append(d)
		if rows.is_empty():
			continue
		# 类别标题行（不可选）
		_toc.add_item(str((cat as Dictionary).get("title", cat_id)))
		_toc_to_entry.append(-1)
		_toc.set_item_disabled(_toc.item_count - 1, true)
		for d in rows:
			_entries.append(d)
			_toc.add_item("    %s" % str(d.get("term", "")))
			_toc_to_entry.append(_entries.size() - 1)

	_update_buttons()


# ------------------------------------------------------------------ 渲染

## 渲染第 i 条词条：词条名 + 短句 + 正文。
func _show_entry(i: int) -> void:
	if _entries.is_empty():
		return
	_index = clampi(i, 0, _entries.size() - 1)
	var e: Dictionary = _entries[_index]

	var out := "[font_size=32][b]%s[/b][/font_size]\n" % str(e.get("term", ""))
	var short := str(e.get("short", ""))
	if not short.is_empty():
		out += "[color=#6b7a5e][i]%s[/i][/color]\n" % short
	out += "\n" + str(e.get("body", "")) + "\n"

	_content.clear()
	_content.append_text(out.strip_edges())
	_sync_toc_selection()
	_update_buttons()
	# 等一帧让新内容完成布局，再回到顶部
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 0


## 让左侧目录选中当前词条那一行（跳过类别标题行）。
func _sync_toc_selection() -> void:
	for row in range(_toc_to_entry.size()):
		if _toc_to_entry[row] == _index:
			_toc.select(row)
			return


func _update_buttons() -> void:
	_prev.disabled = _index <= 0
	_next.disabled = _index >= _entries.size() - 1


# ------------------------------------------------------------------ 交互

func _on_toc_selected(row: int) -> void:
	if row < 0 or row >= _toc_to_entry.size():
		return
	var target := _toc_to_entry[row]
	if target < 0:
		# 类别标题行：不切内容
		_sync_toc_selection()
		return
	_show_entry(target)


func _on_prev() -> void:
	_show_entry(_index - 1)


func _on_next() -> void:
	_show_entry(_index + 1)


func _on_back() -> void:
	emit_signal("closed")
