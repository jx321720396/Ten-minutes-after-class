# 正常比例人物帧动画实装小样

2026-10-13 调整：人物高度由 1.65 米缩至 1.32 米；行走 6→3 FPS、聊天 3→1.5 FPS。相机水平朝向与桌椅对齐，坐姿改用身体中心轴而不是鞋底像素中位数，并关闭坐姿 billboard。坐姿使用同一原图的上身/腿部两个 AtlasTexture 层，将腿部放到椅面前方，改善纸片与椅面的遮挡。行走终点改为桌椅旁，站立聊天不再落进椅子中；坐下仍是直接切换单帧，没有转身入座过渡。上述变更只影响独立美术小样。已重新通过 Godot 专项验证和渲染截图检查。

2026-10-12：使用陈阳正常比例透明图集，不使用 Q 版。独立运行 `scenes/game/normal_student_motion_sample.tscn`（编辑器 F6），会自动演示站立 → 侧向行走到桌椅 → 正面聊天 → 正面坐姿。上方按钮可切换动作和方向，重播按钮恢复自动演示。

## 范围与入口

- 场景：`scenes/game/normal_student_motion_sample.tscn`。
- 可复用人物组件：`scenes/components/normal_student_animation.tscn`；`play_pose(action, direction)` 选择表现状态，`automatic` 控制是否自动推进帧。
- 配置：`data/ui/normal_student_motion_sample.json`；13 个动画片段、29 个 AtlasTexture 帧，四方向站立/行走/聊天加正面坐姿。其他坐姿仅留在原图，未加入播放资源；请求任何方向的坐姿统一播放 `sit_front`。
- 固定正面相机，坐姿世界落点读取桌椅实际 `SitPoint`。每帧采用人物主体的实际裁切边界与脚底基线，排除等分网格带入的邻行头发碎片。SpriteFrames 管理帧资源，Sprite3D 按配置播放；共享原图，无需修改图片。

本次仅实装可运行美术小样，未替换主教室角色、外观表或内核行为；原图的行走接触姿态仍有重复，未新增坐下过渡帧。片段切换是展示流程，不是脚本化剧情，不参与本局时间或模拟结算。

## 验证

Godot 4.7.2 运行 `tools/verify_normal_student_motion.gd`，覆盖片段数、四方向行走切帧、仅正面坐姿、稳定坐姿和真实座位落点。运行 `tools/capture_normal_student_motion.gd` 在真实 OpenGL 渲染中输出站立、行走、聊天、坐姿截图。新脚本通过 gdformat 和 gdlint。

检验一：本次无玩法规则修改。动画组件仅读取外部表现状态，不依赖角色姓名、角色编号或模拟矩阵。
