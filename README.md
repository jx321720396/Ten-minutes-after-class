# 下课十分钟 · Ten Minutes After Class

> 一个学期，三十天，九十次课间——你不改变班级，班级自己改变自己。

以 **涌现（Emergence）** 为主题的高中课间社交模拟游戏。玩家是班级 17 个社交节点之一，在一个学期（30 个上学日）里通过搭话、递纸条、调侃、安慰、举报等行为，扰动一个**自运行**的班级社交系统；小团体、孤立、阵营对立、崩溃后的关系重塑，全部由底层规则自发涌现，没有预设剧情、没有固定结局。

- **引擎**：Godot 4.6（Mobile 渲染器，1920×1080，横屏）
- **语言**：GDScript
- **平台目标**：Windows / Android（TapTap 渠道）
- **当前阶段**：里程碑 M0 — 仓库与框架搭建（骨架已可打开，玩法系统待实现）

---

## 快速开始

1. 安装 **Godot 4.6**（标准版，非 .NET）。
2. 打开 Godot → `Import` → 选择本目录的 `project.godot`。
3. 按 `F5` 运行，入口是 `scenes/ui/main_menu.tscn`（主菜单 → 新游戏/继续/设置/关于）。

导出与构建配置见 `docs/production/比赛提交清单.md`。

---

## 目录结构

```
.
├─ project.godot            Godot 项目定义（勿手改，用编辑器）
├─ assets/                  美术 / 音频 / 字体等原始资源
│   ├─ icons/               图标
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
└─ .github/                 Issue / PR 模板与 CI
```

完整目录约定见 `docs/design/架构总览.md`。

---

## 文档导航

| 文档 | 说明 |
|---|---|
| [`docs/README.md`](docs/README.md) | **文档总索引**（从这里进入） |
| [`docs/gdd/core-gameplay-v3.0.md`](docs/gdd/core-gameplay-v3.0.md) | **玩法权威规格 v3.0**（唯一生效版本，冲突以它为准） |
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

摘自 v3.0，任何实现与评审都必须遵守：

1. **禁止脚本化**：把涌现部分换成脚本，游戏必须不成立（检验一）。
2. **四层分离**：性格 / 身份 / 行为 / 标签分层；**禁止在运行期出现角色名或角色 ID 判断**。
3. **观察层只读**：O1 簇标签器与"孤立"标签只输出给可视化与简报，不回写任何数值。
4. **假信息必须有破绽**：推理板中的矛盾必须可交叉验证。

## 许可

本项目为参赛作品，版权保留所有权利，详见 [`LICENSE`](LICENSE)。
