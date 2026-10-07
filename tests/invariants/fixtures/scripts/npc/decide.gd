extends Node
## 哨兵夹具：**故意违反**铁律 3（数值不落在脚本里）。
## 下面这些数值本该放进 data/ 配置表，写成字面量就是违规。
## 语法合法，Godot 能正常解析。

const SPEED := 3.5


func score(x: float) -> float:
	return x * 1.4 + 12.0
