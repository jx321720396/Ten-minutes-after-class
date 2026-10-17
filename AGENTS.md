# AGENTS.md

## 当前主要工作目录（2026-10-14，用户指定）

当前主要目标是移动端，优先在 **D:/game/下课十分钟-mobile** 工作，并在每次操作前确认分支为 main-mobile。当前聊天即使仍挂在旧项目目录，也应显式将命令工作目录指向本目录。移动端已有布局、触摸输入、导出配置与未提交改动必须保留；跨侧同步仍按 main → main-mobile，不反向合并，不删除 main-mobile。

给 AI 编码助手（Reasonix / Claude / Copilot 等）的项目须知。人类协作者请看 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 移动端适配分支

main-mobile 是移动端适配专用分支，禁止删除。所有移动端布局、触摸输入、屏幕方向和导出适配改动优先在此分支进行。

## 项目一句话

Godot 4.7.2 + GDScript 的社交涌现模拟游戏《下课十分钟》：玩家是实习老师／班主任，管理 **16 名学生，一局全池入局**；老师不进入学生关系矩阵。保留 30 天学期、每天 3 段课间 + 2 段上课，第七天首次周考。通过有限时间的干预兼顾平均成绩与关系安全，班级格局从学生局部互动涌现。

> **引擎定稿（2026-10-06）**：Godot 4.7.2（GDScript）。**2026-10-14 策划改为老师版，运行时仍是学生版，尚未迁移；旧参数与标定结果不得直接当作老师版规格。**

## 权威信息源（按优先级）

1. [`docs/gdd/core-gameplay-v3.1.md`](docs/gdd/core-gameplay-v3.1.md) —— **玩法唯一事实源（主文档）**。回答玩法问题前必须先读它，不要凭常识推断；规格变更直接改这份文档并在 `CHANGELOG.md` 记录。
2. `docs/design/架构总览.md` —— 工程结构与模块边界。
3. `docs/production/路线图.md` —— 当前里程碑与优先级，决定"现在该做什么"。

## 硬性约束（违反即为错误实现）

1. **禁止角色名 / 角色 ID 判断**：老师版行为逻辑依赖公开被动配置、当前状态、关系与环境（主文档 §13.1）。角色差异只能来自 `data/`；删除透明度、信任度与隐藏性格四维修正，专属被动不得写成按角色名分支。
2. **观察层只读**：簇标签器、"孤立"与风险标签不得回写任何矩阵（主文档 §9.3、§11）。
3. **不引入脚本化剧情**：不得写"第 N 天必然发生某人的冲突／孤立"。第七天周考等固定制度不属于剧情禁项。
4. **数值集中**：任何增量、阈值、系数放 `data/`（配置表），不得散落在脚本里的魔法数字。
5. **不碰的文件**：`.godot/`（引擎缓存）、`project.godot` 手改需谨慎、`resources/*.tres` 用编辑器改。
6. **内核纯净**：`scripts/core/` 不得引用 UI 与表现层节点类型；随机数一律用带种子的 `RandomNumberGenerator`（禁用全局 `randi()` 之类的隐式随机，保可复现性，主文档 §13.1）。

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
- **`main` 允许直接推送**（小团队主干开发，2026-10-08 起）：推送前跑**快门禁**（`check_config` / `test_core` / `verify_formula` / `check_docs`，秒级）+ `gdformat scripts/` + `gdlint scripts/`，**红灯不推** —— **仓库已移除 GitHub Actions（2026-10-09）**，没有 CI 兜底，全靠这一步。完整六道门（含多种子标定门，与 UI / 美术改动无关且有已知不达标项）需要时手动跑 `bash tools/run_tests.sh --no-godot`。跨模块大改或需要他人复看的改动仍推荐走 PR（`CONTRIBUTING.md` §8）。
- **规格变更**必须同批更新受影响的 `docs/` 与 `CHANGELOG.md`；其余改动在同一批推送内补记即可，不要求每个提交都写条目。
- 涉及玩法逻辑的改动，说明"检验一（换成脚本还成立吗）"如何通过。

## 当前状态

M1 进行中，参赛目标仍为 **2026 聚光灯创作挑战（主题「涌现」），10/18 提交**。2026-10-14 已更新老师版策划，代码与配置仍为学生版，旧门与旧标定不证明老师版通过。新规格与优先级见主文档 §14–§15 和 `docs/production/路线图.md`；旧冲刺日历保留为历史执行参考，尚未据新范围承诺交付日期。教室 3D 与人物素材可作为迁移候选；移动端方向与下述同步约定继续有效。

## 平台方向：制作移动端（2026-10-13 定规）

**当前阶段 = 制作移动端。** 执行约定：

1. **移动端分支 = `main-mobile`**（队友维护、可含移动端专属实现如导出预设、响应式布局）；移动端开发与验收在该分支上进行，不以 `main` 代替。
2. **同步方向固定为「`main` → `main-mobile`」**：`main` 上落定的通用更新（代码 / 数据 / 文档）按期并入 `main-mobile`；需要移动端与通用侧一起改的改动，先在 `main` 落定，再合并过去。
3. **有差异以移动端仓库为准**：合并时若两侧改了同一处，保留 `origin/main-mobile` 的版本（`git merge main` 冲突时取 `--ours`）；`main` 侧改动不得覆盖移动端已有实现。
4. 合并后在 `main-mobile` 上跑快门禁（`check_config` / `test_core` / `verify_formula` / `check_docs`）+ `gdformat` / `gdlint`，再推送；跨侧排查问题时先确认当前所在分支（`git status -sb`），避免"改在 main、测在 mobile"。

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

### 导出 APK 前：CSV 导入模式检查

```bash
python tools/check_export_imports.py   # data/**/*.csv 的 .import 必须全部是 importer="keep"
```

否则 Godot 的 `csv_translation` 导入器会接管 CSV，**原始 CSV 不进包**，安卓运行期读不到这些表
（2026-10-17 手机首次 tick 卡死即由此引起：老师版 11 张表缺失）。桌面端直接读源码目录不受影响，
所以**桌面上跑得通不代表导出包没问题**。`tools/run_tests.sh` 已包含这一步。
