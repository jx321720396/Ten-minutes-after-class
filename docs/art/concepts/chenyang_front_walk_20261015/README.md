# 陈阳正面行走小样

沿用确认后的完整人物透明贴图与连续网格，仅增加正面行走；没有再次拼接独立生成的腿部。角色实际沿世界 +Z 前进，相机正面跟随，地砖提供位移参照。落地阶段用根节点位移抵消脚部局部后移，抬脚阶段平滑向前摆动；手臂与对侧腿同步摆动，脚下阴影随抬脚减弱。

- 动图：front_walk_sample.gif，24 fps、60 帧、2 个完整步行周期、可循环。
- 静帧：walk_00.png、walk_08.png、walk_15.png、walk_23.png。
- 动作与捕获参数：data/ui/samples/chenyang_front_walk.json。
- 网格活动脚本：tools/art_samples/chenyang_front_walk.gd。
- 复现：godot --path . -s tools/art_samples/capture_chenyang_front_walk.gd。
- 原始帧：tools/out/chenyang_front_walk_frames/。

验证捕获中的所有网格顶点有限、三角形不翻面；连续落地帧的脚部世界位置误差小于配置容差。脚踝和膝部变形保持共享网格，无额外关节拼缝。仅为正面视觉小样，未接入正式演员、导航或行为逻辑；侧面和背面不在本次范围内。
