# 全班坐姿聊天贴图

2026-10-18。在 main-mobile 实装 16 人坐姿聊天表现。检查已有资源后，旧 characters2.5D/quiet_female/chat 像素原型与现用画风不一致；缺少现用人物的正面聊天动作，因此仅补生成 16 张正面图。背向镜头全部直接调用各人的 seated_back_v1，不重复生成。

内置 imagegen 逐人以 idle_seated_v1 为编辑参考，保留身份、校服、坐姿、腿部及画布，使用微张嘴和自然抬手表现聊天。1024×1536 RGBA，原图仅转码 WebP q90，无缩放或合成，16 张共 2,270,810 字节。源文件、角色绑定及复用背影见 assets/textures/characters/chat_seated_v1/manifest.json。

## 接入

student_poses.json 的 activity_poses.chat 绑定 chat；back_pose_variants 将 idle/chat 映射至既有 idle_back。GroupFacingPresenter 继续决定朝向，离座使用原站姿；结束聊天恢复对应活动。AssetPreloader 预加载新动作及复用背影。仅表现与资源配置改动，不改变内核、关系、行为收益或随机序列。

## 提示词

Use case: identity-preserve edit. Edit the provided original seated student sprite into TALKING WITH A CLASSMATE while seated. Preserve EXACT character identity, face, hairstyle, glasses and hair accessories, blue-white Chinese school tracksuit, gray trousers and sneakers, original anime illustration style, warm neutral lighting. Full seated body with same legs, head position and feet placement on original 1024x1536 canvas. Subtle natural friendly conversational expression with mouth slightly OPEN MID-SENTENCE, not a big laugh. One hand raised at lower chest in a small relaxed OPEN-PALM conversational gesture, other hand resting naturally on thigh. Head slightly turned toward a neighboring classmate, do not change body framing. Clear readable speaking gesture, anatomically correct hands, no extra limbs. No book, phone, food, headphones, desk, chair, background, speech bubble, text, symbols, watermark or ground shadow. Single student only. Genuine alpha transparency, no opaque glow. Both shoes fully visible. Maintain seat calibration and character proportions.

## 验收

专项：tests/unit/test_chat_seated_pose.gd。覆盖全班独立正面资源、背影复用、朝向刷新、退出与其他活动切换。

实景：运行 tools/capture_snack_seated.gd -- --chat，在真实教室固定 16 人聊天夹具，检查姿态、可见性、成绩与 RNG，输出 classroom_chat_1280.png / classroom_chat_960.png；不写玩家存档。

结果：聊天、朝向、零食、音乐及阅读 5 个脚本共 14/14 测试、781 项断言通过；实景 36 项检查通过，两张截图人工核对。配置 190 项、两种字体覆盖、gdformat 与 gdlint 通过。Godot 实景进程退出有既有 ObjectDB/资源释放警告，退出码为 0。未导出 APK。
