extends RefCounted
## 纯展示时序：自动展开分镜，翻页始终需要玩家点击。

var page := 0
var revealed := 0
var finished := true
var _pages := 0
var _panels := 0
var _interval := 0.0
var _elapsed := 0.0


func start(pages: int, panels: int, interval: float) -> void:
	_pages = pages
	_panels = panels
	_interval = interval
	page = 0
	revealed = 1
	_elapsed = 0.0
	finished = pages <= 0 or panels <= 0 or interval <= 0.0


func advance_time(delta: float) -> void:
	if finished or revealed >= _panels:
		return
	_elapsed += delta
	while _elapsed >= _interval and revealed < _panels:
		_elapsed -= _interval
		revealed += 1


func tap() -> void:
	if finished:
		return
	if revealed < _panels:
		revealed += 1
		_elapsed = 0.0
	elif page + 1 < _pages:
		page += 1
		revealed = 1
		_elapsed = 0.0
	else:
		finished = true


func skip() -> void:
	finished = true
