# 时间组件完整计划案

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本文件仅为计划，尚未执行实现；不自动派发子代理。

**Goal:** 把 3D 教室接入内核唯一时间源，实现可操作课间、上课发酵、每日简报停留与学期结束，并提供清晰的时间 UI。

**Architecture:** SimCore 持有唯一玩法时间；SimulationClock 将真实经过时间换算成整数模拟 tick，TimeHUD 只读取快照。相位边界、日末结算由内核负责，场景不得另造一套日历或调用私有结算函数。

**Tech Stack:** 项目既定 Godot 4.7.2、GDScript、现有 GUT；不新增依赖。

**Spec:** `docs/gdd/core-gameplay-v3.1.md` §3、§8、§12、§14、§18；`data/rules/phases.csv`。本文接口与 UI 为实施建议；明确标注的玩法提案未获裁决前不得改写主文档。

## 1. 范围与当前事实

本组件同时包含时间驱动、时间显示、相位切换与暂停管理。人物目标选择、寻路、关系算法、转笔美术、简报内容生成属于其他组件；本计划仅定义接口。

2026-10-07 现场读取的现状：

- `scripts/core/sim_core.gd` 已有 `advance_tick()`、`advance_phase()`、`advance_day()`、`day()`、`phase()`、`phase_index()`、`tick_in_phase()`、`global_tick()`。
- `advance_tick()` 在下一 tick 开始前处理前一相位的边界，单步末尾仍保留旧相位。这是同种子对拍的既有观测语义，必须保护。
- `scripts/game/classroom_roam.gd` 使用独立的 `break_seconds`、`class_seconds` 驱动走动演示，不是玩法时间。
- `autoload/game_state.gd` 的 `day`、`phase` 目前没有成为可靠的实时镜像；HUD 应读取内核快照。
- `autoload/save.gd` 只保存版本化字典，不代表完整内核恢复已经实现。
- 当前场景为 `scenes/game/classroom3D.tscn`，人物是 3D 空间中的纸片表现。

交付目标：新游戏进入教室即可从第 1 天上午课间开始；一整天精确运行 480 tick；简报等待时不推进；第 30 天结束后停止模拟。直接运行场景也通过现有演示建局入口接入相同时间组件。

## 2. 固定时序与换算

| 顺序 | phase_id | 玩家操作 | tick 数 | 实时标称时长 | tick 间隔 |
|---|---|---|---:|---:|---:|
| 1 | morning_break | 允许 | 100 | 100 秒 | 1 秒 |
| 2 | morning_class | 禁止 | 90 | 15 秒 | 1/6 秒 |
| 3 | lunch_break | 允许 | 100 | 100 秒 | 1 秒 |
| 4 | afternoon_class | 禁止 | 90 | 15 秒 | 1/6 秒 |
| 5 | afternoon_break | 允许 | 100 | 100 秒 | 1 秒 |
| 6 | day_settle | 禁止 | 0 | 等待玩家继续 | 不推进 |

每天 480 tick、330 秒，不计暂停及简报；30 天共 14,400 tick、165 分钟。每段课间对应游戏内 10 分钟，每段上课对应 45 分钟；不新增未经规格确定的 08:00 等钟表起点。

新增 `data/rules/time_presentation.csv`：字段 `phase_id,display_name,real_duration_seconds,game_duration_seconds`；前五行分别对应上表，课间 game_duration_seconds=600，上课=2700。settle 行两时长为 0。相位顺序、tick 数与权限仍只从 phases.csv 读取，不能在新表重复定义。

新增 `data/rules/time_runtime.csv`：`key,value,note`，`term_days=30`、`max_ticks_per_frame=8`。前者来自学期规格；后者是建议的性能预算，不影响 tick 总数。启动校验 active phase 时长为正、settle 时长为零、两表相位一致、term_days 为正整数。

## 3. UI 方案

固定在左上角的紧凑 2D 卡片，挂 CanvasLayer，适配 3D 教室；样式采用米白底、细墨绿边框、清晰黑体。颜色、间距由主题统一，禁止在 HUD 内自行创建另一套装饰风格。

常态示例：`第 6 / 30 天 · 中午午休`，第二行 `课间剩余 01:24`，下方一条剩余时间条。显示真实操作倒计时；游戏内 10 分钟留在说明或提示，不同时显示两个倒计时。

上课示例：`上午课堂 · 发酵中`，进度条与 `本阶段约剩余 00:12`；禁用玩家主动交互和点击移动，仍可查看已获得的情报与推理板。

日末示例：`第 6 天结束`，打开每日简报并停止模拟；按钮 `进入第 7 天`。第 30 天按钮改为 `查看学期报告`，没有第 31 天可操作课间。

铃声与阶段名称提示在边界触发一次，不逐帧播放；首版提示与铃声不额外消耗模拟时间。倒计时显示向上取整，边界处显示 00:00，不出现负数。低帧率积压时显示模拟剩余时长的估计，不承诺真实墙钟准点结束。

## 4. 核心接口与状态

### SimCore：时间事实与明确边界

新增 `time_snapshot() -> Dictionary`，固定字段：`day:int, phase_id:String, kind:String, phase_index:int, tick_in_phase:int, tick_count:int, global_tick:int, player_control:bool`。现有 `phase()` 只返回 kind，不能用来区分上午与下午。

新增 `finish_time_boundary() -> Dictionary`：只在当前阶段 tick 已耗尽时有效，完成与原 `_transition_if_needed()` 相同的边界动作，绝不运行 `_tick()`；返回 `changed:bool, ended_day:int, day_settled:bool, snapshot:Dictionary`。重复调用不重复结算或发事件；未耗尽返回 changed=false。实现应复用原边界逻辑，不能复制一份结算代码。

保留原 advance_tick/phase/day 的公共语义和对拍输出。实时驱动只调用 advance_tick 和新增边界接口，不在播放中调用 advance_phase 快进整段。finish_time_boundary 为显式调用提供新能力，不改变原有离线调用的采样时点。

日末会把内核游标推进到下一天；显示层仍保存 ended_day 并进入 report 状态。第 30 天内核可保留现有的 day=31 结算游标，但不执行第 31 天 tick，不给玩家展示可操作第 31 天。这一处理保护现有报告统计的 day-1 口径。

### SimulationClock：真实时间调度

新增 `scripts/game/simulation_clock.gd`（Node），接口：

- `bind_core(core: SimCore) -> void`：读取配置并初始化，不推进 tick。
- `pump(delta_seconds: float) -> void`：可测试的固定步长驱动；_process 仅调用它。
- `hold(owner: StringName) -> void` / `release(owner: StringName) -> void`：按拥有者集合暂停，可重入添加，同名重复添加不累计；最后一个拥有者释放后才恢复。
- `continue_after_report() -> bool`：仅 report 状态且非学期结束时成功；清空累计真实时间，进入下一天。
- `snapshot() -> Dictionary`：内核时间字段，加 `mode:String, paused:bool, remaining_seconds:float, progress:float, ended_day:int`。
- 信号 `time_updated(snapshot: Dictionary)`、`phase_changed(snapshot: Dictionary)`、`report_ready(ended_day: int)`、`term_finished(ended_day: int)`。

mode 取 `running/report/finished`。一旦 report 或 finished，pump 不推进。

推进规则：累计 delta；达到当前相位 real_duration_seconds/tick_count 时扣除间隔并推进一个 tick。每帧最多处理配置预算，保留积压，禁止跳 tick。遇任意相位边界，执行 finish_time_boundary、发通知并停止本帧批处理；清空旧相位累计时间，下一相位下一帧开始，避免卡顿跨过一个完整可操作课间。标称时长不计该边界帧及低帧率延迟。

暂停期间忽略 delta，恢复后不追赶暂停时间。remaining_seconds=max(0,(tick_count-tick_in_phase)*interval-clamp(accumulator,0,interval))；progress 根据已完成 tick 与有效的小数进度计算，限制在 0..1。

暂停菜单导致场景树暂停时，时钟自然不处理；判定演出使用 hold/release 允许 UI 动画继续。进入 report 时清理本次判定等临时持有者，但不能提前释放仍打开的暂停菜单；跨场景时销毁时钟及其持有者，不向旧内核继续推进。

## 5. 行为、移动、演出的接口

- 操作入口以 kind=break、mode=running、非暂停和玩家自身可行动为条件；不能只隐藏按钮，实际命令入口也应拒绝不合法操作。
- 行为的 busy_until 和完成时点由内核 tick 管理；表现层动画结束不能代替行为完成。
- 行为跨相位未完成按既有中断规则处理；上课铃触发取消不合法交互与归位表现，不能在上课继续接收社交指令。
- 行走组件读取时间驱动提供的 phase_changed，不再自造课间/上课计时。现有 ActorWalker 仍负责表现，路径规划与 NPC 目的选择不属于时间组件。
- 当前 move.duration=15 tick 的口径在实施时保留；按路径长度计算移动时间是讨论中的提案，需要另行确定并同步 Python/GDScript，不能在本任务中悄悄改动。
- 转笔开始前由行为内核抽取并锁定结果；UI 只接收信念估计值与结果，不获得真实概率，不额外消费玩法 RNG。
- **提案：** 转笔演出期间全班模拟暂停，角色的真实行为耗时仍照常由 tick 支付。该建议尚未获得用户明确裁决；实施前确认或沿用现有玩法，不把建议当成事实。
- 若采用演出暂停，PenCheckUI 用自己的演出秒数播放 Tween，并保证跳过、取消、关闭都释放自己的 hold，不释放其他拥有者。
- 归位采用内核相位转换后表现归位；此时禁用玩家操作，不额外增加相位 tick。不得为等动画结束而增加第三段上课或隐藏的游戏时间。

## 6. 存档边界

首版只保证“日末简报边界保存”，不新增任意 tick 自动保存。快照必须同时保存完整内核状态及 RNG 状态；时间游标单独保存不能恢复同种子局。

时间组件保存 mode=report、ended_day、相位游标及 config 版本/指纹，accumulator 在日末为零；暂停拥有者、Tween 进度不存。恢复后先显示同一日简报，点击继续才开下一天，不重复执行跨天衰减。finished 状态恢复后进入报告。

完整 SimCore 序列化若仍未实现，由存档任务负责；本组件定义字段与验收用例并接入可用接口，不冒称“保存时间就完成继续游戏”。

## Global Constraints

- 玩法依据主文档；所有时长、阈值与性能预算配置集中在 data/。
- scripts/core 不依赖 UI、场景或全局表现单例；不新增全局随机调用。
- NPC 和玩家遵循相同模拟时钟；暂停不能只暂停玩家而让隐藏关系继续变化。
- 不按第 N 天注入剧情；30 天是学期长度，不是脚本事件安排。
- 不手改 resources/*.tres，不改 .godot/；project.godot 仅确有注册需求才改，本计划不要求新增 autoload。
- 当前工作区已有其他人的修改，实施只编辑本任务文件和明确的接入位置，不清理或覆盖并行工作。

## Review Focus

1. 低帧率与大 delta：不丢 tick、不跳过整个课间（任务 2）。
2. 第 480 tick 与第 14,400 tick：结算只一次、不偷跑次日 tick（任务 1、4）。
3. 暂停菜单与转笔重叠：一方结束不得解除另一方暂停（任务 2）。
4. 日末存档恢复：不重复衰减、不直接进入下一天（任务 4）。
5. 切场景和重复绑定：旧时钟失效、信号不重复、演示时间不再驱动人物（任务 3）。

## 7. 分任务实施

### Task 1：内核只读快照与边界接口

**Files:** 修改 `scripts/core/sim_core.gd`；新增 `tests/unit/test_time_boundary.gd`。

**Interfaces:** 产出 time_snapshot 与 finish_time_boundary，字段见 §4。

- [ ] 写失败用例：初始化 day=1、morning_break、global_tick=0；100 次 advance_tick 后 global_tick=100、tick_in_phase=100，finish_time_boundary 后 morning_class、global_tick 仍为 100；再次调用 changed=false。
- [ ] 写日末用例：480 tick 后显式处理边界，只发一次 day_settled；全局 tick=480，重复处理不衰减、不增 tick。
- [ ] 用 GUT 单独运行该文件，确认失败源于缺接口。
- [ ] 实现快照及复用原转换逻辑，保留旧公共方法语义。
- [ ] 同时运行原有 SimCore 测试与同种子导出对拍，确认旧采样与关键指标没有变化。
- [ ] 按任务文件定向提交，提交描述 `feat(time): add explicit phase boundary snapshot`。

### Task 2：配置与固定步长时间驱动

**Files:** 新增两张时间配置表及 `scripts/game/simulation_clock.gd`、`tests/unit/test_simulation_clock.gd`；修改 `scripts/core/config_loader.gd` 与 `autoload/config.gd` 的相关读取/校验位置。新增表遵循现有加载机制。

**Interfaces:** 消费任务 1 接口；产出 §4 时钟方法与四个信号。

- [ ] 写用例：pump(0.4) 不增 tick，再 pump(0.6) 增 1 tick；上课 90 tick 标称 15 秒；不同 delta 分割到同一 tick 时内核状态一致。
- [ ] 写用例：hold(a)、hold(b)、release(a) 仍暂停；release(b) 恢复；重复 release 无副作用；暂停期间 RNG 和关系不变。
- [ ] 写用例：大 delta 达每帧预算后保留积压；达到边界后同帧不运行新相位 tick；课间进度、剩余秒数不越界。
- [ ] 写配置失败用例：重复相位、缺表项、负时长、零 tick 活动相位拒绝加载。
- [ ] 运行失败用例，按 §2/§4 实现配置、调度与信号。
- [ ] 运行新增配置与时间测试，确认全部通过；提交 `feat(time): drive simulation with configured fixed ticks`。

### Task 3：3D 场景与时间 HUD 接入

**Files:** 新增 `scenes/ui/time_hud.tscn`、`scripts/ui/time_hud.gd`；修改 `scenes/game/classroom3D.tscn`、`scripts/game/classroom_roam.gd`、`autoload/game_state.gd` 的时间接线；新增 `tests/integration/test_time_scene.gd`（GUT 场景集成测试）。

**Interfaces:** HUD 消费时钟 snapshot/signals；Roam 消费 phase_changed；GameState 保持内核持有职责。

- [ ] 写集成用例：场景只有一个有效 SimulationClock；一次推进对应一个内核 tick，重复进入不重复连接；上课移动命令被拒绝。
- [ ] 实例化 HUD，验证名字来自 phase_id 配置、倒计时向上取整、day_settle 显示 ended_day。
- [ ] 关闭 Roam 自身时间循环，由真实相位驱动；保留其目标选择演示并明确不属于正式 NPC 策略，避免本任务扩展为寻路重写。
- [ ] 接入 HUD 和暂停菜单，时钟对内核只绑定一次；GameState 镜像若保留则从快照统一更新，不独立自增。
- [ ] 1920×1080 与 1280×720 各检查课间、上课、暂停截图；HUD 不遮主要交互对象，文字无截断。
- [ ] 运行集成用例；提交 `feat(time): connect classroom clock and phase HUD`。

### Task 4：日末停留、学期结束与存档衔接

**Files:** 修改 `scripts/game/simulation_clock.gd`；新增 `tests/unit/test_time_term.gd`；按实际简报组件接入回调。完整内核存档另属存档任务，本任务只接已存在的序列化接口，缺失时明确交接。

**Interfaces:** report_ready、continue_after_report、term_finished；保存字段见 §6。

- [ ] 写用例：第 480 tick 后 mode=report；继续 pump 不增 tick；点继续一次进入第 2 天，重复点击不多进一天。
- [ ] 写用例：30 天总计 14,400 tick、30 次结算、term_finished 一次；结束后任何 pump/继续请求不运行第 31 天。
- [ ] 写恢复用例：report 模式游标恢复后依旧停留，不重做日末结算；存在完整内核序列化时比较原局与恢复局后续 RNG/矩阵。
- [ ] 实现状态门控与报告按钮；存档依赖未完成时显示明确开发状态并保留接口，不提供虚假的成功恢复。
- [ ] 测试通过后提交 `feat(time): stop at daily reports and term completion`。

### Task 5：文档收口与完整验证

**Files:** 修改主文档受影响的时间接口条目、`docs/design/架构总览.md`、`docs/design/数据模型.md`、`data/README.md`、`CHANGELOG.md`；必要时更新 `tools/check_config.py` 的新表校验。

- [ ] 将已确定的实现接口写入文档；未裁决的演出暂停、距离耗时仍保留提案状态，不混入事实源。
- [ ] 运行全部 GUT 单元与新增集成测试，确认原有移动组件测试仍通过。
- [ ] PowerShell 通过现有 bash 工具运行六道门，保持命令以 && 串联：`python tools/check_config.py && python tools/test_core.py && python tools/verify_formula.py && python tools/check_metrics.py && python tools/diversity_report.py && python tools/check_docs.py`。
- [ ] 运行 `bash tools/run_tests.sh --godot "<本机 Godot 完整路径>"`；同种子 Python/GDScript 关键指标误差 ≤1%。实际命令与 Godot 路径按 tools/README.md，不安装另一套引擎。
- [ ] 从主菜单和直接运行教室两条入口目视走完一日；确认五个相位顺序、上课禁操作、日末停止、继续开下一天。
- [ ] 记录实际通过/失败与未完成依赖，定向提交文档；不得仅凭计划用例宣称测试通过。

## 8. 交付与验收清单

- [ ] 内核是唯一日历与 tick 真值，演示计时不再影响正式时间。
- [ ] 每日三个操作段与两个发酵段各一次，精确 480 tick。
- [ ] 时间 HUD 在 3D 教室中清晰，阶段、剩余时间和权限一致。
- [ ] 暂停恢复不补跑暂停时间，嵌套暂停不提前恢复。
- [ ] 铃声/边界/结算信号不重复，行为中断只结算一次。
- [ ] 日末简报等待不计时，第 30 天终止精确。
- [ ] 移动表现、行为占用、UI 演出使用明确的各自时间职责。
- [ ] 存档完整性按真实完成情况交接，未完成项不冒称可用。
- [ ] 原内核对拍、六道门与相关 GUT 验证留有结果。

建议实施顺序为任务 1→2→3→4→5，先跑通一日再处理报告恢复。不新增时间加速按钮、任意时点存档或复杂昼夜光照，避免扩展首版范围。
