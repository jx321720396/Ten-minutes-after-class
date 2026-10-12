# 对话气泡小样（Blender）

> 状态：**资产与工具链已入库；接线未做**（2026-10-12 用户裁定：只入库资产与工具链）
> 生成：`blender --background --factory-startup --python tools/build_chat_bubble_blender.py`
> 配置：[`data/ui/chat_bubble_blender.json`](../../../data/ui/chat_bubble_blender.json) ｜ 资产：[`assets/textures/ui/speech_bubble/`](../../../assets/textures/ui/speech_bubble/)
> 预览（本目录 `blender_preview.png`，24 帧拼版：pop / idle / fade 顺序，从左到右、从上到下）

## 这是什么

替换/补齐**头顶对话气泡**的外观与动画。起因是用户反馈「项目里的气泡看着很生硬」。

现状定位（三条，都在代码里可查）：

| 现状 | 出处 |
|---|---|
| 现在的头顶气泡只发**符号粒子**，且明说「不表示聊天内容」 | `scripts/ui/chat_activity_bubble.gd`、CHANGELOG 2026-10-12 |
| 那个无字对话气泡**从未被实例化** | `scenes/components/speech_bubble.tscn` 全仓无引用 |
| 它的动画是 `pop_scale 1.3` → 停留 → **缩放到 0** | `scripts/ui/speech_bubble.gd` 的 `show_bubble()` |

「生硬」的三个实际来源：**几何硬边**（纯代码圆角矩形 + 硬描边）、**缩放到 0**（没有回弹、没有形变）、**节奏均匀**。

## 设计要点

1. **轮廓**：圆角矩形（14 段/角的密折线）+ **两段二次贝塞尔「弯刀尾」**——不是直线三角，所以尾部没有折角。
2. **动画支点 = 尾巴尖**：物体原点就在尾巴尖，弹入是**等比长大 + `easeOutBack` 过冲**（`pop`），不是缩放归零。
3. **淡出**：以「缩小 + 上浮」为主，只在最后两帧做 alpha 消失。
   > ⚠️ **踩过的坑（接线的必须知道）**：主体一旦半透明，**贴在它背后的墨色描边外壳就透出来，气泡整块变深灰**。所以淡出不能整段用 alpha，且描边的 alpha 要按 `ink_alpha_power` 提前退出。
4. **配色**：`view_transform = Standard` —— Blender 默认的 **AgX 会把白色压成灰**；材质用微暖纸白 + 墨色描边，与项目纸感 UI 同族。
5. **无描边版本不可用**：试过不带墨线的柔和版，在白底与教室浅色背景上**几乎看不见**，故资产统一带墨线。

## 帧与锚点

| 段 | 帧数 | 文件 | 播放建议 |
|---|---|---|---|
| `pop`（弹入） | 10 | `pop_00.png` … `pop_09.png` | 一次性播放，约 0.3–0.4 秒 |
| `idle`（呼吸） | 9 | `idle_00.png` … `idle_08.png` | **循环**（曲线用 `1 − cos` 一个周期，首尾姿态一致） |
| `fade`（淡出） | 5 | `fade_00.png` … `fade_04.png` | 一次性播放，约 0.2 秒 |
| 静态 | 1 | `static.png`（512²） | 可直接当普通贴图用 |

- 序列帧分辨率 **256²**，静帧 **512²**，透明底（RGBA）。
- **锚点：尾巴尖固定在画面 `(0.2872, 0.1426)`**（归一化，从左下起算）——接线时把该点对准人物头顶即可。数值可在 `build_report.json` 的 `anchor_tail_tip_normalized` 复查。
- 帧率未写进资产（由 Godot 端定）。

## 接线时的第一个障碍（务必先看这条）

`scripts/ui/speech_bubble.gd` 是 **`Node2D`**，而人物是 `Sprite3D`——**挂在 3D 人物节点下不会渲染**，这正是它一直没被实例化的原因。两条可行路径：

1. **`Sprite3D` billboard**（推荐）：`AnimatedSprite3D` + `SpriteFrames` 播放上述三段，`BILLBOARD_FIXED_Y`，与 `classroom_actors.gd` 的纸片人一致；
2. **沿用 `chat_activity_bubble` 的做法**：`CanvasLayer` + `unproject_position` 把 3D 锚点投到 2D 屏幕再画 `Control`。

两条路都要遵守既有纪律：**只读内核**（气泡只反映真实会话/行为，不改任何矩阵、不消费模拟随机数）。

## 工具链与已知限制

- 脚本：[`tools/build_chat_bubble_blender.py`](../../../tools/build_chat_bubble_blender.py)（参数全部外置，脚本无魔法数字）
- **本机 Blender 没有 Cycles**（`RenderSettings.engine` 枚举里只有 `BLENDER_EEVEE`，`--factory-startup` 与否都一样），而现有的 `tools/build_*_blender.py` 全部写死 `CYCLES`——**那批脚本在本机跑不了**。本脚本按配置选引擎、不可用时回退，并把这个事实写进 `build_report.json` 的 `engine_fallback`。
- `.blend` 源工程与 `build_report.json` 在本目录，便于复查与二次编辑。
- GLB（网格 + shape key 形变）已验证可行（`morph_targets=2` + `weights` / `scale` 两条动画），但**本批未入库**：配置项 `outputs.export_glb` 默认 `false`，需要时再打开。

## 验收

1. `pop` → `idle` → `fade` 三段连续播放，气泡从尾巴尖"长出来"再收回，无折角、无跳变。
2. 淡出段**不出现整体变灰**（即描边未透出）。
3. 透明底、无白边；放到教室浅色与深色背景上都能看清。
4. 资产不参与任何判定：把序列帧换掉不影响同种子模拟结果。
