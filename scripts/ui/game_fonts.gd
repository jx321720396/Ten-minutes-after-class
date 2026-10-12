extends RefCounted
## 游戏统一使用随包发布的字体；不依赖玩家设备的系统字体。
##
## 这是**脚本侧**的唯一字体入口（动态创建的 UI 都走这里）。
## 项目级默认字体见 `resources/ui/game_theme.tres`（`project.godot` 的 [gui] theme/custom）。
## 换字体时两处都要改：本文件 + 那个主题资源。

const REGULAR := preload("res://assets/fonts/misans/MiSans-Regular.ttf")
const DEMIBOLD := preload("res://assets/fonts/misans/MiSans-Demibold.ttf")


static func regular() -> Font:
	return REGULAR


## 需要强调时用（比 regular 重一档，避免用合成加粗）
static func demibold() -> Font:
	return DEMIBOLD
