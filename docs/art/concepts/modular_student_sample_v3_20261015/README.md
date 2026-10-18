# 陈阳连续网格小样 v3

用户反馈旧版「怪异吓人」后，停止在独立生成的袖子、骨盆和裤腿之间反复调偏移。旧版各部件的衣褶、比例和受光不一致，硬旋转及透明渐变只能掩盖局部边缘，不能形成连续人体。

新版使用 imagegen 生成同一人物完整透明底稿，再由 Godot 单一连续三角网格变形。肩、肘、颈部用平滑权重过渡，膝盖和腰胯保持原画连续；轻微呼吸和低幅度示意采用同一张图，不引入新接缝。此轮不展示尚未成熟的走路动作。

- 自然站姿／轻微示意对照：parts_assembled_sample.png。
- 动图：continuous_motion_sample.gif，96 帧 Godot 渲染结果编码为 16 fps GIF。
- 教室实景：classroom_sample.png；近景 classroom_sample_close.png。
- 素材：assets/textures/characters/modular_sample_v1/chenyang_continuous_v3.webp。
- 关节位置、权重区域、网格精度和动作幅度：data/ui/samples/chenyang_soft_mesh_sample.json。
- 拼装及变形：tools/art_samples/chenyang_soft_mesh.gd。
- 重现：godot --path . -s tools/art_samples/capture_chenyang_soft.gd。
- 中间帧：tools/out/modular_student_sample_v3_frames/。

验证：所有帧每个顶点均为有限值，每个共享三角形保持正面积、不翻面；实际检查肩线、手腕、腰胯和膝部的连续性。脚部不参与当前动作。此代码仍为单人美术小样，未更改正式 16 人或模拟内核。侧面、大幅抬臂、学习和行走仍需要相应权重及动作设计，不能从本次小幅活动推断已经完成。

内置 imagegen 生成提示要点：基于已确认陈阳概念，完整自然站立、约七头身、双手自然垂放、肩膀放松、目光略偏向教室、蓝白校服及炭灰长裤，正面略俯视、统一柔和受光、透明背景；整个人一次绘制，肩肘腕和裤腿连贯，不生成分离部件或关节断面。后续动作由网格完成，没有 Python 修图。
