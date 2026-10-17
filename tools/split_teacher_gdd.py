"""Generate chapter reading copies of the authoritative teacher/mobile GDD."""

import argparse
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/gdd/core-gameplay-v3.1.md"
OUTPUT = ROOT / "docs/gdd/teacher-mobile"


def build():
    source = SOURCE.read_text(encoding="utf-8")
    chapters = list(re.finditer(r"^# 第[^\s]+章 (.+)$", source, re.MULTILINE))
    assert len(chapters) == 15, "Expected all 15 authoritative chapters"
    digest = hashlib.sha256(source.encode("utf-8")).hexdigest()
    names = [f"{i:02d}-{m.group(1).strip()}.md" for i, m in enumerate(chapters, 1)]
    anchor_files = {}
    for i, match in enumerate(chapters):
        end = chapters[i + 1].start() if i + 1 < len(chapters) else len(source)
        for title in re.findall(r"^#{1,6} (.+)$", source[match.start():end], re.MULTILINE):
            slug = re.sub(r"[^\w\s-]", "", title.lower()).replace(" ", "-")
            anchor_files[slug] = names[i]

    def link(match):
        target = match.group(1)
        if target.startswith("#"):
            return "](" + anchor_files.get(target[1:], "../core-gameplay-v3.1.md") + target + ")"
        if re.match(r"(?:[a-zA-Z]+:|/)", target):
            return match.group(0)
        return "](../" + target + ")"

    def rebase(text):
        return re.sub(r"\]\(([^)]+)\)", link, text)

    banner = (
        "> 老师版 · 移动端｜自动同步阅读分册。"
        "唯一编辑来源：[主策划案](../core-gameplay-v3.1.md)。\n"
        "> 修改主文档后运行 `python tools/split_teacher_gdd.py`；"
        "勿单独编辑本分册。\n"
        f"<!-- source-sha256: {digest} -->\n\n"
    )
    result = {}
    for i, match in enumerate(chapters):
        end = chapters[i + 1].start() if i + 1 < len(chapters) else len(source)
        nav = ["[总览与目录](00-总览与目录.md)"]
        if i:
            nav.append(f"[上一章]({names[i - 1]})")
        if i + 1 < len(chapters):
            nav.append(f"[下一章]({names[i + 1]})")
        body = rebase(source[match.start():end].strip())
        result[names[i]] = banner + body + "\n\n---\n\n" + " · ".join(nav) + "\n"
    intro = source[:chapters[0].start()]
    intro = intro.split("## 目录", 1)[0].strip()
    index = "# 下课十分钟 · 老师版移动端策划目录\n\n" + banner
    index += "按章阅读入口；保留主文档中的规则、待定项与实现状态，不因拆分而更改玩法。\n\n"
    index += "| 章节 | 内容 |\n|---|---|\n"
    for i, match in enumerate(chapters):
        index += f"| {i + 1:02d} | [{match.group(1).strip()}]({names[i]}) |\n"
    index += "\n## 版本与旧文件\n\n"
    index += "- 当前规则：本目录及其来源主文档；老师管理 16 名学生，制作目标为移动端。\n"
    index += "- `../v4/` 为学生版历史分册，不作为当前玩法要求；仍含被引用的美术、UI、存档迁移资料，暂不整批删除。\n"
    index += "- 旧单体稿与历史快照的用途见 [GDD 入口](../README.md)。\n"
    index += "- 先迁移有效内容、修复引用并核对工作区改动，再决定删除具体历史文件。\n\n"
    index += "## 主文档原始说明\n\n" + rebase(intro) + "\n"
    result["00-总览与目录.md"] = index
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify copies without modifying files")
    args = parser.parse_args()
    generated = build()
    if args.check:
        stale = [name for name, body in generated.items()
                 if not (OUTPUT / name).exists() or (OUTPUT / name).read_text(encoding="utf-8") != body]
        extra = {p.name for p in OUTPUT.glob("*.md")} - set(generated)
        if stale or extra:
            print("FAIL: stale/missing chapters:", stale, "unexpected:", sorted(extra))
            return 1
        print("PASS: index and all 15 chapters match the authoritative GDD")
        return 0
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, body in generated.items():
        (OUTPUT / name).write_text(body, encoding="utf-8")
    print("Generated index and 15 chapters in docs/gdd/teacher-mobile/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
