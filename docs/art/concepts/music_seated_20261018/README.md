# 全班坐姿听音乐贴图

2026-10-18。使用内置 imagegen，以每人的原始 idle_seated_v1 透明坐姿为编辑目标，逐人制作独立听音乐贴图。按用户修正采用小型白色有线耳塞；头戴式耳机的早期生成结果不导入项目。

## 最终提示词

Use case: identity-preserve edit. Edit the provided original seated student game sprite into discreetly LISTENING TO MUSIC AT THEIR CLASSROOM SEAT. IMPORTANT: tiny white WIRED IN-EAR EARBUDS only, like simple ordinary school-student earphones. Absolutely NO over-ear headphones, NO headband, NO ear cups, NO headset, NO large audio accessories. One small white earbud at visible ear, thin white earphone wire running discreetly along neck and into collar/pocket. One hand lightly adjusts the tiny earbud near ear with two fingers, never cupping the whole ear; other hand rests naturally on lap. Preserve exact character face, hairstyle, hair clips, glasses, blue-white Chinese school uniform, gray trousers and sneakers; same anime rendering and neutral warm light. Preserve original FULL seated front-view composition on 1024x1536 canvas, same head and feet placement and same leg pose, shoes fully visible. Relaxed subtle enjoying-music expression with softly open eyes. No phone, food, desk, chair, background, floor shadow, music symbols, text or watermark. Genuine alpha transparency, no opaque halo. One character only. Anatomically correct hands. Main visual cue must be tiny wired earbuds suitable for covert music listening in a classroom.

## 资产与接入

最终资产位于 assets/textures/characters/music_seated_v1/，逐人参考图、源文件与成品文件名登记在 manifest.json。原始 PNG 保留在 Codex generated_images 中。成品维持 1024×1536 和 alpha，通过 WebP 格式压缩入库，不缩放画布。

公开活动 listen_music 对应同名坐姿，由 data/ui/student_poses.json 的 activity_poses 与每人 binding 配置；复用已实现的姿态切换和后台预加载。仅在座且在场时使用，离座恢复站姿，活动结束按当前活动切回。贴图不影响内核与活动判定。

## 验收入口

- tests/unit/test_music_seated_pose.gd：每人的独立贴图、预加载、尺寸和姿态切换，以及听音乐／吃零食／普通坐姿的相互恢复。
- tools/capture_snack_seated.gd -- --music：独立进程运行全班听音乐夹具，检查显示、随机数与成绩不变，输出 classroom_music_1280.png 和 classroom_music_960.png；不保存玩家存档。

验收结果：听音乐 2/2、187 项断言通过，吃零食回归 2/2、123 项断言通过；GL 真实教室 36 项检查通过。已人工查看全体生成图及课堂截图，均为有线耳塞；配置 187 项、两套字体覆盖、格式与静态检查通过。16 张 WebP 共约 2.15 MiB。

