# 下课十分钟 · Ten Minutes After Class

> 七天后的周考，正在变化的班级——你的干预只有有限的时间。

以 **涌现（Emergence）** 为主题的高中班级管理模拟游戏。玩家扮演实习老师／班主任，通过监控、私聊、巡视、调座位和鼓励交流，兼顾 **16 名学生**的平均成绩与关系安全。压力、动力、今日学业收益分别运行；学生公开被动提供差异，班级关系由局部互动形成。保留 30 天学期，每天三个课间、两个上课段，第七天首次周考。

> **2026-10-14 状态**：老师版策划已更新，现有可运行工程仍为学生版，老师版尚未实现。当前规则以 [主策划案](docs/gdd/core-gameplay-v3.1.md) 为准；旧运行时与标定记录不能视为老师版验收。

- **引擎**：Godot 4.7.2（Mobile 渲染器，1920×1080，横屏）
- **语言**：GDScript
- **平台目标**：Windows / Android（TapTap 渠道）
- **当前阶段**：老师版策划收敛与 M1 迁移准备；当前制作移动端，移动端验收在 `main-mobile`，通用更新按 `main → main-mobile` 同步。赛事目标日仍为 10/18，尚未据新范围承诺交付进度。

---

## 快速开始

1. 安装 **Godot 4.7.2**（标准版，非 .NET）。
2. 打开 Godot → `Import` → 选择本目录的 `project.godot`。
3. 按 `F5` 运行，入口是 `scenes/ui/main_menu.tscn`（主菜单 → 新游戏/继续/设置/关于）。
4. 跑测试（**不需要 Godot**）：`bash tools/run_tests.sh` —— 离线六道门 + 铁律测试
   （`tests/invariants/`）；装了 Godot 时加跑 GUT 单测，用 `--godot "<Godot 可执行文件完整路径>"` 指定即可，
   详见 [`tools/README.md`](tools/README.md)。

导出与构建配置见 `docs/production/比赛提交清单.md`。

---

## 目录结构

```
.
├─ project.godot            Godot 项目定义（勿手改，用编辑器）
├─ assets/                  美术 / 音频 / 字体等原始资源
│   ├─ icons/               图标
│   ├─ models/              3D 模型（classroom/ 教室场景，见 assets/README.md）
│   ├─ textures/            贴图（clueboard/ 线索板素材）
│   ├─ audio/               音频（bgm/ sfx/，见 assets/README.md）
│   └─ fonts/               字体
├─ autoload/                全局单例（游戏状态、事件总线、存档、配置）
├─ data/                    配置表与数值（角色种子、规则参数、平衡数值）
├─ docs/                    策划、设计、制作、规范文档（见 docs/README.md）
├─ resources/               Godot 资源（.tres：样式盒、主题、曲线）
├─ scenes/                  场景
│   ├─ ui/                  菜单与界面
│   └─ game/                玩法场景（clue_board_1 线索板原型）
├─ scripts/                 脚本（与 scenes/ 同构：ui/ game/ core/ npc/ systems/）
├─ shaders/                 着色器
├─ tests/                   测试（GUT / gdUnit4）
├─ tools/                   离线标定与校验工具（Python：内核、六道门、参数扫描）
└─ .github/                 Issue / PR 模板
```

完整目录约定见 `docs/design/架构总览.md`。

---

## 文档导航

| 文档 | 说明 |
|---|---|
| [`docs/README.md`](docs/README.md) | **文档总索引**（从这里进入） |
| [`docs/gdd/core-gameplay-v3.1.md`](docs/gdd/core-gameplay-v3.1.md) | **老师版主策划案（唯一事实源）**，2026-10-14 修订；文件名保留旧路径 |
| `docs/gdd/` | 玩法设计文档体系与章节映射 |
| `docs/design/` | 技术设计：架构、数据模型、规则引擎 |
| `docs/production/` | 路线图、里程碑、比赛提交清单 |
| `docs/art/` `docs/audio/` | 视觉与音频规范 |
| `docs/qa/` | 测试策略与验收清单 |
| `docs/references/` | 历史资料归档（v1.0 / v2.0 策划案原始 docx） |

---

## 协作

- 贡献流程、分支与提交规范、GDScript 风格、资源规范：**[`CONTRIBUTING.md`](CONTRIBUTING.md)**
- 给 AI 编码助手的项目须知：**[`AGENTS.md`](AGENTS.md)**
- 变更记录：**[`CHANGELOG.md`](CHANGELOG.md)**

## 设计铁律（摘要）

以当前主策划案为准，任何实现与评审都必须遵守：

1. **禁止脚本化**：把涌现部分换成脚本，游戏必须不成立（检验一）。
2. **公开、数据驱动的差异**：专属被动来自配置，**禁止在运行期按角色名或固定 ID 实现特殊效果**。
3. **观察层只读**：簇标签器与"孤立"标签只输出给可视化与简报，不回写任何数值。
4. **反馈清楚**：压力、动力、今日学业收益分开显示；具体事件和风险都有依据，未知关系不能当作中立。

## 许可

本项目为参赛作品，版权保留所有权利，详见 [`LICENSE`](LICENSE)。
