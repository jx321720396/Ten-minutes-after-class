# autoload/ —— 全局单例

> 状态：骨架 ｜ 维护者：程序 ｜ 最后更新：2026-10-06
> 规划依据：[`../docs/design/架构总览.md`](../docs/design/架构总览.md) 第 2、3 节

本目录存放注册到 `project.godot` 的全局单例。**单例只做"持有与转发"，不承载玩法规则**——规则属于 `scripts/systems/`。

## 已注册单例

| 文件 | 单例名 | 职责 | 状态 |
|---|---|---|---|
| `event_bus.gd` | `EventBus` | 全局信号总线：模拟内核 → 表现层的唯一通道（§4.1 四个信号） | ✅ 已实现 |
| `config.gd` | `Config` | 持有 `scripts/core/config_loader.gd` 解析出的配置表并转发查询 | ✅ 已实现 |
| `save.gd` | `Save` | 存档读写（含版本号字段），默认 `user://savegame.dat` | ✅ 已实现 |
| `game_state.gd` | `GameState` | 当前局状态持有（seed/difficulty/day/phase + SimCore 槽） | ✅ 已实现（SimCore D8 落地） |

## 约定

- **注册方式**：在 `project.godot` 的 `[autoload]` 段注册，单例名与文件名一致（`EventBus`、`Config`、`Save`、`GameState`）。
- **依赖方向**：`autoload/` 可依赖 `scripts/core/`、`scripts/systems/`；**反向依赖禁止**（内核不得引用单例），以保证内核可在无头环境独立运行。
- **不得存放**：规则实现、数值常量、UI 逻辑。
- **信号命名**：过去式（`day_settled`、`stress_burst`、`event_happened`、`tag_changed`），载荷用字典或基础类型，便于日志复用。

## 说明

- 配置解析已下沉到 `scripts/core/config_loader.gd`（`class_name ConfigLoader`，RefCounted、可无头单测）；autoload `Config` 只做缓存与转发。
- 主菜单「继续」已接入 `Save.has_save()`（不再直接用 `FileAccess.file_exists`）。
- 存档格式含 `version` 字段（`Save.SAVE_VERSION`），D13 晚冻结格式细节。
