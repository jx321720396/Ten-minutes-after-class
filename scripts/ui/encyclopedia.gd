extends Control
## 百科全书（主菜单入口）—— 分章节的玩家手册。
##
## 内容来源：`data/localization/encyclopedia.json`
##   { chapters: [ { title, intro?, sections: [ { heading, body } ] } ] }
## 该 JSON 由 `docs/localization/百科全书文案.md` 转出；**文案一律不进代码**
## （`docs/localization/本地化说明.md` §2 禁止硬编码中文字面量）。
##
## 与其它界面保持同一风格：半透明遮罩 + 米黄 PanelContainer + 标题 44 / 正文 24，
## 关闭方式与 `about_menu.gd` 一致（`signal closed` + Esc）。

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

var _chapters: Array = []
var _index := 0


func _ready() -> void:
	_prev.pressed.connect(_on_prev)
	_next.pressed.connect(_on_next)
	_back.pressed.connect(_on_back)
	_toc.item_selected.connect(_on_toc_selected)
	_load_data()
	_show_chapter(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		_on_back()


## 章节数量（供测试与调试）。
func chapter_count() -> int:
	return _chapters.size()


func current_chapter_title() -> String:
	if _chapters.is_empty() or _index < 0 or _index >= _chapters.size():
		return ""
	return str((_chapters[_index] as Dictionary).get("title", ""))


## 读取数据文件并填充目录。
func _load_data() -> void:
	_chapters = []
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
	for c in (parsed as Dictionary).get("chapters", []):
		_chapters.append(c)
		_toc.add_item(str((c as Dictionary).get("title", "")))
	_update_buttons()


## 渲染第 i 章（章标题 + 章首引导语 + 各小节）。
func _show_chapter(i: int) -> void:
	if _chapters.is_empty():
		return
	_index = clampi(i, 0, _chapters.size() - 1)
	var ch: Dictionary = _chapters[_index]

	var out := "[font_size=32][b]%s[/b][/font_size]\n\n" % str(ch.get("title", ""))
	var intro := str(ch.get("intro", ""))
	if not intro.is_empty():
		out += intro + "\n\n"
	for sec in ch.get("sections", []) as Array:
		var s: Dictionary = sec
		out += "[font_size=28][b]%s[/b][/font_size]\n\n" % str(s.get("heading", ""))
		out += str(s.get("body", "")) + "\n\n"

	_content.clear()
	_content.append_text(out.strip_edges())
	_toc.select(_index)
	_update_buttons()
	# 等一帧让新内容完成布局，再回到顶部
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 0


func _update_buttons() -> void:
	_prev.disabled = _index <= 0
	_next.disabled = _index >= _chapters.size() - 1


func _on_toc_selected(i: int) -> void:
	_show_chapter(i)


func _on_prev() -> void:
	_show_chapter(_index - 1)


func _on_next() -> void:
	_show_chapter(_index + 1)


func _on_back() -> void:
	emit_signal("closed")
