# 暖木色书架 3D 小样

2026-10-12：按用户提供的教室参考与书架概念图制作的独立低多边形模型。宽 1.0 m、高 1.55 m、深 0.36 m（不含顶部摆件），正面朝 -Z，原点位于地面中心。三层开放格、30 本书、顶部盆栽和两本叠放书。属于美术试样，尚未替换主教室。

- 可复用组件：`scenes/components/school_bookshelf_sample.tscn`
- 展示场景：`scenes/game/school_bookshelf_sample_showroom.tscn`，在 Godot 中打开后按 F6 运行。
- 通用模型：`assets/models/bookshelf/prop_bookshelf_sample.glb`，含几何与材质，可导入 Blender / Godot。
- 数据：`data/ui/school_bookshelf_sample.json`，几何尺寸和材质配色集中于此。
- 实机截图：`tools/out/school_bookshelf_sample/sample.png`、`front.png`。

生成：`godot --headless --path . --script tools/build_school_bookshelf_sample.gd`

截图和 GLB 导出：`godot --path . --script tools/capture_school_bookshelf_sample.gd`（需要图形设备）。

已使用 Godot 4.7.2 生成组件、渲染两视角并导出 GLB，返回码均为 OK。风格小样使用纯色哑光材质；手绘木纹、细节贴图和最终教室光照仍需后续打磨。模型为项目内程序构造，无新增第三方模型资源。
