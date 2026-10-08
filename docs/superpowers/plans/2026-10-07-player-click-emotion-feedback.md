# 玩家点击落点与四种情绪气泡计划案

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本次仅交付素材与计划，不实施组件。

**Goal:** 为已有鼠标/WASD 玩家移动增加准确的落点反馈，并接入放松、生气、哭泣、开心的男女两组情绪气泡。

**Architecture:** PlayerController 提供经过寻路确认的目的地与移动生命周期；落点组件仅展示。玩家的可见事件反应通过小型情绪映射器选择四张表情之一，头顶屏幕 UI 根据 3D 锚点定位，男女版本仅负责外观。

**Tech Stack:** 当前 Godot 4.7.2、GDScript、Sprite3D/水平 MeshInstance3D、CanvasLayer/Control、Tween、现有 GUT。无需新插件、手绘序列帧或新的玩法随机数。

**Spec:** 用户确认四种情绪、男女两组，以及需要点击落点素材和可编程计划；主文档 §8、§10.4、§15。本文展示参数、四表情映射为具体建议，不改压力公式或新增情绪数值轴。

## 1. 现状与交付物

- `scripts/game/player_controller.gd` 已有鼠标寻路、WASD、is_auto_walking()/is_manual_walking()/destination()/can_control()；本任务不重复实现玩家控制。
- 当前成功落点尚无明确公开事件；UI 不应再次投射鼠标射线，自行猜目的地。
- `scripts/ui/speech_bubble.gd` 是 Node2D 自绘无字对话气泡，不是本次表情素材组件。保留它，用新组件承载带图片的情绪反馈。
- `appearance.csv` 已有 NPC gender 字段，但玩家使用末位专属节点，不能从 NPC 表或别名推断玩家版本。
- 本次已生成点击图：`assets/textures/ui/movement/click_destination_v01.png`，1254×1254、RGBA，alpha 范围 0..255。暖橙空心菱形、深棕轮廓与中心点；这是完整图，不是图集，不需裁切帧。
- 仓库检索暂未找到已生成的八张情绪气泡；既有素材不重画。正式路径在素材收录任务中填写，缺素材明确报告，不以乱码路径或假文件接线。

## 2. 点击落点的用户规则

| 输入/状态 | 落点表现 |
|---|---|
| 成功点击合法地面且寻路成功 | 在实际可达终点显示橙色菱形，弹入一次 |
| 点击家具后被吸附 | 标记吸附后的终点，不能画在原始点击坐标 |
| 寻路到最近开放格 | 使用最后一段实际路径终点，不能使用仍指向堵塞格的旧 goal |
| 自动行走 | 标记留在目的地，轻微缓慢呼吸；不跟着玩家脚走 |
| 再次点击成功 | 原标记立即被替换，只保留一个目的地 |
| 新点击不可达 | 不显示新的“可达标记”；旧计划若保留则保留旧标记，旧计划若取消则隐藏，必须与控制器一致 |
| 已在目的地 | 只播放短落点确认，不创建长驻自动行走状态 |
| 到达 | 缩小淡出并隐藏 |
| 按下 WASD | 取消自动路径并隐藏落点；手动移动不显示鼠标目的地 |
| 打开暂停菜单 | 取消/冻结策略跟随当前 PlayerController；已取消路径必须同步隐藏 |
| 转笔 hold、上课、简报、忙碌占用 | 禁止新移动标记；若原移动被取消则隐藏 |
| 点击 UI 或人物交互入口 | 不生成地面落点，输入优先由 UI/人物拾取消费 |

标记代表移动目的地，不代表交互成功，不改变脚下活动融合圈。颜色与菱形轮廓用于区分圆形活动圈，不再增加“成功绿色、失败红色”多套移动图片。

## 3. 点击组件实现

新增 `scripts/game/click_destination_marker.gd`、`scenes/game/click_destination_marker.tscn`。场景是地面水平的 Sprite3D 或带贴图的 QuadMesh，关闭 billboard、保留深度测试、使用透明材质、不投影。避免把 top-down 素材朝向镜头导致标记直立。

新增 `data/rules/player_feedback_style.csv`（key,value,note），建议：marker_quad_width_m=1.0、marker_ground_offset_m=0.015、marker_pop_seconds=0.12、marker_fade_seconds=0.18、marker_pulse_period_seconds=1.2、marker_pulse_amplitude=0.04。quad_width 是含图像透明边距的全画布宽度，按素材可见形状目视标定，不能把可见菱形半径当全画布半径。

公开方法 `show_destination(position: Vector3) -> void`、`arrive() -> void`、`cancel() -> void`、`set_feedback_paused(paused: bool) -> void`。每次新目标先 kill 旧 Tween，再重置缩放/透明度，避免旧淡出回调把新标记隐藏。位置固定在教室地面高度，不用人物步态高度。

PlayerController 新增信号：

- `destination_set(position: Vector3)`：只有路径接受成功后发出，位置使用 `_path[-1]`；同步让 destination() 返回这个实际终点。
- `destination_reached(position: Vector3)`：真实到达时发出，发信号前缓存路径终点。
- `destination_cancelled(reason: StringName)`：WASD/权限锁/取消/新计划替换按实际状态发；重复清理无信号风暴。
- `destination_rejected(requested: Vector3, reason: StringName)`：无效点击/无路径，可供调试或简短状态提示；不显示橙色可达标记。

不要每帧重建标记，不用渲染组件控制路径。首次绑定根据 is_auto_walking 与 destination 恢复显示；场景销毁断开连接。

## 4. 情绪素材收录

只用以下八个逻辑槽位：

| emotion_id | 中文 | male 建议文件 | female 建议文件 |
|---|---|---|---|
| relaxed | 放松 | male_relaxed.png | female_relaxed.png |
| angry | 生气 | male_angry.png | female_angry.png |
| crying | 哭泣 | male_crying.png | female_crying.png |
| happy | 开心 | male_happy.png | female_happy.png |

建议目录 `assets/textures/ui/emotions/`，复制收录，保留原图。若已有文件名不同，不强制改名，通过 `data/ui/emotion_bubbles.csv` 映射：`variant,emotion_id,texture_path`。路径填写实际 res:// 路径；表格必须恰有两组四种，不写不存在的资源作为已验收数据。

图片应带 alpha，主体与气泡尾巴完整，画布留边一致。现有图若自带白色气泡、边框和尾巴，就直接展示整张，不再套第二个气泡底板。若只有脸，统一由组件补同一个底板，八图不可混用两种包装。以现有画风为准，不要求重新生成八张。

不要求图片全部同分辨率；使用 keep aspect centered 的 TextureRect 统一显示框，画布过宽/透明边距不一致时登记给美术，不能强拉伸脸型。建议显示框 72×72 px（1920×1080 基准），最高不超过 96 px；少量素材可能需要配置偏移。

## 5. 情绪四分类：低成本、明确来源

本版仅展示**玩家自身**的情绪；NPC 默认不接，以免把隐藏内心通过气泡泄露。若后来需要 NPC 情绪，必须另补可见性规则，不能遍历所有真实矩阵直接展示。

不新增“开心值/愤怒值/哭泣值”累积轴，不按性别选择行为。四种表情是对玩家实际经历的反馈，由最近一次可见的已完成事件与玩家当前压力/性格选择。

建议规则如下，执行顺序从上到下：

| 条件 | 表情 |
|---|---|
| 完成事件使玩家压力下降，且玩家压力进入低压区（<40） | 放松 |
| 已完成事件对玩家是负面，玩家压力≥70 且玩家 F≥50 | 哭泣 |
| 已完成事件对玩家是负面，其余情况 | 生气 |
| 已完成事件对玩家是正面，其余情况 | 开心 |
| 中性、仅走动、点击地面、每帧更新、无新事件 | 不弹气泡 |

40/70/50 是现有压力分区与性格中点；正式从已有配置读取，不在组件里写死。哭泣/生气区分只使用数值性格，不写“某角色必哭”或“女生哭、男生生气”。男女素材仅由玩家外观 variant 选择。

事件效价以**玩家自身受到的实际效果摘要**为准，不以“判定成功一定开心”替代。建议定义 `player_effect_score = delta_affinity + delta_trust - delta_hostility - delta_stress`，各 delta 是这次事件对玩家自身态度/压力的变化，不是别人对玩家的真实态度。score>0 正面、<0 负面、=0 中性；权重初值均为 1 并放 data。若事件既减压又增加敌意，仍按上表顺序选择一次。

摘要必须在完成事件的统一结算处汇总一次，传给只读映射器；不能让 UI 扫描全矩阵猜测，也不能订阅多条逐轴 apply_event 各弹一次。中断若确实给玩家增加压力，用真实中断摘要触发负面；环境涓流不逐 tick 弹泡。

这是推荐的简单四表情映射，不声称完整实现主文档所有情绪词。旧表中的焦虑、羞涩、亢奋等本版不要求新增素材；主文档表保留设计含义，呈现章节注明只支持四种输出。

## 6. 情绪反馈接口与头顶显示

新增 `scripts/ui/player_emotion_feedback.gd`（纯映射，不写玩法）、`scripts/ui/emotion_bubble.gd` 和 `scenes/ui/emotion_bubble.tscn`。

映射器接口 `classify(effect: Dictionary, player_stress: float, player_f: float) -> StringName`，effect 字段 `delta_affinity,delta_trust,delta_hostility,delta_stress,event_id`；返回 relaxed/angry/crying/happy 或空字符串。不消费 RNG。

表现接口 `bind_anchor(anchor: Node3D, camera: Camera3D) -> void`、`set_variant(variant: StringName) -> void`、`show_emotion(emotion: StringName, event_id: String) -> void`、`clear() -> void`、`set_feedback_paused(paused: bool) -> void`。

在玩家节点添加 HeadAnchor（约在实际立绘头顶）；用相机投影到 CanvasLayer 内同一视口坐标系，保证远近人物上方图标保持清楚。相机后方、离开画面或 anchor 销毁则隐藏。现有姓名标签保留，气泡在它上方留间距。

玩家外观新增/复用 `bubble_variant`，male 或 female，保存为纯外观设置。优先跟随玩家选择的头像组；当前没有头像选择时由项目配置提供明确默认并记录开发状态。禁止从名字、玩家末位 ID 或性格推断性别；缺失映射时隐藏并只告警一次，不选择一张陌生图片伪装成功。

动画建议：0.12 秒弹入，1.5 秒停留，0.25 秒淡出；不额外扣游戏时间。每人只允许一张情绪气泡，不做队列积压。同 event_id 去重；新事件只保留最新一个。连续同表情设 2 秒最小再触发间隔，参数放 style 表。

如果正进行转笔判定，缓存最近一条情绪反馈，到结果揭晓后再播放；取消未揭晓演出时按实际结算状态处理，不能用情绪提前告诉玩家成功/失败。新负面事件可以替换正在展示的正面气泡，但不积压大量动画。

暂停菜单/全班模拟 hold 时气泡停留时间也冻结；屏幕位置仍可更新以跟随镜头，返回活动时继续。必须由时钟 paused 状态控制 Tween，不假设 get_tree().paused 能覆盖所有暂停原因。

## Global Constraints

- 本计划不修改移动速度、寻路、压力曲线、好感/敌对/信任公式。
- UI 不回写内核矩阵、不掷玩法随机数；情绪派生不引入新的累积情绪变量。
- 仅在玩家真正收到事件结果后显示；不能提前曝光隐藏结果或 NPC 内心。
- 鼠标落点、脚下个人/融合圈、头顶情绪三种语义独立，不复用同一个圈的状态。
- 样式和素材绑定配置集中；不得手改 .godot/ 或 resources/*.tres。
- PlayerController 与完成事件代码正在并行演进，只改必要接线位置，不复制另一个输入控制器。

## Review Focus

1. 原鼠标位置与最终路径终点不同，标记必须选后者（任务 1）。
2. 连点、WASD、取消与旧 Tween 回调不能错误隐藏新目标（任务 1）。
3. 同一事件多轴结算只弹一次，重复通知不能重复反馈（任务 3）。
4. 男/女和四情绪全部有真实路径；缺图不得导致场景无法启动（任务 2）。
5. hold 暂停与转笔未揭晓期间不提前显示结果（任务 3、4）。

## 7. 分任务落地

### Task 1：点击目的地信号与标记

**Files:** 修改 `scripts/game/player_controller.gd`；新增 marker 脚本/场景、style 表；新增 `tests/unit/test_click_destination_marker.gd`，扩充现有玩家控制测试。

- [ ] 写失败用例：吸附到不同点、目标格被调整时 destination_set 为最终路径端点；无路径不发成功信号。
- [ ] 写用例：第二次目标替换、WASD取消、到达、权限失效、UI消费点击，标记与实际路径一一对应。
- [ ] 实现 §3 四个信号与贴地组件，使用已生成 PNG；重复 show kill 旧 Tween。
- [ ] 检查当前路径 destination=goal 是否与 _path[-1] 不同，统一为真实终点，不另造路线。
- [ ] GUT 与当前相机截图通过后，提交 `feat(ui): 显示玩家点击移动落点`。

### Task 2：八张情绪气泡素材与绑定

**Files:** 收录用户既有八图到 emotions 目录；新增 `data/ui/emotion_bubbles.csv`；配置加载器接入真实表；新增素材校验测试。

- [ ] 取得实际源目录并盘点 eight slots；读取图像尺寸/alpha/完整边界，保留源文件。
- [ ] 将真实路径写入映射表，不把不存在文件注册成已完成资源。
- [ ] 验证两组各四种、映射唯一、Texture2D 可加载；缺一图记录具体槽位，既有功能继续可运行。
- [ ] 确认玩家 bubble_variant 来源；对有气泡底板/仅表情头像采用一致包装。
- [ ] 测试通过后提交 `art(ui): 收录玩家四情绪男女气泡`。素材尚未提供时此任务明确未完成，不阻塞点击组件。

### Task 3：实际事件摘要与四情绪映射

**Files:** 新增 player_emotion_feedback 映射器和 `tests/unit/test_player_emotion_feedback.gd`；修改玩家事件完成出口；新增 `data/rules/player_emotion_feedback.csv` 的效价权重与映射参数。

- [ ] 写分类用例：负面 S=75/F=60→crying、S=75/F=40→angry；正面→happy；减压且 S=30→relaxed；中性→空。
- [ ] 写同 event_id 多轴通知去重用例；仅移动/环境逐 tick 更新不触发。
- [ ] 在实际结算完成处汇总玩家自身效果摘要，分类一次，不包含他人→玩家的隐藏关系值。
- [ ] 将真实效果、失败/中断、玩家自身性格和压力输入映射器，验证男女版本不改变分类。
- [ ] GUT 通过后提交 `feat(ui): 派生玩家四种情绪反馈`。

### Task 4：3D 头顶显示、暂停与演出协调

**Files:** 新增 emotion_bubble 脚本/场景；修改 `scenes/game/classroom3D.tscn`、`scripts/game/classroom.gd`、必要的玩家 HeadAnchor 创建位置；新增 `tests/integration/test_player_feedback.gd`。

- [ ] 绑定同视口相机投影和玩家锚点，验证镜头移动/远近/画面外不会错误留泡。
- [ ] 实现最新反馈替换、同表情冷却、Tween取消与事件去重，不累计播放队列。
- [ ] 接入暂停及转笔结束出口，未揭晓时不显示结果相关表情；恢复不一次性补播旧泡。
- [ ] 验证点击标记与脚下融合圈、姓名、表情布局互不覆盖。
- [ ] 同种子同操作开/关反馈，内核矩阵/RNG/事件数量保持一致；集成测试通过后提交。

### Task 5：文档和最终验证

**Files:** 更新主文档呈现章节、`docs/art/UI图清单.md`、`data/README.md`、架构/CHANGELOG；不擅自改第八章情绪底层公式。

- [ ] 记录采用的四表情映射、真实素材位置、接口与未完成依赖。
- [ ] 运行相关 GUT、现有玩家控制/时间测试及真实对拍；六道门与铁律按项目要求执行，记录跳过项。
- [ ] 1920×1080 与 1280×720 检查落点、八槽位表情、暂停、连点、WASD取消、转笔结果揭晓。
- [ ] 将生成图在真实地砖背景上验收，小尺寸可辨；必要时仅调样式，不假称已有游戏截图验证。

## 8. 本次交付状态

- 点击标记 PNG 已生成、复制入项目，检查了分辨率与真实 alpha；未接入运行场景。
- 本计划已给出组件、信号、素材映射、规则、测试和五项实施任务。
- 八张情绪气泡尚未在工作区找到，素材绑定任务等待实际路径。
- 未编写组件代码，未运行新组件测试，未验证生成图在游戏中的实际尺寸效果。
