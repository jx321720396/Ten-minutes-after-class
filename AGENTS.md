# AGENTS.md

给 AI 编码助手（Reasonix / Claude / Copilot 等）的项目须知。人类协作者请看 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 项目一句话

Godot 4.6 + GDScript 的社交涌现模拟游戏《下课十分钟》：玩家是班级节点之一——24 人 NPC 角色池按难度随机抽取 8/16/24 人，玩家另算（本局 9/17/25 个节点），一局 = 30 天学期，每天 3 段课间操作 + 2 段上课发酵，班级格局从底层规则自发涌现。

## 权威信息源（按优先级）

1. [`docs/gdd/core-gameplay-v3.1.md`](docs/gdd/core-gameplay-v3.1.md) —— **玩法唯一事实源（主文档）**。回答玩法问题前必须先读它，不要凭常识推断；规格变更直接改这份文档并在 `CHANGELOG.md` 记录。
2. `docs/design/架构总览.md` —— 工程结构与模块边界。
3. `docs/production/路线图.md` —— 当前里程碑与优先级，决定"现在该做什么"。

## 硬性约束（违反即为错误实现）

1. **禁止角色名 / 角色 ID 判断**：行为逻辑必须是 `f(性格四维, 透明度, 当前状态)` 的纯函数（主文档 §11.1）。角色差异只能来自 `data/` 的开局种子。
2. **观察层只读**：簇标签器与"孤立"标签不得回写任何矩阵（主文档 §10 观察层）。
3. **不引入脚本化剧情**：不得写"第 N 天必然发生 X"。
4. **数值集中**：任何增量、阈值、系数放 `data/`（配置表），不得散落在脚本里的魔法数字。
5. **不碰的文件**：`.godot/`（引擎缓存）、`project.godot` 手改需谨慎、`resources/*.tres` 用编辑器改。

## 目录约定

- 场景 `scenes/{ui,game,components}/`，脚本 `scripts/{ui,game,core,npc,systems}/` —— **脚本目录与场景目录同构**。
- 全局单例放 `autoload/` 并在 `project.godot` 注册；配置与数值表放 `data/`。
- 测试放 `tests/`（GUT 或 gdUnit4，见 `docs/qa/测试策略.md`）。

## 常用命令

```bash
# 打开项目（需已安装 Godot 4.6）
godot --path . --editor

# 无头运行（CI/校验）
godot --headless --path . --quit

# GDScript 格式与静态检查
pip install gdtoolkit==4.*
gdformat --check scripts/ && gdlint scripts/
```

## 提交与 PR

- 提交信息：`<类型>(<范围>): <描述>`，类型见 `CONTRIBUTING.md`。
- 改动必须同步更新受影响的 `docs/` 与 `CHANGELOG.md`。
- 涉及玩法逻辑时，PR 描述需说明"检验一（换成脚本还成立吗）"如何通过。

## 当前状态

仓库处于 M0（框架搭建）：主菜单流与线索板原型可用，`autoload/`、`data/`、`tests/` 为待实现目录。实现顺序以 主文档 §16 开发优先级与 `docs/production/路线图.md` 为准（第一版：时间系统 → 态度矩阵 → 压力 → 人物行为（闲聊/搭话/调侃/安慰）+ 簇标签 → 可视化 → 简报）。
