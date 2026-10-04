# data/ —— 配置与数值表

> 状态：骨架 ｜ 维护者：策划 / 程序 ｜ 最后更新：2026-10-04
> 规划依据：[`../docs/design/数据模型.md`](../docs/design/数据模型.md) 第 2 节

**代码只读本目录，不得写死数值。** 任何增量、阈值、概率、系数都必须来自这里。

## 目录结构

```
data/
├─ characters/
│   └─ seeds.csv          24 角色种子表（对应 v3.0 §11.4）
├─ rules/
│   ├─ transmission.csv   传导参数：theta_A / theta_H / sigma / beta / epsilon（v3.0 §7.2）
│   ├─ decay.csv          跨天衰减系数（v3.0 §3.5）
│   └─ phases.csv         相位时长与规则启用子集（v3.0 §3.2、§3.3）
└─ balance/
    └─ w_events.csv       统一增量公式的事件权重全表（v3.0 §6.1）
```

（上述 CSV 为规划文件，M1 阶段创建。）

## CSV 约定

- 编码 **UTF-8 无 BOM**；首行为表头，列名用 `snake_case` 英文。
- 数值列不得为空；布尔用 `0/1`；多值列用 `|` 分隔（如 `tags_init`）。
- 注释行以 `#` 开头（加载器需跳过）。
- 每张表必须有对应的字段说明文档段落（见 `docs/design/数据模型.md`），新增列须同步更新。

## 字段速览

| 文件 | 关键字段 |
|---|---|
| `characters/seeds.csv` | `id`、`alias`、`archetype`、`mbti`、`e`、`n`、`f`、`p`、`opacity_init`、`identity_seed`、`tags_init`、`initial_relations` |
| `rules/transmission.csv` | `theta_a`、`theta_h`、`sigma`、`beta_affinity`、`beta_hostility`、`epsilon` |
| `rules/decay.csv` | `axis`、`no_interaction`、`interacted`、`note` |
| `rules/phases.csv` | `phase_id`、`tick_count`、`active_rules`、`player_controllable` |
| `balance/w_events.csv` | `event_id`、`axis`、`delta`、`delta_min`、`delta_max`、`note` |

## 校验要求

`config_loader.gd` 启动时校验并在失败时**明确报错（含文件名与行号）**，不得静默使用默认值：

- 必需列存在、行数符合预期（如角色表 24 行）；
- 数值范围合法（0–100 的轴、正数阈值）；
- `w_events.csv` 的每个 `event_id` 能对应到 v3.0 中的规则编号（`note` 列必须写明出处章节）。

## 权威性

数值的**出处**必须可追溯到 [`../docs/gdd/README.md`](../docs/gdd/README.md) 的具体章节或它的标定目标（§3.4）。标定后的调整走 `balance/` 前缀分支并在 `CHANGELOG.md` 的「平衡」分类中记录。
