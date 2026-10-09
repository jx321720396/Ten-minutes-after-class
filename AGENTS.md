# AGENTS.md

给 AI 编码助手（Reasonix / Claude / Copilot 等）的项目须知。人类协作者请看 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 项目一句话

Godot 4.7.2 + GDScript 的社交涌现模拟游戏《下课十分钟》：玩家是班级节点之一——24 人 NPC 角色池按难度随机抽取 8/16/24 人，玩家另算（本局 9/17/25 个节点），一局 = 30 天学期，每天 3 段课间操作 + 2 段上课发酵，班级格局从底层规则自发涌现。

> **引擎定稿（2026-10-06）**：Godot 4.7.2（GDScript）；规格与数值资产不变。详见 `docs/production/聚光灯21天冲刺计划.md` §0。

## 权威信息源（按优先级）

1. [`docs/gdd/core-gameplay-v3.1.md`](docs/gdd/core-gameplay-v3.1.md) —— **玩法唯一事实源（主文档）**。回答玩法问题前必须先读它，不要凭常识推断；规格变更直接改这份文档并在 `CHANGELOG.md` 记录。
2. `docs/design/架构总览.md` —— 工程结构与模块边界。
3. `docs/production/路线图.md` —— 当前里程碑与优先级，决定"现在该做什么"。

## 硬性约束（违反即为错误实现）

1. **禁止角色名 / 角色 ID 判断**：行为逻辑必须是 `f(性格四维, 透明度, 当前状态)` 的纯函数（主文档 §9.11）。角色差异只能来自 `data/` 的开局种子。
2. **观察层只读**：簇标签器与"孤立"标签不得回写任何矩阵（主文档 §8 观察层）。
3. **不引入脚本化剧情**：不得写"第 N 天必然发生 X"。
4. **数值集中**：任何增量、阈值、系数放 `data/`（配置表），不得散落在脚本里的魔法数字。
5. **不碰的文件**：`.godot/`（引擎缓存）、`project.godot` 手改需谨慎、`resources/*.tres` 用编辑器改。
6. **内核纯净**：`scripts/core/` 不得引用 UI 与表现层节点类型；随机数一律用带种子的 `RandomNumberGenerator`（禁用全局 `randi()` 之类的隐式随机，保可复现性，主文档 §14.7）。

## 目录约定

- 场景 `scenes/{ui,game,components}/`，脚本 `scripts/{ui,game,core,npc,systems}/` —— **脚本目录与场景目录同构**。
- 全局单例放 `autoload/` 并在 `project.godot` 注册；配置与数值表放 `data/`（代码只读）。
- 3D 等外部资产放 `assets/models/<名称>/`（见 [`assets/README.md`](assets/README.md)）；离线标定工具在 `tools/`（Python）。
- 测试放 `tests/`（GUT 或 gdUnit4，见 `docs/qa/测试策略.md`）。

## 常用命令

```bash
# 打开项目（需已安装 Godot 4.7.2）
godot --path . --editor

# 无头运行 / 导入资产（CI/校验）
godot --headless --path . --quit
godot --headless --path . --import

# GDScript 格式与静态检查
pip install gdtoolkit==4.*
gdformat --check scripts/ && gdlint scripts/

# 离线六道门（Python，与引擎无关）
python tools/check_config.py && python tools/test_core.py && python tools/verify_formula.py

# 一键跑测试（六道门 + 铁律 tests/invariants/ + Godot 侧 GUT；Godot 路径配置见 tools/README.md）
bash tools/run_tests.sh
bash tools/run_tests.sh --godot "<Godot 可执行文件完整路径>"   # 本机 Godot 不在 PATH 时
bash tools/run_tests.sh --no-godot                            # 只跑离线部分
```

GDScript 约定：矩阵访问一律走 `Affinity(i,j)` 等访问器；风格与命名见 `CONTRIBUTING.md`。

## 提交与 PR

- 提交信息：`<类型>(<范围>): <描述>`，类型见 `CONTRIBUTING.md`。
- **`main` 允许直接推送**（小团队主干开发，2026-10-08 起）：推送前必须 `bash tools/run_tests.sh --no-godot` 全绿，并先跑 `gdformat scripts/` + `gdlint scripts/` —— **红灯不推**。跨模块大改或需要他人复看的改动仍推荐走 PR（`CONTRIBUTING.md` §8）。
- **规格变更**必须同批更新受影响的 `docs/` 与 `CHANGELOG.md`；其余改动在同一批推送内补记即可，不要求每个提交都写条目。
- 涉及玩法逻辑的改动，说明"检验一（换成脚本还成立吗）"如何通过。

## 当前状态

M1（核心循环跑通）进行中，参赛冲刺模式：**2026 聚光灯创作挑战（主题「涌现」），10/18 提交**。Python 内核与标定已完成（六道门全绿），Godot 工程推进中（教室 3D 场景已导入 `assets/models/classroom/`）。执行顺序以 `docs/production/聚光灯21天冲刺计划.md` 倒排日历为准；规格顺序以主文档 §13 与 `docs/production/路线图.md` 为准（第一版：时间系统 → 态度矩阵 → 压力 → 人物行为（闲聊/搭话/调侃/安慰）+ 簇标签 → 可视化 → 简报）。

## 提交前的六道门（全部必须通过；用 `&&` 串起，勿用 `;`）

```bash
python tools/check_config.py     &&   # 配置校验（含阈值键存在性）
python tools/test_core.py        &&   # 内核单测
python tools/verify_formula.py   &&   # 公式对拍
python tools/check_metrics.py    &&   # 玩法指标（**多种子分布判据**，不看单局）
python tools/diversity_report.py &&   # 多样性与存在性（机制上场率 / 跨局指纹 / 吸收态）
python tools/check_docs.py            # 文档一致性（未实现标记 / 参数值 / 引用 / 陈旧表述）
```

> GDScript 侧对应门：GUT / gdUnit4 单测 + 同种子对拍（Python vs GDScript 关键指标误差 ≤ 1%）。
