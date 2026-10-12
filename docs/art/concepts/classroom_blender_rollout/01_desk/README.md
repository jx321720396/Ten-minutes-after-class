# 第一件：学生课桌 Blender v1

2026-10-12。对应整室概念图里的暖木色单人课桌。

## 交付与查看

- `school_desk_blender_v1.blend`：原生可编辑工程，保留木纹、倒角修改器、管材和桌斗的独立物件。
- `blender_preview.png`：Blender Cycles 实际渲染。桌面示意书本只用于此预览，没有导入课桌 GLB。
- `godot_comparison.png`：同一 Godot 光照下的比较，画面左边为新版，右边为原项目课桌；椅子隐藏以便比较。
- `godot_preview.png`：新版独立实机图。
- `classroom_before.png`、`classroom_after.png`：同一冻结教室实例、同一镜头，换桌前后对比。
- `assets/models/school_desk/prop_school_desk_blender_v1.glb`：净课桌，包含木纹贴图与材质，按木板/钢材/胶脚/螺钉合为 4 个网格。
- `build_report.json`、`godot_report.json`：生成与引擎验证记录。

桌面宽 0.66 m、深 0.46 m、厚 0.04 m，中心高度 0.74 m，与既有组件一致。侧挂钩略超出桌面宽度，整体宽约 0.686 m；正式接入时需在通道、挂包和碰撞验收中考虑该突出部件。原点在地面中心，GLB 为 Y 向上、正面朝 -Z；Blender 工程为 Z 向上、正面朝 +Y。

改进：圆角桌面、与书架统一的克制暖木纹、真实开放桌斗、圆钢管支撑、低光泽金属、胶脚和曲线挂钩。源文件保留独立部件；导出时使用复制网格应用修改器并按材质合并，不破坏编辑结构。

## 复现

参数：`data/ui/school_desk_blender.json`。木纹复用本次原创书架纹理，不依赖第三方模型。

```powershell
& 'E:/blender/blender.exe' --background --factory-startup --python tools/build_school_desk_blender.py
& 'C:/Users/极星/Desktop/Godot_v4.7.2-stable_win64.exe' --path . --script tools/capture_school_desk_blender.gd
```

验证：Blender 5.2.2 生成与渲染成功；Godot 4.7.2 导入得到 4 个网格，桌面上沿含螺钉约 0.761 m。临时教室样本为固定种子、中等难度，替换了 17 张桌子的外观；`StandSpot`、`SitPoint`、导航碰撞的变换与形状保持不变并经断言检查。

## 当前范围

课桌小样与临时整室预览已完成。主场景文件没有被保存或替换，椅子、人物、布景仍使用当前项目版本；不能把整室预览视为已经实现整张概念图。后续首先优化椅子，再完成柜子、黑板、窗帘等部件，最后统一布景和光照。
