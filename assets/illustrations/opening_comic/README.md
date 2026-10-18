# 老师上任漫画

2026-10-18 使用 OpenAI imagegen 生成四张 1672×941 校园漫画插画。顺序为临时接班、考试安排、成绩考验、安全责任。仅作为开场表现，不指定学生关系事件。

正式插画已内嵌中文和白底黑边尖角气泡，游戏运行时只展示图片，不再创建对话框。原始无字底图保存在 `docs/art/opening_comic_sources/`；离线执行 `tools/bake_opening_comic.gd` 生成 1920×1080 带字页面（输出至 `tools/out/opening_comic_baked/`），并自动无损写入此处 WebP。配置与文案：`data/ui/opening_comic.json`；视图与时序：`scripts/ui/opening_comic*.gd`。每页独立斜切遮罩沿对应插画分格，透明渐显与横向滑入均按真实时间播放，不受世界倍率影响。

图片由本次生成结果原样复制，无额外外部素材。原始生成文件编号依次为 fbb8b0a4、c92d7ea2、ef9b509d、965b7157。
