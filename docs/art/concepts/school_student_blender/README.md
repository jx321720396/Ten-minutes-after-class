# 校服人物 3D 基础模型 v1

日期：2026-10-12。使用 Blender 5.2.2 制作的真实三维人物几何，不是平面立绘或面向镜头的 Sprite3D。

## 交付

- `school_student_blender_v1.blend`：可编辑源工程，保留头部、五官、发束、校服、四肢、鞋与骨架的独立物件。
- `assets/models/school_student/char_school_student_blender_v1.glb`：合并为单一蒙皮网格、按材质分表面，包含 18 骨基础骨架。
- `blender_preview.png`：Blender Cycles 实际渲染。
- `godot_preview.png`、`godot_front.png`、`godot_side.png`：Godot 4.7.2 导入后的三视角实机截图。
- `godot_desk_scale.png`：与上一轮 Blender 课桌同框的实机比例验收。
- `build_report.json`、`godot_report.json`、`glb_verification.json`：生成、骨架与导出验证记录。

外观为短发学生、蓝白运动校服、白色运动鞋。比例约五头身；沿用现有站姿人物小样的 1.65 m 身高校准，实际含发束包围盒约 1.657 m。原点在脚底，GLB 为 Y 向上、正面朝 +Z；Blender 为 Z 向上、正面朝 -Y。

## 骨架与范围

基础骨架包含 Root、Hips、Spine、Chest、Neck、Head 与左右上臂/前臂/手、大腿/小腿/脚。手臂与腿部采用两骨插值权重，头部与鞋等附属件随对应骨骼；Blender 源文件保持可编辑结构，导出时仅合并临时副本。

生成时实际旋转左上臂骨骼并检查网格位移，确认蒙皮变形，再恢复中立姿态。Godot 导入验证了 18 根骨骼、1 个蒙皮网格和约定身高，并分别检查正侧面及桌面高度。

当前是站姿基础建模样板，五官、发型和服装仍使用简化几何。没有表情形变、手指骨骼、完整行走/坐下/交谈动画或正式角色行为接入；后续动画需要检查肩、肘、髋、膝的变形和椅子穿插。未替换现有生产人物。

## 复现

配置：`data/ui/school_student_blender.json`，固定种子；模型与材质为项目内原创。

```powershell
& 'E:/blender/blender.exe' --background --factory-startup --python tools/build_school_student_blender.py
& 'C:/Users/极星/Desktop/Godot_v4.7.2-stable_win64.exe' --path . --script tools/capture_school_student_blender.gd
```

日志位于 `tools/out/student_blender_build.log` 与 `tools/out/student_blender_godot.log`。此工作仅涉及独立美术样板，不修改内核、角色种子或玩法规则。
