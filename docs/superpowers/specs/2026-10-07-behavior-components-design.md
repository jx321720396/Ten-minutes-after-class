# 内核行为组件重构设计

> 日期：2026-10-07 ｜ 状态：用户确认后已实施，验证记录见文末 ｜ 范围：GDScript 行为执行模块拆分
>
> 需求：把 SimCore 中的行为拆成独立组件。用户本轮要求先写成文档。
> 权威依据：主文档 §6、§10、§12、§18，以及 [架构总览](../../design/架构总览.md)。本文件规定工程拆分，不改变玩法规格。

## 1. 目标与范围

把 `scripts/core/sim_core.gd` 的十个 `_do_*` 执行函数迁入独立行为组件，让每种行为可以单独阅读、测试和维护。保留现有对外调用、函数参数、随机数消耗顺序、数值结算顺序及通知顺序。

本次不重写 NPC 决策、玩家行动权限、时间系统、行为完成机制、空间规则、影响公式或 Python 参考。当前已知但尚未解决的玩法缺口单独排期，不能混入重构，否则无法判断同种子差异来自搬移还是机制变更。

“组件”是 `RefCounted` 逻辑对象，不是挂到每个人物上的 Node，不需要 `.tscn`、场景树、单例注册或编辑器插件。所有角色共用本局的一套行为组件，通过参数选择发起者与目标，不为每个 NPC 创建十套实例。

## 2. 文件与职责

```text
scripts/systems/behaviors/
├─ behavior_context.gd
├─ behavior_registry.gd
├─ chat_behavior.gd
├─ join_chat_behavior.gd
├─ tease_behavior.gd
├─ report_behavior.gd
├─ rumor_behavior.gd
├─ roughhouse_behavior.gd
├─ exclude_behavior.gd
├─ comfort_behavior.gd
├─ ask_help_behavior.gd
└─ apologize_behavior.gd
```

| 文件 | 职责 |
|---|---|
| behavior_context | 对行为开放必要的读取与执行服务；不保存独立矩阵或 RNG |
| behavior_registry | 固定注册十种行为、执行分发、处理组件间调用 |
| chat_behavior | 现有话题事件、观测、聊天状态与通知 |
| join_chat_behavior | 接纳概率、预掷 roll 支持、接受调用聊天、拒绝反噬 |
| tease_behavior | 玩笑/嘲讽分档、围观响应及羞辱结果 |
| report_behavior | 举报事件、敌对回落、施害证据与通知 |
| rumor_behavior | 当前简化流言效果与旁观者观测 |
| roughhouse_behavior | 参与者收益与旁观者敌对 |
| exclude_behavior | 当前双向疏远与群体影响 |
| comfort_behavior | 当前安慰成本及目标效果 |
| ask_help_behavior | 当前求助判定与成功/拒绝效果 |
| apologize_behavior | 当前和解判定与不做关系调制的修复效果 |

本次保留在 SimCore：配置、状态数组、初始化、时间、统一公式、传导、压力与环境、观察/信念、行为占用和完成、目标选择、NPC 决策、玩家入口、统计报告。后续若拆这些模块，应另立范围。

## 3. 调用关系

```text
NPC 决策／玩家入口／原有测试
             ↓
SimCore._do_* 兼容转发
             ↓
BehaviorRegistry.execute(kind, i, j, options)
             ↓
对应 Behavior.execute(context, i, j, options)
             ↓
BehaviorContext → SimCore 现有读取／公式／占用／观测／通知
```

搭话成功通过 registry 调用 chat，复用同一份实现；不是回调 `_do_join_chat` 自身。保留“先搭话占用、再聊天占用”的当前顺序，以及 chat 通知在 join_chat 通知前发生的语义。

注册表按固定行为键定义，不能扫描目录反射注册，不能依赖字典遍历顺序决定 NPC 行为优先级。现有 `_decide_and_act()` 继续决定调用先后。

## 4. 行为公共契约

每个组件提供：

```gdscript
extends RefCounted

func execute(context: RefCounted, actor: int, target: int, options: Dictionary = {}) -> void:
    # 行为具体逻辑
    pass
```

registry 接口：

- `execute(kind: StringName, actor: int, target: int, options: Dictionary = {}) -> bool`：已注册并执行返回 true，未知键报明确错误并返回 false，不抽 RNG、不改状态。
- `has_behavior(kind: StringName) -> bool`：只读。
- `behavior_ids() -> Array[StringName]`：固定注册顺序，只读副本。

行为自身保留 void 结果；现有 accepted 字段、计数和事件仍按原函数生成，不统一改成新的结果对象。

options 仅包含现有特殊参数：

| 行为 | options |
|---|---|
| join_chat | `roll: float`，缺省 -1.0，沿用“负值时内抽” |
| tease | `audience: Array`，缺省空数组 |
| exclude | `crowd: Array`，缺省空数组 |
| roughhouse | `bystanders: Array`，缺省空数组 |
| 其他 | 空字典 |

传入成员顺序必须保留，禁止排序、去重或换用不同抽样策略；现有循环顺序影响结算去重和通知，属于等价性的一部分。

## 5. 共享上下文与状态边界

上下文绑定当前 SimCore，使用 WeakRef 保存内核引用；组件不得长期强引用 SimCore。避免 `SimCore → registry/context → SimCore` 的 RefCounted 循环，导致每局状态无法释放。

registry 与 context 由 SimCore 本局初始化一次。组件不持有上下文，execute 时传入；组件间调用通过 context 的执行转发完成。context 对 registry 的引用也应是弱引用或无环的 Callable，不能重新形成闭环。

最小服务面：

| 类型 | 接口 |
|---|---|
| 自有/目标真值读取 | `affinity(i,j)`、`hostility(i,j)`、`trust(i,j)`、`stress(i)`、`dimension(i,dim)`、`node_count()` |
| 配置读取 | `threshold(key)`，读取现有 `_thresholds_lookup`；缺键保留当前错误语义，不加静默默认 |
| 结算与占用 | `apply_event(i,j,event_id,scale=1.0,no_modulation=false)`、`occupy(i,j,behavior,quiet=false)` |
| 观测与证据 | `observe(i,j,axis,weight=1.0)`、`mark_hurt(perpetrator,victim)` |
| 聊天状态 | `set_in_conversation(i,value)`，仅改当前既有行为状态 |
| 概率服务 | `random()`、`sigmoid(z)`、`join_probability(i,j)`，共享同一 MtRandom 与公式 |
| 统计与通知 | `increment_stat(key)`、`emit_event(type,payload)` |
| 组件复用 | `execute_behavior(kind,i,j,options)`，转发本局 registry |

实现采用直接方法调用，不为每个 getter 包一层动态字符串 `call()`。确有类型循环时使用 preload 的脚本引用及 RefCounted/Variant 参数，不能为了 class_name 互相解析失败引入场景加载依赖。

组件通过访问器读取矩阵，不能取得原始数组并裸写。PackedFloat64Array 的复制/写时复制可能使组件写到副本，所以 context 不缓存矩阵数组；每次操作均进入当前内核对象。

**现有例外：** 举报直接执行发起者敌对减 5。为保持行为与舍入完全一致，本次用一个明确命名的上下文服务 `reduce_reporter_hostility(actor,target)` 封装该旧操作，执行体暂留内核；不能在重构中换成影响公式导致数值变化。该旧绕过点及字面量迁移仍是独立整改项，文档不冒称本次已消除所有历史铁律缺口。

上下文失效时 registry 执行明确失败，不为不存在的内核生成空对象或新 RNG；不部分执行后继续忽略错误。

## 6. 兼容入口

保留十个原函数签名，以一行/短段转发 registry：

- `_do_chat(i,j)`
- `_do_join_chat(i,j,roll=-1.0)`
- `_do_report(i,j)`
- `_do_tease(i,j,audience)`
- `_do_exclude(i,j,crowd)`
- `_do_rumor(i,j)`
- `_do_roughhouse(i,j,bystanders)`
- `_do_comfort(i,j)`
- `_do_ask_help(i,j)`
- `_do_apologize(i,j)`

现有 player_action 和 NPC 决策继续调用这些入口；现有 GUT 中直接调用私有行为的用例无需批量改名。兼容方法不保留第二份执行体，确保以后修改某行为只改一个组件。

注册集合不能直接替代 PLAYER_KINDS 或权限检查。当前 registry 有某行为，不等于当前玩家入口已经支持或允许它；本次不擅自接通玩家缺失行为。

## 7. 初始化与资源约束

SimCore 按当前初始化顺序完成状态和配置后创建 context 与 registry，在任何 `_do_*` 可能执行前完成注册。组件构造不得抽随机数、计算新关系或发事件。

同局共享组件，不跨局共享状态。registry 清理不得重复结束行为、写回矩阵或再发通知。组件没有 `_process`、`_ready`、Timer、Tween，也没有 `_rng` 字段。

不新增 project.godot autoload，不改资源 tres；只新增纯脚本。Python 原型无需对应拆文件，因为这是 GDScript 组织结构调整，但实际结果须保持与重构前一致。

## 8. 实施顺序

1. 锁定重构前基线：代码版本/工作区差异、配置指纹、测试结果、同种子快照和 RNG 状态。
2. 先写 registry/context 契约测试与行为等价测试，确认缺组件时失败。
3. 实现共享上下文与注册表；先迁 chat、join_chat，确认预掷 roll 和嵌套调用正确。
4. 迁 report、tease、rumor、roughhouse、exclude，验证施害方向、旁观者顺序和去重。
5. 迁 comfort、ask_help、apologize，验证随机判定与和解 no_modulation。
6. 旧函数缩为转发；检查所有调用均已到组件，没有残留双实现。
7. 同步架构总览、主文档工程章节的组织说明、CHANGELOG；不改玩法正文与数值。

如果实施时其他协作者修改同一行为，先重新确定该行为基线再迁移，不覆盖他们的新增完成机制或空间检查。

## 9. 验证与验收

### 组件契约

- 十种行为键全部注册，未知键不改状态、不消耗 RNG。
- context 不复制矩阵，不持有独立生成器；退出一局后可释放。
- 搭话使用预掷 roll 时不再抽一次；缺 roll 时抽取数量与原实现一致。
- 原入口、直接组件调用与嵌套 chat 调用得到同一组效果和通知。

### 行为等价

逐种行为设置可重复的初始态与参数，重构前后比较：A/H/T/H_deep、Stress、信念、会话状态、busy_until/busy_phase/busy_act、统计、hurt_day、去重状态、事件通知及 RNG 状态。不能只比较最终好感均值。

覆盖成功与失败、无围观与羞辱门槛、重复事件去重、敌对关系下和解、玩家调用、相位边界中断和行为完成。

整局比较使用固定种子 12345、42、2024，16 NPC＋玩家，运行 3 天和 30 天。迁移等价目标是**同一 GDScript 版本重构前后完全一致**；Python/GDScript 则依项目既定关键指标误差≤1%判据，不能将宽松跨语言容差拿来放行重构产生的变化。

### 项目检查

- 实际运行相关 GUT 及完整单元测试，不以历史全绿替代当前结果。
- 检查 scripts/core、systems/behaviors 无场景/UI引用、无全局随机和角色名条件。
- 六道门全部运行，以 `&&` 串联，保持默认多种子口径；对拍必须真实执行，SKIP 不算完成。
- 若现有基线就失败，记录原有失败与本次新增失败，不因“此前就有问题”省略验证。

### 完成定义

- 十种行为执行逻辑各自只有一份，位于独立组件。
- SimCore 不再包含这十种行为的完整执行体，原签名继续可用。
- 状态、公式、时钟、决策仍只有一个事实源。
- 同种子矩阵、占用、事件顺序与 RNG 序列保持一致。
- 文档如实区分重构已完成与历史玩法缺口；未把搬移包装成玩法修复。

## 10. 实施与验证记录

用户确认后按 [实施计划](../plans/2026-10-07-behavior-components.md) 完成十组件拆分与原入口转发。未修改 data 数值、Python 参考或玩法决策。

- 新组件契约测试先确认因注册表缺失失败；实施后 9 项通过。
- 完整 GUT：重构前 126/126，重构后 135/135；既有玩家控制测试的 4 个 orphan 提示仍存在。
- 重构前后 131 个完整状态/事件/RNG 摘要完全一致：十种行为的 17 个显式分支及边界、7 种玩家入口、三个种子各 30 天日末。玩家返回结果也相同；测试探针支持外部旧脚本构造，不覆盖工作区文件。
- 使用临时实际导出器，seed=12345、16 NPC、3 天，Python/GDScript 的 1440 tick 五项均值全部在 1% 以内。项目自动导出入口仍是骨架，本次没有把临时验证冒充正式自动对拍已接通。
- 配置校验 241 项、Python 内核测试 39 项、公式对拍 11 项、文档检查及 100 局多样性通过。
- 100 局玩法指标未通过：爆发均值 84.2（目标 15–30）、好感均值 17.4（目标 45–65）、好感 SD 19.9（目标≥20），饱和率 0%。这是未改动的 Python 基线，留给平衡任务处理。
- 无角色名分支、观察层只读检查通过；魔法数字扫描仍报旧数值补偿算法常量 `134217729.0`，没有新增规则字面量。
- 新增组件与测试的 gdformat/gdlint 通过；只读独立审查无阻塞发现，其指出的玩家历史等价性缺口已补入探针验证。

代码重构已经完成，但当前仓库不能宣称所有质量门全绿。本轮没有自动提交或推送。
