# 教室物件细化第一批（2026-10-12）

根据已确定的暖色教室概念图，直接接入实际入口 `scenes/game/classroom3D.tscn`：

- 后墙五组米白矮柜，蜂蜜木色台面；四门模块带门缝、拉手、脚座与倒角。隐藏旧高柜和旧矮柜的表现节点，保留既有碰撞与导航。
- 右后方阅读书架复用已完成的 Blender 书架 v2，含原书本与盆栽。几何和材质保留，193 个网格按材质合为 12 个，避免逐本书增加绘制调用。
- 柜顶两组文件盒、书本叠放与作业托盘；另外复用两株原盆栽。
- 17 个座位的桌侧共享灰蓝书包，带前袋、拉链、提手和姓名贴；移除原桌面装饰配置中隐藏在人物背后的方块书包。
- 黑板下补粉笔槽、粉笔和板擦；清洁角移至左后方。挂钟新增完整刻度并避开原广播喇叭。

配置集中在 `data/ui/classroom_art.json`；新增家具建模参数在 `data/ui/classroom_furnishings_blender.json`。未改席位、人物资源、模拟规则或随机消费。

## 产物

- `after.png`：1920×1080 实机全景，隐藏界面供美术验收。
- `storage_detail.png`：后墙柜体与阅读角实机近景。
- `blender_preview.png`：新矮柜和书包的 Blender 独立预览。
- `classroom_furnishings_v1.blend`：可编辑柜体和书包工程；原书架的源工程仍为 `../school_bookshelf_blender/school_bookshelf_blender_v2.blend`。
- `build_report.json`：网格、三角形与 GLB 体积；`capture_report.json`：冻结场景的渲染采样。
- `assets/models/classroom_furnishings/`：三件 portable GLB。运行时使用 `scenes/components/` 下的三个原生 PackedScene，网格、材质及书架纹理嵌入场景，复用同一资源。

## 重建

```powershell
& E:/blender/blender.exe --background --factory-startup --python tools/build_classroom_furnishings_blender.py
& <Godot.exe> --headless --path . -s tools/bake_classroom_window_assets.gd -- --config=res://data/ui/classroom_furnishings_blender.json
& <Godot.exe> --path . -s tools/capture_classroom_art.gd -- --label=furnishings_after --clean
```

脚本在 Blender 5.2.2 LTS 使用 EEVEE。家具按材质合并：矮柜 5 个网格 / 3760 三角形，书包 4 个网格 / 1880 三角形，复用书架 12 个网格 / 37864 三角形。

## 验证

Godot 4.7.2，种子 20261011、难度 2、17 人，冻结模拟截图。优化后全景 1039 次绘制调用；首次直接导入原书架为 1401 次。采样平均帧耗时约 1.90 ms，仅表示本机冻结画面的渲染结果，不作为动态游戏性能保证。

教室回归 8 项、137 个断言通过；覆盖模型接入/重建、席位旁书包位置、通道站点、障碍几何、模拟 RNG、人物拾取体与窗帘边界。配置校验、内核单测、公式对拍通过。独立只读审查未发现本批范围内可操作缺陷。

近景检查发现原装饰组装器将非均匀缩放应用于旋转后的世界轴，导致挂钟压扁。已改为先局部缩放再旋转，并验证回归测试在修复前失败、修复后通过。无头渲染器不能回读 MultiMesh 变换，回归检查实际组装器生成的 CPU 绘制数据，另以真实渲染截图验收。

下一批仍需细化椅背、公告栏与门框等物件；本批完成后墙储物与阅读区，并改善桌侧生活细节。
