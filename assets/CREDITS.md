# 第三方资源登记（CREDITS）

> 状态：生效 ｜ 维护者：全体 ｜ 最后更新：2026-10-06
> 规则：**未在本文件登记的第三方资源禁止合入仓库**（见 [`README.md`](README.md)、[`../CONTRIBUTING.md`](../CONTRIBUTING.md) 第 6 节）。

## 登记表

| 资源 | 类型 | 作者 / 来源 | 链接 | 许可 | 需署名 | 使用位置 |
|---|---|---|---|---|---|---|
| 高中男生站姿小样 v1 | 透明人物立绘 | 团队自制（内置 image_gen 生成与透明背景整理） | 本仓库 | CC BY 4.0 | 是 | `assets/textures/characters/samples/school_student_male_standing_v1.webp`；源图与提示词见 `docs/art/concepts/school_student_sample/` |
| 霞鹜文楷 Regular | 字体 | LXGW / Klee Project Authors | https://github.com/lxgw/LxgwWenKai | OFL-1.1 | 保留版权与许可 | 全游戏动态文字；`assets/fonts/lxgw-wenkai/`，许可见 `OFL.txt` |
| Classroom（教室 3D 场景） | 3D 模型（glTF 2.0） | Zeps3D | https://sketchfab.com/3d-models/classroom-7f981d3e0b6445108d684abf3f2fd4ab | CC BY 4.0 | 是 | 课间教室场景 `assets/models/classroom/`（许可原文 `LICENSE-classroom.txt`） |
| 教室像素贴图 ×7（`assets/textures/classroom/`） | 贴图 | 团队自制（AI 生成 + 手工修整） | 本仓库 | CC BY 4.0 | 是 | 3D 教室场景材质：地砖/墙裙/上墙/黑板报/软木板/纸张/窗帘 |
| `scene_classroom_wood.png`（原教室木纹 32×32） | 贴图 | 团队自制（AI 生成 + 手工修整） | 本仓库 | CC BY 4.0 | 是 | **当前未被引用**（讲台 / 门已改用下面的程序化板面），留作备用；要用回需跑 `tools/gen_classroom_textures.py --target wood-normal` 生成配套法线 |
| 木纹板面（`scene_classroom_wood_plank.png`） | 贴图 | 团队自制（AI 生成后裁切：384×384 源图取中间 256×256，避开右下角平台水印；源图未入库） | 本仓库 | CC BY 4.0 | 是 | 教室木纹板面：课桌（`mat_wood_desk.tres`）与讲台 / 门 / 教室门叶（`mat_wood.tres`）共用；另用于 `school_desk_chair_sample.tscn` 的原创几何小样 |
| 角色立绘 ×18（`assets/textures/characters/`） | 贴图 | 团队自制（AI 生成 + 手工修整） | 本仓库 | CC BY 4.0 | 是 | 课间教室的人物立绘：8 性格 × 男女 = 16 张（NPC 用），加`主角男`/`主角女` 2 张（玩家用） |
|  |  |  |  |  |  |  |

> 说明：上表首行为格式示例，**使用前请核实许可条款**；未实际引用的资源请删除该行。

## 许可类型速查

| 许可 | 商用 | 需署名 | 备注 |
|---|---|---|---|
| OFL-1.1 | ✅ | ✅ | 字体常用，需保留许可文件 |
| CC0 / Public Domain | ✅ | ❌ | 最宽松 |
| CC BY 4.0 | ✅ | ✅ | 需标注作者与来源 |
| CC BY-NC 4.0 | ❌（禁商用） | ✅ | **参赛作品谨慎使用** |
| MIT / Apache-2.0 | ✅ | ✅ | 代码/工具常用 |
| 来源不明 | ❌ | — | 禁止入库 |

## 维护流程

1. 引入资源时**同 PR 内**更新本表；
2. 将许可原文放入资源所在目录（命名 `LICENSE-<资源名>.txt`）；
3. CI 与人工评审都会检查本表与资源的对应关系（提交清单第 3 节）；
4. 若某资源许可变更或被移除，在本表留一行"已移除"记录（含日期与原因），不要直接删除历史痕迹。

人物动作试片：assets/textures/characters/samples/school_student_walk_v1.png 与 school_student_sit_v1.png，2026-10-12 使用内置 imagegen 基于同一男生站姿生成。提示词、选用记录与局限见 docs/art/concepts/school_student_motion_sample/README.md。

纯2D俯视小样：assets/textures/samples/classroom_2d/background_v1.png 与 student_motion_v1.png，2026-10-12 内置 imagegen 生成。提示词与修正记录见 docs/art/concepts/classroom_2d_motion/README.md。

## 2026-10-12 原创暖色窗户与复用盆栽

assets/models/classroom_window/ 与 scenes/components/school_window_warm.tscn 为项目内 Blender 程序建模窗户、滑轨、窗台、窗帘；school_potted_plant.tscn 从本项目原创书架工程提取 30 个原盆栽物件并共享复用。无新增第三方模型或纹理。源工程、生成脚本与来源记录见 docs/art/concepts/classroom_warm_windows/README.md。

## 2026-10-12 原创教室矮柜与书包

`assets/models/classroom_furnishings/` 的矮柜和书包由项目内 Blender 脚本建模；书架复用本项目原创书架 v2，按材质合并网格，保留原书本、盆栽与纹理。无新增第三方模型或纹理。源工程和实机验收见 `docs/art/concepts/classroom_furnishings/README.md`。

## 2026-10-12 书包界面插画

`assets/icons/actions/backpack.svg` 为本项目原创线条图标，与百科全书及推理板图标使用相同笔画风格；纸纹复用本项目现有 UI shader。

`assets/textures/ui/backpack/` 由内置 imagegen 根据本聊天书包概念图方向生成。空包为移除物品的透明编辑版本，物品层保留书、MP3、零食的独立透明轮廓。无第三方品牌。提示词和使用方式见 `docs/art/concepts/backpack/README.md`。

## 2026-10-12 人物全身立绘第一版

assets/textures/characters/fullbody_v1/ 共 26 张，由内置 imagegen 根据本聊天原创纸张推理板概念图的校园插画方向生成，包含 24 名 NPC 和男女主角。来源、角色映射及使用边界见同目录 README.md、manifest.json。尚未接入游戏。

人物简化小样：assets/textures/characters/simple_samples/char_01_body_simple_v1.png，2026-10-12 内置 imagegen 根据本项目陈阳全身稿进行风格转换生成。说明见同目录 README.md，尚未接入游戏。

人物方向动作对比：assets/textures/characters/motion_compare_v1/ 的 Q 版与正常比例陈阳图集，2026-10-12 内置 imagegen 以本项目原创人物稿生成。每套 32 帧，方向索引、动作预览及生成局限见同目录 README.md、frames.json、index.html。尚未接入游戏。
