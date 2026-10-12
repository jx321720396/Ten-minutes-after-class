# 当前教室：明亮暖色、窗户与复用盆栽

2026-10-12。用户要求停止 3D 人物试样，继续优化教室物件，并将概念图的明亮暖色落实到当前游戏教室。

## 已接入游戏入口

`scenes/game/classroom3D.tscn` 的既有 `ClassroomArt` 现在直接读取更新后的配置，生成三组窗户（滑轨、把手、窗台、折叠窗帘）与四个共享盆栽；从主菜单进入原教室即可看到，不需要切换到样板场景。

大面积绿色来自旧地砖、墙裙、柜体及补光。本轮将墙面改为奶油白、地面改为浅米色与克制的砖缝、墙裙改为浅暖灰、柜体改为暖灰白；黑板和植物保留局部绿色。原有桌椅木纹保持。太阳光从右侧窗户进入并投影，早/午/下午色彩仅依赖既有相位。

窗户沿用原窗洞 2.8×1.8 m 尺寸和原节点变换；窗帘的位置按实际墙柱的内表面验证，全部褶皱在室内，避免被墙体切成条纹。玻璃透明且不投影，窗框/帘布保留投影。新组件为纯视觉几何，不带碰撞。

## 文件

- `before.png` / `after.png`：实际教室，固定种子 20261011、默认 D3D12 Mobile、1920×1080、17 人、同一游戏镜头。
- `window_godot_detail.png`：实际教室中的窗户/窗帘/盆栽近景；此截图隐藏人物用于检查物件。
- `window_blender_preview.png`：Blender 原生窗户组合渲染。
- `classroom_window_warm_v1.blend`：可编辑窗户、窗帘与复用盆栽源工程。
- `assets/models/classroom_window/prop_window_warm_v1.glb`：7 材质网格的窗户组合，正面朝局部 -Z 以适配当前右墙窗洞。
- `assets/models/classroom_window/prop_potted_plant_reused.glb`：5 材质网格的盆栽，原点在盆底。
- `scenes/components/school_window_warm.tscn` / `school_potted_plant.tscn`：原生、内嵌几何与材质的可复用组件。
- `data/ui/classroom_art.json`：运行时配色、灯光、共享组件定位、近景截图视角。
- `data/ui/classroom_window_blender.json`：离线窗户几何、窗帘偏移和资源生成参数。

盆栽直接从已完成的 `school_bookshelf_blender_v2.blend` 抽取 CeramicPot、PotSoil、14 个 Stem 和 14 个 CurvedLeaf，共 30 个原始物件，没有重新设计或重生成叶片。三个窗台和讲桌共用同一原生场景，重建也复用缓存资源。

## 复现

```powershell
& 'E:/blender/blender.exe' --background --factory-startup --python tools/build_classroom_window_blender.py
& 'C:/Users/极星/Desktop/Godot_v4.7.2-stable_win64.exe' --headless --path . --script tools/bake_classroom_window_assets.gd
& 'C:/Users/极星/Desktop/Godot_v4.7.2-stable_win64.exe' --path . --script tools/capture_classroom_art.gd -- --label=warm-after-20261012 --clean
& 'C:/Users/极星/Desktop/Godot_v4.7.2-stable_win64.exe' --path . --script tools/capture_classroom_art.gd -- --label=warm-window-detail --clean --view=window
```

只需复现前两步才能重建资产；游戏运行直接加载原生组件，不依赖 Blender、GLB 运行时解析或导入器。导出预设为 `all_resources`，已有 JSON 包含项保留，组件中的几何和材质均内嵌。

## 验证与限制

Godot 专项 6 项测试、75 条断言通过。实际入口回归包含资产接入、共享盆栽、重建幂等、窗洞定位、窗帘避让墙柱、环境暖色、原障碍表/站点可走性、人物拾取体与内核 RNG 不受装饰影响。日志在 `tools/out/classroom_warm_tests_green.log`，快门禁和实机图报告另行保存。

新增太阳投影会增加渲染工作量。RTX 4060 Laptop 的固定镜头静态样本约从 1.60 ms 到 2.07 ms；统计在不同短时运行中采集，仅用于本机比较，不代表目标手机性能。阴影和相位灯光均可从配置调整。尚未做导出包或真机性能验收。

其它教室部件仍继续逐件优化，本次完成的是当前整体色彩/光照、窗户组合与盆栽复用；3D 人物试样未接入。

配置校验 313 项、Python 内核 61 项、公式对拍 11 项通过；相关格式/静态检查通过。独立只读审查未发现实质代码问题。全仓文档检查仍有既有“指标门未通过 / 待标定初值”记录导致的 1 项失败，本轮未改写那些机制状态记录。
