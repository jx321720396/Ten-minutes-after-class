# 第三方资源登记（CREDITS）

> 状态：生效 ｜ 维护者：全体 ｜ 最后更新：2026-10-06
> 规则：**未在本文件登记的第三方资源禁止合入仓库**（见 [`README.md`](README.md)、[`../CONTRIBUTING.md`](../CONTRIBUTING.md) 第 6 节）。

## 登记表

| 资源 | 类型 | 作者 / 来源 | 链接 | 许可 | 需署名 | 使用位置 |
|---|---|---|---|---|---|---|
| （示例）霞鹜文楷 | 字体 | lxgw | https://github.com/lxgw/LxgwWenKai | OFL-1.1 | 是 | UI 正文 |
| Classroom（教室 3D 场景） | 3D 模型（glTF 2.0） | Zeps3D | https://sketchfab.com/3d-models/classroom-7f981d3e0b6445108d684abf3f2fd4ab | CC BY 4.0 | 是 | 课间教室场景 `assets/models/classroom/`（许可原文 `LICENSE-classroom.txt`） |
| 教室像素贴图 ×7（`assets/textures/classroom/`） | 贴图 | 团队自制（AI 生成 + 手工修整） | 本仓库 | CC BY 4.0 | 是 | 3D 教室场景材质：地砖/墙裙/上墙/黑板报/软木板/纸张/窗帘 |
| `scene_classroom_wood.png`（原教室木纹 32×32） | 贴图 | 团队自制（AI 生成 + 手工修整） | 本仓库 | CC BY 4.0 | 是 | **当前未被引用**（讲台 / 门已改用下面的程序化板面），留作备用；要用回需跑 `tools/gen_classroom_textures.py --target wood-normal` 生成配套法线 |
| 木纹板面（`scene_classroom_wood_plank.png`） | 贴图 | 团队自制（AI 生成后裁切：384×384 源图取中间 256×256，避开右下角平台水印；源图未入库） | 本仓库 | CC BY 4.0 | 是 | 教室木纹板面：课桌（`mat_wood_desk.tres`）与讲台 / 门 / 教室门叶（`mat_wood.tres`）共用 |
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
