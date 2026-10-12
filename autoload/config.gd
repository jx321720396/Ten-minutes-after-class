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


## 本局人数（NPC 数）：取 data/rules/roster.csv 的 npc_count（数值不落脚本）。
## 供 main_menu（「新游戏」）与 classroom_actors（单场景调试的演示局）共用。
## 2026-10-12：删除难度档概念 —— 一局固定 16 名 NPC（+ 玩家 = 17 个节点）。
func default_npc_count() -> int:
	for row in get_table("rules/roster").get("rows", []):
		if str(row.get("key", "")) == "npc_count":
			var value := int(str(row["value"]))
			if value > 0:
				return value
			push_error("Config：rules/roster.csv 的 npc_count 必须为正整数（当前 %d）。" % value)
			break
	# 兜底：按角色池人数开局，并明确告警（不静默用默认值）
	var pool: Array = get_table("characters/seeds").get("rows", [])
	push_warning("Config：rules/roster.csv 读不到 npc_count，按角色池人数 %d 开局。" % pool.size())
	return pool.size()


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
