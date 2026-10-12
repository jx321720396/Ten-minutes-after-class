# 明亮暖色教室与可复用窗户 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan inline, task by task. Steps use checkbox (`- [x]`) syntax for tracking.

目标：将已获用户授权的明亮暖色概念落到当前 `classroom3D` 入口，完成右侧三组窗户/窗台/窗帘，并复用既有 Blender 盆栽。保留既有木纹、人物和全部玩法/移动几何。

## 文件边界

- `data/ui/classroom_art.json`：运行时配色、灯光、地砖缝、场景资产放置。
- `data/ui/classroom_window_blender.json`：离线窗户几何和资源生成参数。
- `tools/build_classroom_window_blender.py`：Blender 生成窗户、抽取书架盆栽，不修改书架源文件。
- `tools/bake_classroom_window_assets.gd`：GLB 烘焙为直接可加载的原生 PackedScene。
- `scenes/components/school_window_warm.tscn` / `school_potted_plant.tscn`：共享视觉组件，不带碰撞。
- `scripts/game/classroom_art.gd`：在已有装饰重建路径中增加配置驱动场景实例，缓存 PackedScene，避免重复导入。
- `tests/unit/test_classroom_art.gd`：新增实际场景资产接入、暖色和重建验证；保留现有几何/RNG 回归。
- `docs/art/concepts/classroom_warm_windows/`：可编辑源工程、同镜头前后实机图、验收记录。

## 执行

- [x] 保存旧美术配置与固定种子实际入口基线截图；识别绿色来源。
- [x] 写新增测试，先确认实际入口尚无窗户/盆栽场景实例且环境光偏绿时失败。
- [x] 完成 Blender 窗户（沿用 2.8×1.8 m 窗洞）、窗台与窗帘；从既有书架工程抽取原盆栽，按材质合并导出。
- [x] 烘焙窗户/盆栽原生组件，关闭玻璃投影；不引入碰撞。
- [x] 将场景实例纳入现有 rebuild，隐藏被替换窗户和旧窗帘，移除旧盆栽放置；暖色配色与相位光照集中于 JSON。
- [x] 跑专项 GUT、配置/内核/公式快门禁、相关 GDScript 格式与静态检查。
- [x] 同镜头实机检查明亮暖色、窗外可见性、人物可读性、光影与导航；只根据新证据调整。
- [x] 更新美术风格、资源来源与变更记录，交付实际入口截图和源模型。

## 执行记录

Ruling：直接修改用户当前工作区的既有美术接线，不建隔离 worktree — 本任务需要复用当前未提交的样板和场景；仅审查本任务文件和改动，保留其它工作。

Ruling：墙裙改为暖灰，深绿只留在黑板与植物 — 用户明确拒绝整室绿色偏色；保留概念图的小面积校园绿色，同时使大面积表面中性。

Ruling：玻璃不投影，窗框和窗帘投影；灯光只读已有相位 — 保留窗外视野与日光，不引入任何脚本化剧情或新的模拟规则。

完成记录：新增测试先在旧实现失败；最终 6 项/75 断言通过。定位浮点误差改为变换近似比较；定位窗帘穿墙后先补失败断言再调整室内偏移。实际入口与近景均已渲染检查。配置/内核/公式、专项格式与静态检查通过；check_docs 保留全仓既有标定记录失败，不伪造全绿。独立只读审查无实质代码问题。
