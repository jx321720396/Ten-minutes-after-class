class_name TermArchive
extends RefCounted
## 仅保存结束后的报告；不冒充完整游戏存档。

const PATH := "user://last_term_report.dat"
const VERSION := 1


static func write(record: Dictionary, path: String = PATH) -> Error:
	if not valid(record):
		return ERR_INVALID_DATA
	var file := FileAccess.open(path + ".new", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var({"version": VERSION, "report": record})
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(path + ".new", path)


static func read(path: String = PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var payload: Variant = file.get_var(false)
	if not payload is Dictionary or int(payload.get("version", 0)) != VERSION:
		return {}
	var record: Variant = payload.get("report", {})
	return record if record is Dictionary and valid(record) else {}


static func valid(record: Dictionary) -> bool:
	var count := int(record.get("count", 0))
	if not bool(record.get("finished", false)) or count < 2:
		return false
	# 老师版删除信任轴：baseline 只含好感／敌对两份矩阵。
	if record.get("names", []).size() != count or record.get("baseline", []).size() != 2:
		return false
	for matrix in record.baseline:
		if matrix.size() != count * count:
			return false
	return record.get("frames") is Array and record.get("actions") is Dictionary
