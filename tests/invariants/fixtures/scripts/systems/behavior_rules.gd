extends Node
## 哨兵夹具：**故意违反**铁律 1（无角色名 / 角色 ID 判断）。
## 语法本身是合法的 —— Godot 能正常解析，不会污染引擎输出；违规的是它的**逻辑形态**。
## 注释里出现角色名（如「陈阳」）是允许的，扫描器只记 INFO，不算违规。

const CHAR_05 := 5

var char_id: int = 7
var actor_id: int = 1


func pick_target() -> void:
	if char_id == 7:
		print("陈阳")
	if actor_id in [1, 2, 3]:
		print("按角色编号分支")
	print(CHAR_05)
