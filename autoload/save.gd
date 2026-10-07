extends Node
## Save 单例：存档读写（§4.1），格式含版本号字段（D13 晚冻结）。
##
## 只持久化一个带版本号的字典，不关心内容语义（玩法由内核决定）；
## 默认写到 user://savegame.dat，单日结算点写入（架构总览 §4）。
## 方法名避开原生名：read / read_meta（不用 load / get_meta）。

const DEFAULT_PATH := "user://savegame.dat"
const SAVE_VERSION := 1


## 写入存档：{version, saved_at, data}。
func save(data: Dictionary, path: String = DEFAULT_PATH) -> void:
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"data": data,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Save: 无法写入 %s" % path)
		return
	f.store_string(JSON.stringify(payload))


## 读取存档；文件缺失或损坏返回空字典。
func read(path: String = DEFAULT_PATH) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return {}
	return parsed


## 是否存在存档。
func has_save(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


## 读取存档元数据（版本号 + 天数），供主菜单「继续」判断与显示。
func read_meta(path: String = DEFAULT_PATH) -> Dictionary:
	var payload := read(path)
	if payload.is_empty():
		return {}
	var data: Dictionary = payload.get("data", {})
	return {
		"version": int(payload.get("version", 0)),
		"day": int(data.get("day", 0)),
	}


## 删除存档。
func delete(path: String = DEFAULT_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
