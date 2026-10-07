class_name ConfigLoader
extends RefCounted
## 配置加载器：读 data/**/*.csv（主文档 §18、data/README.md）。
##
## 约定（data/README.md）：
## - UTF-8 无 BOM；首行为表头（snake_case 英文）；注释行以 # 开头（跳过）。
## - 布尔 0/1；多值列用 | 分隔（本类不拆分，原样保留字符串）。
## 本类只负责「读」与「解析」，数值范围 / 行数校验由 tools/check_config.py 离线执行。
## 解析结果与 Python 参考 core_sim.load_table 对齐：行值一律为字符串，列名字典化。

const DATA_ROOT := "res://data"

var _tables: Dictionary = {}


## 递归扫描 res://data/ 下所有 .csv 并解析，返回 {表名: 表}。
## 表名 = 相对 data/ 的路径（去 .csv），如 "rules/behaviors"。
func load_all() -> Dictionary:
	_tables = {}
	var files: Array[String] = []
	_collect_csvs(DATA_ROOT, files)
	for path in files:
		var name := _table_name(path)
		_tables[name] = _load_table(path, name)
	return _tables


## 取单张表（未加载则先 load_all）；缺失返回空字典并打印可读错误。
func get_table(name: String) -> Dictionary:
	if _tables.is_empty():
		load_all()
	if _tables.has(name):
		return _tables[name]
	push_error("ConfigLoader: 表缺失 %s（期望 %s）" % [name, DATA_ROOT.path_join(name) + ".csv"])
	return {}


func _collect_csvs(dir_path: String, result: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect_csvs(dir_path.path_join(sub), result)
	for file in dir.get_files():
		if file.ends_with(".csv"):
			result.append(dir_path.path_join(file))


func _table_name(path: String) -> String:
	return path.trim_prefix(DATA_ROOT + "/").trim_suffix(".csv")


func _load_table(path: String, name: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ConfigLoader: 表缺失 %s（%s）" % [name, path])
		return {}
	var headers: Array[String] = []
	var rows: Array[Dictionary] = []
	for line in FileAccess.get_file_as_string(path).replace("\r", "").split("\n"):
		if line.strip_edges().is_empty() or line.strip_edges().begins_with("#"):
			continue
		var fields := _parse_line(line)
		if headers.is_empty():
			headers = fields
			continue
		var row: Dictionary = {}
		for idx in headers.size():
			var value := ""
			if idx < fields.size():
				value = fields[idx]
			row[headers[idx]] = value
		rows.append(row)
	return {"name": name, "path": path, "headers": headers, "rows": rows}


## 解析一行 CSV 为字段数组；支持 "..." 引号包裹与 "" 转义。
func _parse_line(line: String) -> Array[String]:
	var fields: Array[String] = []
	var current := ""
	var in_quotes := false
	var idx := 0
	while idx < line.length():
		var ch := line[idx]
		if in_quotes:
			if ch == '"' and idx + 1 < line.length() and line[idx + 1] == '"':
				current += '"'
				idx += 1
			elif ch == '"':
				in_quotes = false
			else:
				current += ch
		else:
			if ch == '"':
				in_quotes = true
			elif ch == ",":
				fields.append(current)
				current = ""
			else:
				current += ch
		idx += 1
	fields.append(current)
	return fields
