# 陈阳分件活动小样

以已确认的「角色拆分与动作概念」生成，使用内置 imagegen；预览用途，不绑定正式演员。

- 原始图集：chenyang_parts_atlas_v1.png。保留生成文件，不做 Python 修图。
- 修整图集：chenyang_parts_atlas_v2.png。肩部覆盖为完整衣料，裤腿连接端减少横向接缝。
- 15 个部件：头、躯干、骨盆、左右上臂、左右前臂、左右手、左右大腿、左右小腿、左右鞋。
- 裁切区域、父子关节、米制尺寸、重叠锚点与示例动作全部在 data/ui/samples/chenyang_parts_sample.json。
- Godot 拼装脚本：tools/art_samples/chenyang_parts.gd。AtlasTexture 仅定义源区域，各关节控制独立 Sprite3D；素材不烘焙成整人动作帧。
- 膝盖使用单向渐变覆盖，在保留大腿底图的前提下减弱小腿上缘；仍需在正式骨骼形变阶段精修衣褶连续性。
- 复现：godot --path . -s tools/art_samples/capture_chenyang_parts.gd。
- 输出：docs/art/concepts/modular_student_sample_20261015/，包括实际教室截图和动态预览；72 张渲染中间帧位于 tools/out/modular_student_sample_frames/。

当前只验证正面自然站立、轻微呼吸、聊天摆臂及原地迈步。学习姿态、由站转坐、侧面／背面动作需要相应部件形变或替换素材，不用旋转正面贴图冒充完整动作系统。未改正式 16 人接线、导航或模拟内核。

生成提示要点：陈阳同一发型和蓝白校服；正面略俯视；透明图集；头部端正、双手离开口袋；各肢体沿纵向绘制；关节完整绘制隐藏重叠；无文字、无背景、无桌椅。第二轮只修整肩、肘、腕、膝的覆盖端，保留角色身份及部件布局。
