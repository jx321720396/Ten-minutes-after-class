# 坐姿背影 v1

16张1024×1536 RGBA图片，内置 imagegen 逐人参考 idle_seated_v1 生成；角色单独坐姿，无桌椅，保留原校服和发型。生成提示及来源见 generation.json。

每人的 idle_back 与 idle_back_layout 位于 data/ui/student_poses.json，前后桌真实会话复用共同活动朝向，空闲坐姿转背，不替换学习姿态。分层坐姿的头顶、坐骨和脚底独立校正，椅子沿用场景。

全员预览：`godot --path . --script tools/capture_seated_groups.gd -- seated_catalog`。真实场景：省略 seated_catalog，输出到 tools/out/group_facing/。
