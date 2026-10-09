# data/ —— 配置与数值表

> 状态：骨架 ｜ 维护者：策划 / 程序 ｜ 最后更新：2026-10-04
> 规划依据：[`../docs/design/数据模型.md`](../docs/design/数据模型.md) 第 2 节

**代码只读本目录，不得写死数值。** 任何增量、阈值、概率、系数都必须来自这里。

## 目录结构

```
data/
├─ characters/
│   ├─ seeds.csv          24 角色种子表（身份/标签 + E/N/F/P 四维）✓
│   ├─ bindings.csv       绑定组（情侣 / 全班统一初始关系）✓
│   └─ appearance.csv     外观呈现表（角色编号 → 立绘；表现层用，不参与行为判定）✓
├─ rules/
│   ├─ transmission.csv       传导与软饱和参数（theta_* / beta_* / u_* / settle_interval / epsilon）✓
│   ├─ belief.csv             信念矩阵更新参数（eta0_* / sigma_max_* / prior_* / lambda_b）✓
│   ├─ behavior_probs.csv     环境类行为每 tick 基础概率 ✓
│   ├─ behavior_thresholds.csv 阈值类行为触发条件（举报 / 爆发 / 道歉 / 安慰）✓
│   ├─ decay.csv              跨天衰减（有/无互动两档 + 压力保留 + 有互动门槛）✓
│   ├─ status_tags.csv        状态标签（心结 / 秘密同盟；参数外置，避免硬编码）✓
│   ├─ phases.csv             相位时长 + 规则启用子集 + 玩家操作权限 ✓
│   ├─ time_presentation.csv  相位显示名 + 实时标称时长 + 游戏内时长（时间组件）✓
│   ├─ time_runtime.csv       学期长度 term_days + 每帧 tick 预算（时间组件）✓
│   ├─ seats.csv              座位表（seat_id / row / col / kind；决定相邻关系）✓
│   ├─ stand_points.csv       站立点表（课间走动目标；世界坐标在场景 StandPoints/*）✓
│   ├─ difficulty.csv         难度档 → NPC 数量（+ `default` 列 = 新游戏默认档）✓
│   ├─ player_interaction.csv 玩家交互几何与线索参数（闲聊范围 / 连线步长 / 拾取层 / 线索条数）✓
│   ├─ player_invitation_kinds.csv 需要玩家自主接受／拒绝的行为类型（邀请等待不占用）✓
│   ├─ social_events.csv      社会事件状态机（多阶段跨相位）✓
│   └─ social_event_triggers.csv 社会事件触发条件（纯数值，禁日期记号）✓
├─ ui/
│   └─ chat_feedback_style.csv 闲聊反馈呈现参数（转笔四段 / 菜单 / 气泡 / 脚下圈 / 情绪阈值）✓
└─ balance/
    ├─ w_events.csv        事件权重全表（含 tier: normal 1–3 / major 4–5；class: A–E 五分类）✓
    └─ npc_weights.csv     NPC 决策权重（alpha 派生系数 / tau0 / top_n）✓
```

> 以上 CSV **已创建**（2026-10-05），参数初值见文件内注释；标定后按 `balance/` 前缀分支调整并记录 CHANGELOG。

## CSV 约定

- 编码 **UTF-8 无 BOM**；首行为表头，列名用 `snake_case` 英文。
- 数值列不得为空；布尔用 `0/1`；多值列用 `|` 分隔（如 `tags_init`）。
- 注释行以 `#` 开头（加载器需跳过）。
- 每张表必须有对应的字段说明文档段落（见 `docs/design/数据模型.md`），新增列须同步更新。

## 字段速览

| 文件 | 关键字段 |
|---|---|
| `characters/seeds.csv` | `id`、`alias`、`archetype`、`mbti`、`e`、`n`、`f`、`p`、`opacity_init`、`identity_seed`、`tags_init`、`initial_relations` |
| `characters/appearance.csv` | `id`、`alias`、`gender`、`sprite`（表现层立绘绑定，**不参与行为判定**） |
| `rules/stand_points.csv` | `point_id`、`kind`、`note`（课间走动目标；世界坐标在场景 `StandPoints/<point_id>`） |
| `rules/time_presentation.csv` | `phase_id`、`display_name`、`real_duration_seconds`、`game_duration_seconds` |
| `rules/time_runtime.csv` | `key`、`value`、`note`（`term_days` / `max_ticks_per_frame`） |
| `rules/time_flow.csv` | `param`、`value`、`note`（`normal_scale` / `player_action_scale`；世界播放倍率，事件可持有正常速度） |
| `rules/difficulty.csv` | `difficulty`、`npc_count`、`default`（新游戏默认档） |
| `rules/transmission.csv` | `theta_a`、`theta_h`、`sigma`、`beta_affinity`、`beta_hostility`、`epsilon` |
| `rules/decay.csv` | `axis`、`no_interaction`、`interacted`、`note` |
| `rules/phases.csv` | `phase_id`、`tick_count`、`active_rules`、`player_controllable` |
| `balance/w_events.csv` | `event_id`、`axis`、`delta`、`delta_min`、`delta_max`、`note` |
| `rules/player_interaction.csv` | `param`、`value`、`unit`、`note`（`chat_range_m` / `seated_chat_range_m` / `seated_tolerance_m` / `range_step_m` / `clue_*` / 拾取层掩码；玩家与 NPC 共用聊天空间口径） |
| `rules/player_invitation_kinds.csv` | `behavior`、`requires_choice`（0/1；配合 player_interaction 的邀请有效期与再次邀请间隔） |
| `ui/chat_feedback_style.csv` | `param`、`value`、`unit`、`note`（`pen_*_seconds` / `menu_*` / `bubble_*` / `ring_*` / `emotion_*`） |

## 校验要求

`config_loader.gd` 启动时校验并在失败时**明确报错（含文件名与行号）**，不得静默使用默认值：

- 必需列存在、行数符合预期（如角色表 24 行）；
- 数值范围合法（0–100 的轴、正数阈值）；
- `w_events.csv` 的每个 `event_id` 能对应到 v3.0 中的规则编号（`note` 列必须写明出处章节）；
- **表 ↔ 消费者双向一致**（`tools/check_config.py` §12）：新表的每个键都要有脚本读，
  脚本里 `params.get("键")` 的键也必须真的在表里 —— 两边都不允许「静默回落默认值」。

## 权威性

数值的**出处**必须可追溯到 [`../docs/gdd/core-gameplay-v3.1.md`](../docs/gdd/core-gameplay-v3.1.md) 的具体章节或它的标定目标（§3.4）。标定后的调整走 `balance/` 前缀分支并在 `CHANGELOG.md` 的「平衡」分类中记录。
