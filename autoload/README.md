# autoload/ —— 全局单例

> 状态：骨架 ｜ 维护者：程序 ｜ 最后更新：2026-10-04
> 规划依据：[`../docs/design/架构总览.md`](../docs/design/架构总览.md) 第 2、3 节

本目录存放注册到 `project.godot` 的全局单例。**单例只做"持有与转发"，不承载玩法规则**——规则属于 `scripts/systems/`。

## 规划中的单例

| 文件 | 职责 | 状态 |
|---|---|---|
| `game_state.gd` | 当前局状态持有、推进入口（开始/推进/结束一局） | ⬜ 待实现（M1） |
| `event_bus.gd` | 全局信号总线：模拟内核 → 表现层的唯一通道 | ⬜ 待实现（M1） |
| `config_loader.gd` | 读取并校验 `data/` 下的配置表（缺列/越界即报错） | ⬜ 待实现（M1） |
| `save_manager.gd` | 存档：单日结算点写入 `user://savegame.dat`，含版本号 | ⬜ 待实现（M1，主菜单"继续"已预留入口） |

## 约定

- **注册方式**：在 Godot 编辑器 `项目设置 → 自动加载` 中注册，名称与文件名一致（`GameState`、`EventBus` 等）。
- **依赖方向**：`autoload/` 可依赖 `scripts/core/`、`scripts/systems/`；**反向依赖禁止**（内核不得引用单例），以保证内核可在无头环境独立运行。
- **不得存放**：规则实现、数值常量、UI 逻辑。
- **信号命名**：过去式（`day_settled`、`stress_burst`、`cluster_changed`），载荷用字典或专用资源类，便于日志复用。

## 现有进度提示

主菜单 `scripts/ui/main_menu.gd` 目前用 `user://savegame.dat` 的 `FileAccess.file_exists()` 判断"继续"按钮可用性；接入 `save_manager.gd` 后应改为读取存档元数据（版本号 + 天数），不要依赖文件存在与否。
