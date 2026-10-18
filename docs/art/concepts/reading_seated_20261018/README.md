# 全班坐姿竖书阅读贴图

2026-10-18。使用内置 imagegen，以每人的 idle_seated_v1 为身份和坐姿编辑目标，制作 16 张独立阅读贴图。书本双手竖持在胸前，书脊竖直，脸部完整可见；不采用桌面平放书本或写作业姿势。

## 五款共享封面

- botany: sage teal green cover, simple cream botanical leaf branch emblem, cream narrow border
- stars: deep navy blue cover, small gold constellation dots and crescent moon emblem, gold thin border
- mountains: warm ochre yellow cover, simple cream and rust mountain peak illustration with sun circle
- adventure: muted burgundy red cover, a small cream sailing ship emblem above two simple wave lines
- cat: ivory cream cover, simple orange curled sleeping cat emblem, muted orange lower band

首批 01–05 分别确定五种书本外观；其余 11 人把对应首批图作为第二张参考，仅复用书本与持书方向，身份仍取各自原坐姿。书款分配是资产配置，不参与行为、物品数量或阅读收益判定。成品与 book 对应登记在 assets/textures/characters/reading_seated_v1/manifest.json；books.json 保存五款封面定义。

## 提示词

Use case: identity-preserve edit. Edit image 1, the original seated student game sprite, into reading an UPRIGHT open paperback at their classroom seat. Preserve this exact person's face, hairstyle, glasses/hair accessories, blue-white school tracksuit, gray trousers, shoes, anime rendering, and full seated body/head/feet positions on the original 1024x1536 portrait canvas. Both hands naturally grip the lower outer edges of an open book held VERTICALLY at mid-chest, bottom at stomach level, top BELOW CHIN so whole face remains visible. Spine vertical, pages vertical, open covers visible facing viewer, student looking gently down at inside pages; NOT lying flat, NOT a horizontal notebook, NOT writing. Book about 22cm tall, 15cm wide per cover, opened at a slight V-angle. No readable letters or titles on cover. Book design: [books.json 中的对应 description].  Exact original seated legs and proportions; shoes completely visible. No desk, chair, background, shadow on floor, music accessories, phone, snack, effects, text or watermark. Real alpha transparent background. Single character, anatomically correct hands with no extra fingers. Do not make an opaque glow.

后续角色补充：Image 2 is ONLY the BOOK DESIGN and upright holding-pose reference: copy the exact book cover color, emblem, border, placement of motifs and open-book orientation from image 2, NOT its person's face or hair. Use ONLY image 1 for student identity.

## 接入和验收

通过 data/ui/student_poses.json 为公开活动 read_book 配置同名姿态和各人贴图，复用现有后台预加载、坐站切换和桌椅遮挡。画布维持 1024×1536 和 alpha，WebP q90 格式压缩；原始生成 PNG 保留在 Codex generated_images，路径登记在 manifest。

- tests/unit/test_reading_seated_pose.gd：16 人绑定、预加载、姿态切换和五款书覆盖。
- tools/capture_snack_seated.gd -- --reading：独立进程全班阅读夹具、只读性检查及两种分辨率实景截图，不写玩家存档。

验收结果：阅读专项 3/3、238 项断言通过；真实教室 36 项检查通过，输出 classroom_reading_1280.png、classroom_reading_960.png。已逐张检查生成贴图并查看教室实景：书本保持竖直、五款封面复用、人物脸部可见。16 张 WebP 共约 2.25 MiB；配置 190 项、两套字体覆盖、格式与静态检查通过。一张素材曾有 valid=false 导入记录，移除该新生成记录并经 Godot 正常重新导入后，专项及实景复验均通过。

