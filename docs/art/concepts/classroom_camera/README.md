# 教室默认镜头调整（2026-10-12）

参照教室概念图，将默认镜头从高处俯瞰调整为室内取景。相机位置 `[0, 3.35, 9.5]`，看向 `[0, 0, -0.3]`，透视视野 36 度，参数集中在 `data/ui/classroom_art.json` 的 `camera` 项，由 `ClassroomArt` 初始化应用。

隐藏前景矮墙的表现节点 `Room/FrontWall`，保留 `NavGeometry/WallShapes/FrontWallShape`，不改变房间边界、通道、席位或内核。画面上沿由后墙与侧墙填满，避免露出墙顶外空白。

- `before.png`：之前的默认镜头。
- `after.png`：调整后的实机画面，隐藏界面供美术检查。
- `after_hud.png`：带当前游戏界面的画面；原有右侧动作面板仍遮挡部分窗边人物，此次没有调整界面布局。

Godot 4.7.2 实际入口场景、种子 20261011、难度 2，共 17 个角色。教室回归 6 项测试、75 个断言全部通过；修改脚本格式与静态检查通过。截图通过 `tools/capture_classroom_art.gd` 生成。
