# 全班趴桌睡觉贴图

2026-10-18，main-mobile。使用内置 imagegen，逐人以 idle_seated_v1 为身份、校服与下半身位置参考，生成 16 张独立趴桌睡姿：上身前倾，闭眼，脸颊枕在交叠双臂上。画面不含桌椅、枕头、文字或睡眠符号，使用场景已有桌面。

## 实装

资源位于 assets/textures/characters/sleep_seated_v1/，manifest.json 保存人物、参考与源图。透明 PNG 仅转码 WebP q90，无缩放或绘图处理，原图保留在生成目录。

student_poses.json 将 sleep 活动绑定独立素材，sleep_layout 配置桌面前景及身体深度；前景沿相机射线对齐，保持头部和手臂在桌面前方，也参与人物点击检测。现有预加载与姿态切换直接复用；睡觉不使用聊天背影，醒来和离座恢复相应姿态。仅改表现，不修改内核、睡眠收益或随机序列。

## 生成提示词

Use case: identity-preserve edit. Edit the original seated student sprite into SLEEPING FACE DOWN ON FOLDED ARMS at their classroom desk. Preserve exact identity, hairstyle, glasses/hair accessories, blue-white Chinese school tracksuit, gray trousers, sneakers, anime rendering and original 1024x1536 transparent canvas. Keep original seated legs, hips, knees and feet at EXACT original positions; feet fully visible. Bend torso far forward naturally, rounded shoulders, head LOW resting directly on two horizontally crossed forearms. Eyes shut, peaceful relaxed face turned slightly sideways, cheek touching sleeve, visibly asleep. Both forearms form a horizontal cushion at canvas y=620..725; their underside lies on an invisible desk plane at y=730. Crown of head around y=380..450, cheek at y=620; upper canvas above head EMPTY transparent. This is a slumped forward nap, NOT upright seated dozing. Remove all books and pens. No visible desk or chair: existing 3D game desk will supply surface. Single full seated character only, no pillow, bed, accessories, text, Z symbols, effects, background, floor shadow or glow. Genuine alpha transparent background. Anatomically correct arms, hands and head contact, same scale and lower body calibration.

## 验收

tests/unit/test_sleep_seated_pose.gd 覆盖 16 人唯一且可加载的贴图、预加载、桌面前景、退出与其他活动切换，以及镜头投影刷新、桌面深度与点击命中。tools/capture_snack_seated.gd -- --sleep 在独立真实教室夹具检查 16 人姿态、站姿隐藏、成绩与 RNG，并输出两种分辨率截图，不写玩家存档。

睡姿、聊天、朝向、零食、音乐和阅读共 16/16 测试、1348 项断言通过；实景 36 项检查通过，人工核对 classroom_sleep_1280.png 与 classroom_sleep_960.png。配置 190 项、字体覆盖、格式及静态检查通过。16 张素材共 1,963,368 字节（约 1.87 MiB）。各人的 desktop_contact_y 保存手臂底边标定位置，split_y 与下半身高度补偿对应配置。

Godot 验收退出仍有既有资源释放警告，退出码为 0；未导出 APK。
