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
