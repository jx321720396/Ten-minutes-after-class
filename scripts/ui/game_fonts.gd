extends RefCounted
## 游戏统一使用随包发布的 OFL 字体；不依赖玩家设备的系统字体。

const REGULAR := preload("res://assets/fonts/lxgw-wenkai/LXGWWenKai-Regular.ttf")


static func regular() -> Font:
	return REGULAR
