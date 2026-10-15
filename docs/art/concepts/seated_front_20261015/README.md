# 正面坐姿分层小样（2026-10-15）

本目录保留小样迭代及实装验收截图。正式入口已通过 ClassroomActors 配置接入；运行时素材位于 assets/textures/characters/seated_v1/，配置为 data/ui/student_poses.json。

当前版本：desk_preview_study_v5.png。使用 char_01_study_connected.png 的完整学习姿态，肩膀、肘部、手腕和双手来自同一张图。通过同图 UV 多边形划分桌前手臂和书本，禁止叠加旧独立袖子素材。

渲染顺序：椅子与地面 → 身体 → 桌子 → 同图的手臂与书本前景。身体在髋部使用连续纹理分段，桌上前景使用相同投影对齐。配置：data/ui/seated_front_preview.json；捕获工具：tools/capture_seated_front_preview.gd。

v4 及 study_arms_book.png 保留为历史试稿，存在袖子重复与断接，不作为当前方案。

当前仍为静态示意；不包含写字动画、正式课堂状态绑定或全班验证。

实装验收：runtime_classroom_study.png 为原相机的正式教室全景，runtime_study_close.png / runtime_idle_close.png / runtime_stand_close.png 为同场景近景（相机移近以避开前排遮挡，仅截图时隐藏名字牌）。捕获脚本为 tools/capture_runtime_student_pose.gd。状态数据由测试夹具设置，正式表现不写回活动或成绩。

运行时验证：6 个相关 GUT 脚本共 56 项测试／327 断言通过；新增测试覆盖坐姿头部、写字手和真实遮挡体拾取，格式／lint 与 Godot 资产导入通过。最终复跑离线快门禁时，其他并行工作的 tools/core_sim.py 存在尚未定义的 _invite_friends_pass / _find_partner，test_core 与 verify_formula 因此中断；本次未修改该内核文件。
