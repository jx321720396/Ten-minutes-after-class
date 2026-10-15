# 当前教室视角下的正面行走预览

classroom_front_walk.gif：实际 classroom3D 场景、当前监控相机与界面，陈阳从中央过道后方向前行走 5 秒。其余同学显示学习姿态，桌椅与材质使用真实场景深度；没有调整相机位置、朝向、投影或视野。

静帧 classroom_walk_000.png、classroom_walk_060.png、classroom_walk_119.png 对应移动起点、中途、终点。

参数：data/ui/samples/chenyang_classroom_walk.json。复现：godot --path . -s tools/art_samples/capture_chenyang_classroom_walk.gd。原始 120 帧保存在 tools/out/chenyang_classroom_walk_frames/；逐帧确认相机变换及 FOV 未改变。沿用已验证的连续网格与步行算法，未接入正式导航或替换角色资源。GIF 到终点后重播起点。
