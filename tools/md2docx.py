"""Markdown → DOCX 转换器（基于 python-docx）

用途：把仓库内的 md 规格文档导出为可直接分发的 docx。
支持：标题（#~####）、段落、无序/有序列表、表格、代码块、引用、分隔线，以及行内 `粗体` 与 `代码`。

用法：
    python tools/md2docx.py <input.md> <output.docx>
    python tools/md2docx.py --all          # 导出预设的两份文档

设计要点：
  · 表格单元格内的 **粗体** / `代码` 会被剥离标记（docx 表格内逐 run 上色成本高、收益低）；
  · 表格行里**未转义的 `|`**（如绝对值 `|A − H|`）会多切出列 —— 本转换器按表头列数
    把多余的片段合并回中间列，避免整表错位；
  · 中文字体通过 w:eastAsia 显式设置，否则 python-docx 默认字体对中文无效。
"""

import os
import re
import sys

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.shared import Pt, RGBColor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CN_FONT = "微软雅黑"
MONO_FONT = "Consolas"


def _font(run, name, size=None, bold=None, italic=None, color=None):
    run.font.name = name
    run._element.rPr.rFonts.set(qn("w:eastAsia"), name)
    if size:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if italic is not None:
        run.italic = italic
    if color:
        run.font.color.rgb = color


def add_inline(par, text):
    """把行内 `**粗体**` 与 `` `代码` `` 转成 docx run。"""
    for seg in re.split(r"(\*\*[^*]+\*\*|`[^`]+`)", text):
        if not seg:
            continue
        if seg.startswith("**") and seg.endswith("**"):
            _font(par.add_run(seg[2:-2]), CN_FONT, bold=True)
        elif seg.startswith("`") and seg.endswith("`"):
            _font(par.add_run(seg[1:-1]), MONO_FONT, size=9, color=RGBColor(0xB0, 0x30, 0x30))
        else:
            _font(par.add_run(seg), CN_FONT)


def strip_inline(text):
    return text.replace("**", "").replace("`", "")


def split_row(line):
    """按 | 切分表格行（去掉首尾空段）。"""
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in s.split("|")]


def merge_to_width(cells, width):
    """列数超宽时把多余片段合并回中间列（应对未转义的 | 绝对值符号）。"""
    if len(cells) <= width:
        return cells + [""] * (width - len(cells))
    extra = len(cells) - width
    mid = max(0, (width - 1) // 2)
    merged = cells[:mid] + ["|".join(cells[mid:mid + extra + 1])] + cells[mid + extra + 1:]
    return merged[:width]


def convert(md_path, docx_path):
    lines = open(md_path, encoding="utf-8").read().split("\n")
    doc = Document()
    base = doc.styles["Normal"]
    base.font.name = CN_FONT
    base.font.size = Pt(10.5)
    base.element.rPr.rFonts.set(qn("w:eastAsia"), CN_FONT)

    i = 0
    n = len(lines)
    stats = {"tables": 0, "headings": 0, "codes": 0}
    while i < n:
        ln = lines[i]

        # 代码块
        if ln.strip().startswith("```"):
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            par = doc.add_paragraph()
            par.paragraph_format.left_indent = Pt(12)
            _font(par.add_run("\n".join(buf)), MONO_FONT, size=9)
            stats["codes"] += 1
            continue

        # 表格：本行以 | 开头，且下一行是分隔行
        if ln.strip().startswith("|") and i + 1 < n and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            header = split_row(ln)
            width = len(header)
            i += 2
            body = []
            while i < n and lines[i].strip().startswith("|"):
                body.append(merge_to_width(split_row(lines[i]), width))
                i += 1
            tbl = doc.add_table(rows=1, cols=width)
            tbl.style = "Table Grid"
            for c, txt in enumerate(merge_to_width(header, width)):
                par = tbl.rows[0].cells[c].paragraphs[0]
                _font(par.add_run(strip_inline(txt)), CN_FONT, size=9, bold=True)
            for row in body:
                cells = tbl.add_row().cells
                for c, txt in enumerate(row):
                    par = cells[c].paragraphs[0]
                    _font(par.add_run(strip_inline(txt)), CN_FONT, size=9)
            doc.add_paragraph()
            stats["tables"] += 1
            continue

        # 标题
        m = re.match(r"^(#{1,6})\s+(.*)$", ln)
        if m:
            lvl = len(m.group(1))
            doc.add_heading(strip_inline(m.group(2)), level=min(lvl, 4))
            stats["headings"] += 1
            i += 1
            continue

        # 分隔线
        if re.match(r"^\s*(-{3,}|\*{3,})\s*$", ln):
            i += 1
            continue

        # 引用
        if ln.strip().startswith(">"):
            buf = []
            while i < n and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip().lstrip(">").strip())
                i += 1
            par = doc.add_paragraph()
            par.paragraph_format.left_indent = Pt(18)
            add_inline(par, " ".join(buf))
            for r in par.runs:
                r.italic = True
            continue

        # 列表
        m = re.match(r"^(\s*)[-*]\s+(.*)$", ln)
        if m:
            par = doc.add_paragraph(style="List Bullet")
            add_inline(par, m.group(2))
            i += 1
            continue
        m = re.match(r"^(\s*)\d+\.\s+(.*)$", ln)
        if m:
            par = doc.add_paragraph(style="List Number")
            add_inline(par, m.group(2))
            i += 1
            continue

        # 空行
        if not ln.strip():
            i += 1
            continue

        # 普通段落
        par = doc.add_paragraph()
        add_inline(par, ln.strip())
        i += 1

    doc.save(docx_path)
    return stats


PRESETS = [
    ("docs/gdd/core-gameplay-v3.1.md", "docs/export/下课十分钟-游戏策划案-v3.1.docx"),
    ("docs/production/开发进展-2026-10-05.md", "docs/export/开发进展-2026-10-05.docx"),
]


def main():
    args = sys.argv[1:]
    if args and args[0] == "--all":
        pairs = [(os.path.join(ROOT, a), os.path.join(ROOT, b)) for a, b in PRESETS]
    elif len(args) == 2:
        pairs = [(args[0], args[1])]
    else:
        print(__doc__)
        return 1

    for src, dst in pairs:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        st = convert(src, dst)
        size = os.path.getsize(dst)
        print("  %s -> %s  (%d 标题 / %d 表格 / %d 代码块, %.1f KB)"
              % (os.path.relpath(src, ROOT), os.path.relpath(dst, ROOT),
                 st["headings"], st["tables"], st["codes"], size / 1024.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
