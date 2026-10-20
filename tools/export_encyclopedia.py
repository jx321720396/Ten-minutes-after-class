#!/usr/bin/env python3
"""把 `data/localization/encyclopedia.json` 导出成一份可逐词条编辑的 Markdown 编辑稿。

为什么要有这个脚本：百科词条正文是玩家可见文案，手工改 JSON 很容易碰坏
（转义、缩进、`\\n\\n` 段落看不出来）。导出成「一词条一块」的编辑稿，改完再用
`tools/import_encyclopedia.py` 写回 —— **JSON 仍是唯一事实源**，编辑稿只是给人改的。

用法：
    python tools/export_encyclopedia.py            # 写 docs/localization/百科全书-词条编辑稿.md
    python tools/export_encyclopedia.py --stdout   # 打到标准输出（不落盘）
    python tools/export_encyclopedia.py --check    # 只比对，编辑稿与 JSON 不同步则退出码 1

编辑稿格式（import 脚本按同样的约定解析）：
    ## 分类
    ### stat · 状态与数值
    - 排序：1
    - 导语：……

    ## 词条
    #### 压力
    <!-- id: attr.stress | category: stat | implemented: true -->
    - 别名：压力值
    - 一句话：绷到头之前的那口气
    - 正文：
    ```text
    ……
    ```
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "localization" / "encyclopedia.json"
OUT = ROOT / "docs" / "localization" / "百科全书-词条编辑稿.md"

CAT_SEP = " · "


def load_data() -> dict:
    return json.loads(DATA.read_text(encoding="utf-8"))


def _entry_block(entry: dict) -> list[str]:
    entry_id = str(entry.get("id", ""))
    category = str(entry.get("category", ""))
    implemented = "true" if bool(entry.get("implemented", False)) else "false"
    aliases = [str(a) for a in entry.get("aliases", [])]

    lines = [
        "#### %s" % str(entry.get("term", "")),
        "",
        "<!-- id: %s | category: %s | implemented: %s -->" % (entry_id, category, implemented),
        "",
    ]
    if not bool(entry.get("implemented", False)):
        lines.append("> 当前**未上线**：游戏里看不到这一条。想上线，把上面的 `implemented` 改成 `true`。")
        lines.append("")
    lines += [
        "- 别名：%s" % "、".join(aliases),
        "- 一句话：%s" % str(entry.get("short", "")),
        "- 正文：",
        "",
        "```text",
        str(entry.get("body", "")),
        "```",
        "",
    ]
    return lines


def build_markdown(data: dict) -> str:
    cats = sorted(data.get("categories", []), key=lambda c: int(c.get("order", 0)))
    entries = list(data.get("entries", []))
    offline = [e for e in entries if not bool(e.get("implemented", False))]

    lines: list[str] = [
        "<!-- 由 python tools/export_encyclopedia.py 生成；也可以手工改，"
        "改完跑 python tools/import_encyclopedia.py 写回 JSON。 -->",
        "",
        "# 百科全书 · 词条编辑稿",
        "",
        "- 数据源：`data/localization/encyclopedia.json`（schema_version %s，**游戏的唯一事实源**）"
        % data.get("schema_version", "?"),
        "- 规模：%d 个分类 / %d 条词条（其中 %d 条未上线）" % (len(cats), len(entries), len(offline)),
        "- 改完在仓库根目录跑 `python tools/import_encyclopedia.py` 回写；"
        "`--dry-run` 只报告不写盘",
        "",
        "## 怎么改",
        "",
        "1. **改文案**：直接改中文。`####` 那行是词条名，下面「别名 / 一句话 / 正文」是内容。",
        "2. **正文格式**：段落之间空一行；可写 `[b]加粗[/b]`、`[t]别的词条名[/t]`（跨引用，"
        "填词条名或别名）、`[color=orange]…[/color]`（未实装提示）。",
        "3. **标记行别动**：`id: … | category: … | implemented: …` 那行是程序引用键。"
        "`implemented` 改成 `false`，这条就不在游戏里出现；改回 `true` 上线。",
        "4. **调顺序**：整块上下挪（从 `#### 词条名` 到正文代码块结束）。同一分类内的先后 = 游戏目录顺序。",
        "5. **加词条**：复制一整块，改内容；`id` 起新的英文点号名（如 `cmd.new_thing`），"
        "`category` 填分类 id。",
        "6. **删词条**：整块删掉。",
        "7. **分类**：「分类」一节里改标题与导语；`排序` 决定目录里的先后。",
        "",
        "---",
        "",
        "## 分类",
        "",
    ]
    for cat in cats:
        lines += [
            "### %s%s%s" % (str(cat.get("id", "")), CAT_SEP, str(cat.get("title", ""))),
            "",
            "- 排序：%s" % int(cat.get("order", 0)),
            "- 导语：%s" % str(cat.get("intro", "")),
            "",
        ]

    lines += ["---", "", "## 词条", ""]
    for cat in cats:
        cat_id = str(cat.get("id", ""))
        rows = [e for e in entries if str(e.get("category", "")) == cat_id]
        lines += ["### %s%s%s（%d 条）" % (str(cat.get("title", cat_id)), CAT_SEP, cat_id, len(rows)), ""]
        for entry in rows:
            lines += _entry_block(entry)

    # 分类字段缺失（不该发生）时兜底：把没归到任何分类的词条也导出来，免得丢
    known = {str(c.get("id", "")) for c in cats}
    orphans = [e for e in entries if str(e.get("category", "")) not in known]
    if orphans:
        lines += ["### 未归类的词条（category 不在分类表里，导入时会报错）", ""]
        for entry in orphans:
            lines += _entry_block(entry)

    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="导出百科全书的词条编辑稿")
    ap.add_argument("--stdout", action="store_true", help="打到标准输出，不落盘")
    ap.add_argument("--check", action="store_true", help="只检查编辑稿是否与 JSON 同步")
    args = ap.parse_args()

    text = build_markdown(load_data())

    if args.stdout:
        sys.stdout.write(text)
        return 0

    if args.check:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        # 编辑器可能把换行存成 CRLF —— 内容相同就算同步，别为这个报红
        if current.replace("\r\n", "\n").replace("\r", "\n") == text:
            print("编辑稿与 JSON 同步：%s" % OUT.relative_to(ROOT).as_posix())
            return 0
        print("!! 编辑稿与 JSON 不一致：%s" % OUT.relative_to(ROOT).as_posix())
        print("   JSON 改过 → 跑 python tools/export_encyclopedia.py 重新导出")
        print("   编辑稿改过 → 跑 python tools/import_encyclopedia.py 写回")
        return 1

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print("已导出：%s" % OUT.relative_to(ROOT).as_posix())
    return 0


if __name__ == "__main__":
    sys.exit(main())
