# tools/ —— 离线脚本

贴图压缩：`py -X utf8 tools/compress_textures.py` 默认只预览；应用时使用 `--apply --backup <项目外的新目录>`，默认质量 80，保留尺寸与透明通道，跳过法线／材质、像素原型、图标及标志。应用后通过 Godot 正常 `--headless --path . --import` 更新导入资源。逐文件原图与 compression-report.json 保存在备份目录。降低的是磁盘／包内资源大小，不降低分辨率或保证显存下降。

考试漫画验收：`godot --headless --path . --script res://tools/smoke_exam_comic.gd` 检查自动播放、冻结、成绩接线、未达标与防重复结算；加 `-- --live` 验证真实教室入口。使用图形渲染并加 `-- --capture` 可生成分镜与成绩截图至 `tools/out/exam_comic/`。

压力灯光验证：`godot --headless --path . --script tools/verify_pressure_lighting.gd` 检查真实教室平滑过渡、固定镜头更新、旧玩家排除及压力只读；去掉 `--headless` 可生成三档截图至 `tools/out/pressure_lighting/`。

> 状态：生效 ｜ 维护者：程序 ｜ 最后更新：2026-10-08

本目录存放**不参与游戏运行**的离线脚本：批量标定、数据校验、内核原型验证。见 [`../docs/design/架构总览.md`](../docs/design/架构总览.md) 的目录约定。

## 为什么有 Python 原型

项目最终实现在 Godot（GDScript），但**本机没有 Godot 可执行文件**，无法运行引擎验证。因此先用 Python 写一份**等价内核原型**验证公式与不变式，确认算法正确后再移植到 `scripts/core/`。

> 原型与正式实现的关系：**原型验证"公式对不对"，GDScript 实现"能不能跑在引擎里"**。两者共用同一套 `data/` 参数表。

## 现有脚本

玩家邀请参考模型见 `player_invitations.py`：由 `core_sim.py` 的行为入口调用，读取 `player_invitation_kinds.csv` 与 `player_interaction.csv`；离线无人回应时邀请过期，不替玩家接受。Python 原型仍没有真实聊天会话与场景寻路，因此邀请参考模型不覆盖 Godot 的群聊成员与几何校验；这些通过 GUT 和真实教室集成测试验证。

| 脚本 | 用途 | 运行 |
|---|---|---|
| [`core_sim.py`](core_sim.py) | **最小无头内核原型**：时间/相位/tick + 状态矩阵 + 统一影响公式 + 传导（感知 + 涓流）+ 信念矩阵 + 3 个行为 + 决策 softmax + 跨天衰减 | `python tools/core_sim.py --days 3 --seed 12345` |
| [`test_core.py`](test_core.py) | **一致性测试**：手算例（性格倍率 / 关系调制 / 软饱和 / round 0.1 / 负反馈）+ 不变式（决策禁读 `A[j][i]`、同种子同结果、数值范围、`tau > 0`） | `python tools/test_core.py` |
| [`verify_formula.py`](verify_formula.py) | **公式对拍**：按 UIF §8 的 `(i,k,X,E,C,P,Δ)` 独立重算，与实现逐项比对（事件链 / 传导链 / 衰减链） | `python tools/verify_formula.py` |
| [`calib_experiment.py`](calib_experiment.py) | **标定对照实验**：跑不同 `β` / 保留率 / 负反馈组合，输出均值、饱和率、SD（分化度） | `python tools/calib_experiment.py 25` |
| [`check_config.py`](check_config.py) | **配置表启动校验**：档位一致性 / 取值域 / 门槛与先验关系 / 趋势性等，含导航烘焙口径（`nav_max_climb < nav_blocker_height`），可接 CI | `python tools/check_config.py` |
| [`check_export_imports.py`](check_export_imports.py) | **导出前检查**：`data/**/*.csv` 的 `.import` 必须全部是 `importer="keep"`、`type=""`；否则 `csv_translation` 导入器会接管 CSV，安卓包丢表（桌面端不受影响） | `python tools/check_export_imports.py` |
| [`day_budget.py`](day_budget.py) | **一天收支预算（只算账）**：从 `data/rules/*.csv` 读速率与耗时，算一整天各状态的动力／压力／收益、老师一日动力上限、阈值维持成本、邻座涓流扩散上限与第八天目标均分（现 490）的算术可达性；不改任何数值 | `python tools/day_budget.py` |
| [`bake_classroom_nav.gd`](bake_classroom_nav.gd) | **教室导航网格烘焙**（GDScript，需 Godot）：参数取自 `data/rules/movement.csv`，产物 `resources/navigation/classroom_nav.tres`；改了教室占位几何后必须重跑 | `godot --headless --path . --script tools/bake_classroom_nav.gd` |
| [`md2docx.py`](md2docx.py) | **md → docx 导出**：标题 / 表格 / 代码块 / 行内格式，输出到 `docs/export/` | `python tools/md2docx.py --all` |
| [`export_encyclopedia.py`](export_encyclopedia.py) | **百科词条导出**：把 `data/localization/encyclopedia.json` 导成一份「一词条一块」的 Markdown 编辑稿（`docs/localization/百科全书-词条编辑稿.md`），供逐词条改文案；`--check` 比对编辑稿与 JSON 是否同步 | `python tools/export_encyclopedia.py` |
| [`import_encyclopedia.py`](import_encyclopedia.py) | **百科词条回写**：把编辑稿的改动写回同名 JSON（JSON 仍是唯一事实源）。校验 id 重复 / category 不在分类表 / 正文代码块没收尾等，出错不写盘；`[t]…[/t]` 引用了不存在的词条只警告 | `python tools/import_encyclopedia.py --dry-run` |
| [`export_ticks.py`](export_ticks.py) | **逐 tick 状态导出（对拍基建）**：hook 内核 `tick`，导出同种子逐 tick 的关系三轴 / 透明度 / 压力统计与矩阵哈希，供 GDScript 移植后逐 tick 对拍（冲刺计划 D6–D9） | `python tools/export_ticks.py --days 3 --seed 12345 --npc 8` |
| [`headless_day_book.gd`](headless_day_book.gd) | **三策略收支与过程记录**（GDScript，需 Godot）：A 自动巡查无操作／B 有限督学（表扬＋换座）／C 集中督学，同种子对照；逐 tick 记录压力峰值与 >70 持续、学习与共同学习组人数、敌对总量、伤害与拒绝、崩溃人·tick、老师占用 tick，并出 30 天满格好感结构；只读 `data/` | `godot --headless --path . --script res://tools/headless_day_book.gd -- 8 12345 16` |

> 导出产物默认落 `tools/out/`（机器产物，已在 `.gitignore` 中排除）。

## 一键跑测试

结算真实场景流程验收：`godot --path . --script res://tools/smoke_outcome_flow.gd --rendering-method gl_compatibility --audio-driver Dummy`，实例化生产教室与时钟，检查考试／失败／结束及原生按钮接线，夹具仅限验收进程，保留玩家归档。使用图形渲染可避开无头 Dummy 渲染器的已有纹理初始化告警。

考试／辞退／本局回顾截图：`godot --path . --script res://tools/capture_outcome_ui.gd --rendering-method gl_compatibility --audio-driver Dummy`，使用生产界面与独立数据夹具，输出至 `tools/out/outcome_ui/`；不覆盖玩家归档。详见 [验收记录](../docs/qa/考试与结束界面验收-2026-10-18.md)。

[`run_tests.sh`](run_tests.sh) 把「六道门（`tools/*.py`）+ 导出前置检查（CSV 导入模式）+ 铁律测试（`tests/invariants/`）+ 逐 tick 对拍（`tests/integration/`）+ Godot 侧 GUT 单测」串成一条命令：

```bash
bash tools/run_tests.sh                                      # 自动探测 Godot
bash tools/run_tests.sh --godot "E:/godot/Godot_v4.7.2-stable_win64_console.exe"
bash tools/run_tests.sh --no-godot                           # 只跑离线部分
```

- **Godot 路径**查找顺序：`--godot` 参数 > 环境变量 `GODOT_BIN` > 仓库根 `.godot_path` 文件 > `PATH`。
  本机没把 Godot 加进 PATH 时，把完整路径写进 `.godot_path`（该文件不入库）即可长期生效：
  `echo "E:/godot/Godot_v4.7.2-stable_win64_console.exe" > .godot_path`
- 找不到 Godot 时**只跳过 Godot 段**，六道门与铁律测试照跑；退出码 0 = 全部通过（跳过不算失败）。
- Windows 必须用 **console 版**可执行文件才能拿到 headless 输出（见 [`../tests/README.md`](../tests/README.md)）。
- 脚本已强制 `PYTHONIOENCODING=utf-8` —— 本机 GBK 控制台下六道门会因 `✓` 抛 `UnicodeEncodeError`。
- **耗时**：全套离线测试约 **45 秒**（其中第四 / 第五道门各约 18 秒，其余七项合计不到 1 秒）。
  两道重门默认**多进程并行**——局与局互相独立（各自 `Sim(seed)` + 各自 `random.Random(seed)`），
  结果与串行**逐位一致**；调试时可加 `--jobs 1` 强制串行（见 `tools/check_metrics.py` 抬头）。

参数：`--days`（天数）、`--seed`（随机种子，保证可复现）、`--npc`（NPC 数量）。
第四 / 第五道门另有 `--seeds`（局数，默认 100）与 `--jobs`（并行进程数，默认按核数、上限 16）。

## 已验证的结论（2026-10-05）

- ✅ **实现与文档公式完全一致**：`verify_formula.py` 对事件链、传导链、衰减链做独立重算对拍，**4 项全通过**（含 `tease_hostility` 的 `M`=−0.30 → −1.000，证明关系调制生效）；
- ✅ 统一影响公式的**性格倍率**（`clamp(1+Σw·d, 0.1, 1.2)`）、**关系调制**、**软饱和**（`u/(1+|u|/U)`）、**round(0.1)**、**负反馈**均与文档一致；
- ✅ 事件去重（同一对子同规则每课间段一次）有效：一天事件数 8765 → 1402；
- ✅ 传导「每天 2 次」结算正确（3 天结算 6 次）；
- ✅ 同种子同结果、所有轴落在 0–100、决策未读真实值；
- ✅ **30 天不饱和达成**（负反馈落规格后）：饱和率 **0.0%**、均值 **50.4**、SD **19.5**（目标：饱和 <10%、均值 45–65、SD ≥20）。

## 已暴露的待标定问题（原型局限，非 bug）

| 现象 | 原因 | 下一步 |
| --- | --- | --- |
| （**已解决**）30 天全班饱和 90.8% | 好感是**正反馈**：稳态 = 每日增益/(1−保留率) ≈ 192 → 封顶 | ✅ **负反馈已落规格**（统一写入点、正向轴）；实测 30 天饱和率 0.0%、均值 50.4 |
| （**非问题**）3 天好感 30 → 31.8 | 关系是**慢变量**：去重 + 分散互动让每条边一天净增 1–3 点；且初始好感低于传导阈值 `θ_A`，传导尚未启动 | ✅ **符合 §3.4 标定目标**——不要为了「看起来快」而调大 `base` |
| （**已解决**）压力爆发 0 次（目标每 1–2 天一次） | 原型只实现了 3 个行为，**负面事件来源太少**（仅「被拒绝」） | ✅ 补齐【当众调侃】【流言】【心结】+ **调侃目标带偏好**（聚焦「被讨厌的人」）后：**爆发每 2.0 天一次**，压力形态变为「少数人高压 / 多数人正常」 |
| 好感均值 39.7（目标 45–65） | 压力活跃后 `M_state` 的正面压制仍在起作用 | ⏳ 待微调：`M_state` 的 40–70 区间系数，或好感增益 |
| 信念误差 ~7–9 | 信念滞后于真值（关系一直在变） | 可接受（「人心隔肚皮」），若过大再调 `eta0_*` |


## 约定

书包界面截图：`godot --path . --script tools/capture_backpack.gd` 使用真实教室与生产面板，输出 `tools/out/backpack/actual-inventory.png`（真实开局库存）和 `owned-book.png`（仅 UI 预览一本书）。素材与接线说明见 [书包界面说明](../docs/art/concepts/backpack/README.md)。

群体圈层截图：`godot --path . --script tools/capture_activity_rings.gd` 在独立截图实例注入三组真实会话（薄荷绿／淡紫／浅橙）与两个独立人物，使用生产圈层组件与真实教室输出 `tools/out/activity_rings/classroom.png`。需要图形渲染，用于检查融合边界、地砖透出与分组异色。

行为符号气泡截图：`godot --path . --script tools/capture_behavior_particles.gd` 使用实际教室、人物与生产气泡组件，在独立截图实例注入六类公开行为，输出 `tools/out/behavior_particles/classroom.png`。需要图形渲染，不能用 `--headless` 代替视觉检查。

桌椅结构小样：`build_school_desk_sample.gd` 从 `data/ui/school_desk_sample.json` 烘焙独立组件和展示场景；`capture_school_desk_sample.gd` 输出三视角引擎截图到 `tools/out/school_desk_sample/`。运行方式与验收记录见 [小样说明](../docs/art/concepts/school_desk_sample/README.md)。这两个工具不修改主教室或原材质资源。

- 脚本**只读** `data/`，不得写回；
- 输出统计必须包含随机种子，保证他人可复现；
- 新增脚本在本文件登记。

书架 3D 小样：`build_school_bookshelf_sample.gd` 从 `data/ui/school_bookshelf_sample.json` 烘焙组件和展示场景；`capture_school_bookshelf_sample.gd` 渲染两视角并导出 GLB。见 [小样说明](../docs/art/concepts/school_bookshelf_sample/README.md)。

人物移动／坐下试片：godot --path . --script tools/capture_school_student_motion_sample.gd 输出真实引擎帧；py tools/package_school_student_motion_preview.py 封装 GIF；godot --headless --path . --script tools/verify_school_student_motion_sample.gd 校验移动、实际座位锚点与坐姿稳定。场景：scenes/game/school_student_motion_sample_showroom.tscn。

纯2D固定俯视试片：godot --path . --script tools/capture_classroom_2d_motion_sample.gd；py tools/package_classroom_2d_motion_preview.py 封装实录GIF；godot --headless --path . --script tools/verify_classroom_2d_motion_sample.gd 校验纯2D节点、固定视野与落座保持。

Blender 书架小样 v2：`build_school_bookshelf_blender.py` 由独立 JSON 配置生成可编辑 `.blend`、木纹贴图、GLB 与 Cycles 预览；`capture_school_bookshelf_blender.gd` 直接读取 GLB 进行尺寸检查和实机截图。见 [Blender 小样说明](../docs/art/concepts/school_bookshelf_blender/README.md)。

教室逐件优化首件课桌：`build_school_desk_blender.py` 生成可编辑源工程和按材质合为 4 网格的 GLB；`capture_school_desk_blender.gd` 验证独立小样与临时教室替换，保留座位标记和碰撞。[分件队列](../docs/art/concepts/classroom_blender_rollout/README.md) / [课桌验收](../docs/art/concepts/classroom_blender_rollout/01_desk/README.md)。

人物 3D 基础小样：`build_school_student_blender.py` 生成可编辑人物与 18 骨蒙皮 GLB，并进行上臂变形检查；`capture_school_student_blender.gd` 校验引擎骨架和身高，渲染正侧面与课桌同框。[人物说明](../docs/art/concepts/school_student_blender/README.md)。

暖色教室与窗户：build_classroom_window_blender.py 生成窗户与复用盆栽 GLB；bake_classroom_window_assets.gd 烘焙为原生共享场景；当前教室美术配置直接使用组件。capture_classroom_art.gd 新增 --view=window 近景截图选项。[验收说明](../docs/art/concepts/classroom_warm_windows/README.md)。

对话气泡：`build_chat_bubble_blender.py` 从 `data/ui/chat_bubble_blender.json` 渲染头顶气泡的 pop（10）/ idle（9，循环）/ fade（5）序列帧与 512² 静帧到 `assets/textures/ui/speech_bubble/`；拼版预览、可编辑 `.blend` 与 `build_report.json` 写在本目录同级的小样目录。[小样说明](../docs/art/concepts/chat_bubble/README.md)。无描边版本在浅背景上不可辨，故资产统一带墨线；**本机 Blender 只启用 EEVEE（无 Cycles）**，脚本按配置选引擎、不可用时回退并在报告里标记，既有 `build_*_blender.py` 写死的 CYCLES 在本机跑不了。

行为符号位图字形：`build_symbol_bitmaps_blender.py` 从 `data/ui/behavior_particles_blender.json` 把闲聊符号（`?` `!` `★` `~`）烘焙成立体白字形贴图到 `assets/textures/ui/behavior_particles/`；运行时经 `data/ui/behavior_particles.json` 的 `bitmaps` 字段按各自 style 配色 modulate，**字段为空或贴图缺失即回退字体字形**（可撤回开关）。实测在默认 `font_size 34` 下立体感不可见，见 [符号气泡说明](../docs/art/concepts/behavior_particles/README.md)。


左上角时间／首次周考卡片截图：godot --path . -s tests/integration/capture_time_card.gd 使用真实教室和真实均分，输出 tools/out/time_card 中 1920×1080、1280×720 的教室及卡片截图，不修改正式存档。见 [验收说明](../docs/qa/时间周考卡片验收-2026-10-14.md)。

风险关注卡片截图：`godot --path . --script tools/capture_risk_attention.gd` 在独立实例登记真实风险事件并结算，输出空状态、三类风险与详情在不同横屏尺寸的实机图到 `docs/art/concepts/risk_warning_20261016/`。夹具只用于截图，不进入正式开局。见 [验收说明](../docs/qa/风险关注卡片验收-2026-10-16.md)。
