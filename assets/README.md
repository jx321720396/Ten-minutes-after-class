# assets/ —— 资源目录规范

> 状态：生效 ｜ 维护者：美术 / 音频 ｜ 最后更新：2026-10-04

## 目录结构

```
assets/
├─ icons/            应用与界面图标（icon.svg 为项目图标）
├─ textures/         贴图
│   └─ clueboard/    线索板（推理板）素材：粉笔、板擦、板面
├─ audio/
│   ├─ bgm/          背景音乐（OGG）
│   └─ sfx/          音效（OGG / WAV）
├─ fonts/            字体（含许可文件）
└─ CREDITS.md        第三方资源登记（必须维护）
```

新增子目录需在 PR 中说明；禁止在 `assets/` 根目录散落文件。

## 命名约定

`类别_对象_变体[_状态].扩展名`（全小写蛇形）：

| 类别 | 示例 |
|---|---|
| 界面 | `ui_btn_primary_hover.png`、`ui_panel_report_bg.png` |
| 角色 | `char_06_portrait_happy.png`、`char_06_body_base.png` |
| 场景 | `scene_classroom_desk_set.png` |
| 图标 | `icon_emotion_angry.svg` |
| 音效 | `sfx_chalk_write_01.wav`、`sfx_paper_pass_01.ogg` |
| 音乐 | `bgm_break_loop_a.ogg`、`bgm_class_tense.ogg` |

- 序号用两位数字（`_01`、`_02`），便于排序。
- 变体用于同素材不同状态（`_hover` / `_press` / `_disabled`）。

## 导入与体积规范

- **分辨率**：贴图按 1× 设计分辨率（1920×1080 基准）产出，不做 2× 冗余；需要缩放的由 Godot 处理。
- **过滤**：项目当前 `default_texture_filter = 0`（Nearest）。若美术风格改为非像素风，需同步修改项目设置并在 PR 中说明。
- **压缩**：静态 UI 用 PNG / WebP；照片类用 JPG；避免未压缩 BMP/TGA 入库。
- **体积**：单张贴图 ≤ 1 MB；单条音效 ≤ 200 KB；BGM 单曲 ≤ 3 MB。
- **图集**：同屏出现的多个 UI 元素应打包为图集，减少 draw call（移动端性能敏感）。
- **.import 文件**：Godot 生成的 `*.import` **需要提交**（团队导入设置一致），`.godot/` 缓存不提交。

## 第三方资源（强制）

任何非原创资源必须：

1. 在 [`CREDITS.md`](CREDITS.md) 登记：名称、作者、来源链接、许可协议、是否需署名；
2. 许可文件放入 `assets/fonts/` 或对应子目录（如 `LICENSE-<资源名>.txt`）；
3. 商用许可不明或不允许的资源**禁止入库**。

## 许可与合规

- 参赛作品要求可追溯的素材来源，登记不全的资源视同缺陷（见 `../docs/production/比赛提交清单.md` 第 3 节）。
- 涉及真实人物肖像、商标、影视截图的素材一律禁止。
