extends Node
## Config 单例：持有 ConfigLoader 解析出的全部配置表（§4.4「持有与转发」）。
##
## 规则解析在 scripts/core/config_loader.gd（RefCounted，可无头单测）；
## 本类只缓存并转发查询，不承载玩法规则。首次访问时惰性加载。

var _tables: Dictionary = {}


## 取单张表；缺失返回空字典（表名如 "rules/behaviors"）。
func get_table(name: String) -> Dictionary:
	if _tables.is_empty():
		_load()
	return _tables.get(name, {})


## 新游戏默认难度：取 data/rules/difficulty.csv 中标了 default=1 的档（数值不落脚本）。
## 供 main_menu（「新游戏」）与 classroom_actors（单场景调试的演示局）共用。
func default_difficulty() -> int:
	var rows: Array = get_table("rules/difficulty").get("rows", [])
	for row in rows:
		if str(row.get("default", "0")) == "1":
			return int(str(row["difficulty"]))
	push_warning("difficulty.csv 里没有 default=1 的档，回退难度 1")
	return 1


## 全部配置表 {表名: 表}。
func tables() -> Dictionary:
	if _tables.is_empty():
		_load()
	return _tables


## 重新读取 data/（开发期热更用）。
func reload() -> void:
	_load()


func _load() -> void:
	_tables = ConfigLoader.new().load_all()
