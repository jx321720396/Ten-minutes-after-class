extends Node
## 哨兵夹具：**故意违反**铁律 2（观察层只读）。
## 簇标签器绝不能回写关系矩阵，这里故意写回一次，用来验证静态扫描能抓到。
## 语法合法，Godot 能正常解析。

var A: Array = []


func update(viewer: int) -> void:
	var n := 9
	for j in range(n):
		A[viewer][j] = 50.0
