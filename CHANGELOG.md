# 变更记录

本文件记录本项目的所有重要变更，格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

分类：`新增` / `变更` / `修复` / `移除` / `文档` / `平衡`（数值调整专列，便于回溯标定）。

---

## [未发布]

### 变更
- **玩法规格事实源迁移至 Notion**：仓库不再维护玩法正文，`docs/gdd/` 改为规格入口（登记工程契约 + 编号锚点）。
- `docs/gdd/core-gameplay-v3.0.md` 降级为**编号锚点快照**并移至 `docs/references/core-gameplay-v3.0-20261003.md`（文件头已标注"非事实源"）。
- 术语表由 `docs/gdd/术语表.md` 移至 `docs/design/术语表.md`（属工程标识符约定）。
- 全仓约 30 处规格引用改为统一指向 `docs/gdd/README.md`（单一入口，后续更换 Notion 链接只需改一处）。

### 文档
- 建立 `docs/` 文档体系：文档索引、GDD 入口与契约登记、技术设计、制作管理、视听规范、测试策略、本地化说明、历史资料归档。
- 归档 v1.0 / v2.0 策划资料至 `docs/references/`，v3.0 玩法规格快照归档至 `docs/references/core-gameplay-v3.0-20261003.md`。
- 补齐仓库级文档：`README.md`、`CONTRIBUTING.md`、`AGENTS.md`、`LICENSE`。

### 新增
- 建立工程目录约定：`autoload/`、`data/`、`tests/`、`shaders/`、`assets/{audio,fonts}`。
- 增加 `.github/` 协作规范：Issue 模板、PR 模板、CI 结构校验工作流。
- 增强 `.gitignore` / `.editorconfig` / `.gitattributes`（Godot 4 导出产物、Reasonix 本地配置、GDScript 缩进与换行规范化）。

---

## [0.1.0] - 2026-10-03

### 新增
- Godot 4.6 项目骨架：主菜单流（新游戏 / 继续 / 设置 / 关于 / 确认弹窗 / 暂停菜单）。
- 线索板（推理板）交互原型：`scenes/game/clue_board_1.tscn` + `scripts/game/clue_board_1.gd`（粉笔绘制、板擦、调色板、标记拖拽）。

### 文档
- 《下课十分钟》游戏玩法文档 **v3.0** 定稿：一局 = 一学期 30 天、每天 3 段课间 + 2 段上课发酵、非线性影响力传导（阈值 + 竞争归一化 + tanh 饱和）、四层人物分离、推理板矛盾高亮闭环。
