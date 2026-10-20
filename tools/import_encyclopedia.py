#!/usr/bin/env python3
"""把 `docs/localization/百科全书-词条编辑稿.md` 的改动写回 `data/localization/encyclopedia.json`。

配套 `tools/export_encyclopedia.py`（导出编辑稿）。流程：
    1. python tools/export_encyclopedia.py          # 导出今版文案
    2. 在编辑稿里逐词条改文案
    3. python tools/import_encyclopedia.py --dry-run # 先看报告（不写盘）
       python tools/import_encyclopedia.py           # 写回 JSON

本脚本只改 `categories`（标题/导语/排序）与 `entries`（词条），`_note` / `_discipline` /
`schema_version` 原样保留；JSON 的输出格式与仓库现有文件一致（2 空格缩进、aliases 内联、
UTF-8 无 BOM、末尾换行），因此「导出→原样导入」应该**没有任何 diff** —— 这也是自检方式。

校验不过就不写盘：id 重复、category 不在分类表、正文缺失等直接报错；`[t]…[/t]`
引用了不存在的词条只警告（运行时只是少一处高亮）。

用法：
    python tools/import_encyclopedia.py [--dry-run] [--diff] [--path 编辑稿.md]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "localization" / "encyclopedia.json"
DEFAULT_DOC = ROOT / "docs" / "localization" / "百科全书-词条编辑稿.md"

FIELD_KEYS = ("别名", "一句话", "正文", "排序", "导语")
CAT_SEP = "·"
ID_RE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$")
META_RE = re.compile(
    r"id:\s*([A-Za-z0-9_.\-]+)\s*[|｜]\s*category:\s*([A-Za-z0-9_\-]*)\s*[|｜]\s*implemented:\s*([A-Za-z0-9]+)"
)
REF_RE = re.compile(r"\[t\]([^\[\]]+)\[/t\]")

errors: list[str] = []
warnings: list[str] = []


# --------------------------------------------------------------------- 解析


def _field(line: str) -> tuple[str, str]:
    """把 `- 一句话：xxx` / `**别名**：xxx` 拆成 (字段名, 值)。不是字段行返回 ("", "")。"""
    text = line.strip()
    if text[:2] in ("- ", "* "):
        text = text[2:].strip()
    text = text.replace("**", "")
    for sep in ("：", ":"):
        head, found, tail = text.partition(sep)
        if found and head.strip() in FIELD_KEYS:
            return head.strip(), tail.strip()
    return "", ""


def _blocks(lines: list[str], head_re: re.Pattern[str]) -> list[tuple[str, list[str]]]:
    out: list[tuple[str, list[str]]] = []
    cur: tuple[str, list[str]] | None = None
    for line in lines:
        m = head_re.match(line)
        if m:
            cur = (m.group(1).strip(), [])
            out.append(cur)
        elif cur is not None:
            cur[1].append(line)
    return out


def _normalize_body(lines: list[str]) -> str:
    """代码块内的行 → 正文：逐行去尾空格，去首尾空行，按空行分段，段间用两个换行。"""
    cleaned = [line.rstrip() for line in lines]
    while cleaned and not cleaned[0]:
        cleaned.pop(0)
    while cleaned and not cleaned[-1]:
        cleaned.pop()
    paras: list[str] = []
    cur: list[str] = []
    for line in cleaned:
        if line:
            cur.append(line)
        elif cur:
            paras.append("\n".join(cur))
            cur = []
    if cur:
        paras.append("\n".join(cur))
    return "\n\n".join(paras)


def _body_of(block: list[str], term: str) -> tuple[str, bool]:
    """返回 (正文, 是否已报错)。"""
    start = None
    inline = ""
    for i, line in enumerate(block):
        key, value = _field(line)
        if key == "正文":
            start = i
            inline = value
            break
    if start is None:
        errors.append("词条「%s」缺「- 正文：」这一行" % term)
        return "", True

    fence_start = None
    for j in range(start, len(block)):
        if block[j].strip().startswith("```"):
            fence_start = j + 1
            break
    if fence_start is None:
        # 允许把正文直接写在同一行（会丢掉分段，所以提示一下）
        if inline:
            warnings.append("词条「%s」的正文没放进代码块，已按一行文字导入（分段会丢）" % term)
            return inline, False
        errors.append("词条「%s」的正文既没有代码块、也没有同行的文字" % term)
        return "", True
    for k in range(fence_start, len(block)):
        if block[k].strip().startswith("```"):
            return _normalize_body(block[fence_start:k]), False
    errors.append("词条「%s」的正文代码块没有收尾的 ```" % term)
    return "", True


def _aliases(raw: str) -> list[str]:
    out: list[str] = []
    for part in re.split(r"[、,，;；]", raw):
        item = part.strip()
        if item and item not in out:
            out.append(item)
    return out


def _as_bool(raw: str, term: str) -> bool:
    v = raw.strip().lower()
    if v in ("true", "1", "yes", "y", "是", "上线"):
        return True
    if v in ("false", "0", "no", "n", "否", "下线"):
        return False
    errors.append("词条「%s」的 implemented 只认 true/false（写的是「%s」）" % (term, raw))
    return False


# --------------------------------------------------------------------- 导入


def parse(doc_text: str, old: dict) -> tuple[list[dict], list[dict]]:
    lines = doc_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")

    # ---- 按二级标题切节：只看「分类」与「词条」两节
    sections: dict[str, list[str]] = {}
    cur_name: str | None = None
    for line in lines:
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            cur_name = m.group(1).strip()
            sections.setdefault(cur_name, [])
            continue
        if cur_name is not None:
            sections[cur_name].append(line)

    if "分类" not in sections:
        errors.append("编辑稿里找不到「## 分类」一节")
    if "词条" not in sections:
        errors.append("编辑稿里找不到「## 词条」一节")
    if errors:
        return [], []

    # ---- 分类
    categories: list[dict] = []
    cat_head = re.compile(r"^###\s+(.+?)\s*$")
    for order_hint, (head, body) in enumerate(_blocks(sections["分类"], cat_head), 1):
        if CAT_SEP in head:
            raw_id, _, title = head.partition(CAT_SEP)
            cat_id = raw_id.strip()
            title = title.strip()
        else:
            cat_id, title = "", head
        order = None
        intro = ""
        for line in body:
            key, value = _field(line)
            if key == "排序":
                try:
                    order = int(value)
                except ValueError:
                    errors.append("分类「%s」的排序不是整数：%s" % (head, value))
            elif key == "导语":
                intro = value
        if not cat_id:
            errors.append("分类标题要写成「### id · 标题」，读不懂：%s" % head)
            continue
        if not title:
            errors.append("分类「%s」没有标题" % cat_id)
        if order is None:
            warnings.append("分类「%s」没写排序，按出现顺序用了 %d" % (cat_id, order_hint))
            order = order_hint
        categories.append({"id": cat_id, "title": title, "order": order, "intro": intro})

    seen_cat: dict[str, str] = {}
    for cat in categories:
        if cat["id"] in seen_cat:
            errors.append("分类 id 重复：%s" % cat["id"])
        seen_cat[cat["id"]] = cat["title"]
    seen_order: dict[int, str] = {}
    for cat in categories:
        if cat["order"] in seen_order:
            errors.append(
                "分类排序重复：%s 与 %s 都是 %d" % (seen_order[cat["order"]], cat["id"], cat["order"])
            )
        seen_order[cat["order"]] = cat["id"]

    # ---- 词条
    old_by_term: dict[str, list[dict]] = {}
    for entry in old.get("entries", []):
        old_by_term.setdefault(str(entry.get("term", "")), []).append(entry)

    entries: list[dict] = []
    entry_head = re.compile(r"^####\s+(.+?)\s*$")
    for term, body in _blocks(sections["词条"], entry_head):
        term = term.strip()
        meta = None
        fields: dict[str, str] = {}
        for line in body:
            m = META_RE.search(line)
            if m and meta is None:
                meta = m
                continue
            key, value = _field(line)
            if key and key not in fields:
                fields[key] = value

        if meta is not None:
            entry_id, category, implemented = meta.group(1), meta.group(2), meta.group(3)
        else:
            # 标记行被删了：按词条名在旧 JSON 里唯一匹配，尽量不让一整个词条报废
            hits = old_by_term.get(term, [])
            if len(hits) == 1:
                entry_id = str(hits[0].get("id", ""))
                category = str(hits[0].get("category", ""))
                implemented = "true" if bool(hits[0].get("implemented", False)) else "false"
                warnings.append("词条「%s」的标记行丢了吗？按旧 id %s 补上了" % (term, entry_id))
            else:
                errors.append(
                    "词条「%s」缺标记行（id / category / implemented），且无法按名字对上旧词条" % term
                )
                continue

        if not term:
            errors.append("词条 id %s 的标题（词条名）是空的" % entry_id)
        if not ID_RE.match(entry_id):
            errors.append("词条「%s」的 id 不合规范：%s（要写成 attr.stress 这种英文点号名）" % (term, entry_id))
        if category not in seen_cat:
            errors.append("词条「%s」的 category「%s」不在分类表里" % (term, category))

        body_text, body_failed = _body_of(body, term)
        entries.append(
            {
                "id": entry_id,
                "term": term,
                "category": category,
                "short": fields.get("一句话", ""),
                "aliases": _aliases(fields.get("别名", "")),
                "implemented": _as_bool(implemented, term),
                "body": body_text,
                "body_failed": body_failed,
            }
        )

    # ---- 交叉校验
    seen_id: dict[str, str] = {}
    seen_term: dict[str, str] = {}
    for entry in entries:
        if entry["id"] in seen_id:
            errors.append("词条 id 重复：%s（「%s」与「%s」）" % (entry["id"], seen_id[entry["id"]], entry["term"]))
        seen_id[entry["id"]] = entry["term"]
        if entry["term"] in seen_term:
            errors.append("词条名重复：%s（id %s 与 %s）" % (entry["term"], seen_term[entry["term"]], entry["id"]))
        seen_term[entry["term"]] = entry["id"]
        if not entry["short"]:
            warnings.append("词条「%s」没有「一句话」" % entry["term"])
        body_failed = bool(entry.pop("body_failed", False))
        if not entry["body"] and not body_failed:
            errors.append("词条「%s」的正文是空的" % entry["term"])

    known_terms = set(seen_term) | {a for entry in entries for a in entry["aliases"]}
    for entry in entries:
        for ref in dict.fromkeys(REF_RE.findall(entry["body"])):
            if ref.strip() and ref.strip() not in known_terms:
                warnings.append("词条「%s」里的 [t]%s[/t] 找不到对应词条（高亮会失效）" % (entry["term"], ref))

    used = {entry["category"] for entry in entries}
    for cat in categories:
        if cat["id"] not in used:
            warnings.append("分类「%s」下一条词条都没有，游戏里不会显示" % cat["id"])

    return categories, entries


# --------------------------------------------------------------------- 写回


def _dump(value, indent: int = 0, key: str = "") -> str:
    pad = " " * indent
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = list(value.items())
        body = []
        for i, (k, v) in enumerate(items):
            body.append(
                "%s  %s: %s%s"
                % (pad, json.dumps(k, ensure_ascii=False), _dump(v, indent + 2, k), "," if i < len(items) - 1 else "")
            )
        return "{\n" + "\n".join(body) + "\n" + pad + "}"
    if isinstance(value, list):
        if key == "aliases":
            return json.dumps(value, ensure_ascii=False)
        if not value:
            return "[]"
        body = []
        for i, item in enumerate(value):
            body.append(
                "%s  %s%s" % (pad, _dump(item, indent + 2, key), "," if i < len(value) - 1 else "")
            )
        return "[\n" + "\n".join(body) + "\n" + pad + "]"
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return json.dumps(value)
    return json.dumps(value, ensure_ascii=False)


def dumps(data: dict) -> str:
    return _dump(data) + "\n"


def _changes(old: dict, categories: list[dict], entries: list[dict]) -> list[str]:
    old_entries = {str(e.get("id", "")): e for e in old.get("entries", [])}
    new_entries = {e["id"]: e for e in entries}
    lines: list[str] = []

    old_cats = {str(c.get("id", "")): c for c in old.get("categories", [])}
    new_cats = {c["id"]: c for c in categories}
    added_cats = [c for c in new_cats if c not in old_cats]
    gone_cats = [c for c in old_cats if c not in new_cats]
    touched_cats = [
        cid
        for cid in new_cats
        if cid in old_cats
        and any(
            old_cats[cid].get(f) != new_cats[cid].get(f) for f in ("title", "intro", "order")
        )
    ]
    if added_cats:
        lines.append("分类新增：%s" % "、".join(added_cats))
    if gone_cats:
        lines.append("分类删除：%s" % "、".join(gone_cats))
    if touched_cats:
        lines.append("分类改动：%s" % "、".join(touched_cats))

    added = [i for i in new_entries if i not in old_entries]
    removed = [i for i in old_entries if i not in new_entries]
    if added:
        lines.append("词条新增：%s" % "、".join(added))
    if removed:
        lines.append("词条删除：%s" % "、".join(removed))

    changed: list[str] = []
    old_order = [str(e.get("id", "")) for e in old.get("entries", []) if str(e.get("id", "")) in new_entries]
    new_order = [entry_id for entry_id in new_entries if entry_id in old_entries]
    if old_order != new_order:
        lines.append("词条顺序有调整（目录展示顺序跟着变）")
    for entry_id, entry in new_entries.items():
        before = old_entries.get(entry_id)
        if before is None:
            continue
        diff = [
            f
            for f in ("term", "category", "short", "aliases", "implemented", "body")
            if before.get(f) != entry.get(f)
        ]
        if diff:
            changed.append("%s（%s）" % (entry_id, "/".join(diff)))
    if changed:
        lines.append("词条改动：%s" % "、".join(changed))
    if not lines:
        lines.append("无改动")
    return lines


def _line_diff(before: str, after: str) -> str:
    import difflib

    out = difflib.unified_diff(
        before.splitlines(),
        after.splitlines(),
        fromfile="旧",
        tofile="新",
        n=1,
        lineterm="",
    )
    return "\n".join("  " + line for line in out)


def main() -> int:
    ap = argparse.ArgumentParser(description="把百科词条编辑稿写回 encyclopedia.json")
    ap.add_argument("--path", default=str(DEFAULT_DOC), help="编辑稿路径")
    ap.add_argument("--dry-run", action="store_true", help="只校验并报告，不写盘")
    ap.add_argument("--diff", action="store_true", help="逐条打印正文前后差异")
    args = ap.parse_args()

    doc_path = Path(args.path)
    if not doc_path.is_absolute():
        doc_path = ROOT / doc_path
    if not doc_path.exists():
        print("!! 找不到编辑稿：%s" % doc_path)
        print("   先跑 python tools/export_encyclopedia.py 导出")
        return 1

    old = json.loads(DATA.read_text(encoding="utf-8"))
    categories, entries = parse(doc_path.read_text(encoding="utf-8"), old)

    print("=== 导入百科词条编辑稿 ===")
    shown = doc_path.relative_to(ROOT).as_posix() if doc_path.is_relative_to(ROOT) else str(doc_path)
    print("稿：%s" % shown)
    print("读入：%d 个分类 / %d 条词条" % (len(categories), len(entries)))

    if errors:
        print("\n✗ 有 %d 项错误，未写盘：" % len(errors))
        for item in errors:
            print("  - %s" % item)
        return 1

    new_data: dict = {}
    for key, value in old.items():
        if key == "categories":
            new_data[key] = sorted(categories, key=lambda c: c["order"])
        elif key == "entries":
            new_data[key] = entries
        else:
            new_data[key] = value
    new_data.setdefault("categories", sorted(categories, key=lambda c: c["order"]))
    new_data.setdefault("entries", entries)

    print("\n变化：")
    for line in _changes(old, categories, entries):
        print("  · %s" % line)
    offline = [e["id"] for e in entries if not e["implemented"]]
    print("  · 未上线（游戏里不显示）：%s" % ("、".join(offline) if offline else "无"))

    if warnings:
        print("\n提示（%d 条，不影响写盘）：" % len(warnings))
        for item in warnings:
            print("  - %s" % item)

    if args.diff:
        old_entries = {str(e.get("id", "")): e for e in old.get("entries", [])}
        for entry in entries:
            before = old_entries.get(entry["id"], {}).get("body")
            if before is not None and before != entry["body"]:
                print("\n--- %s %s ---" % (entry["id"], entry["term"]))
                print(_line_diff(before, entry["body"]))

    text = dumps(new_data)
    if text == DATA.read_text(encoding="utf-8"):
        print("\n✓ 校验通过；JSON 内容无变化，没有写盘")
        return 0
    if args.dry_run:
        print("\n✓ 校验通过；--dry-run，没有写盘")
        return 0

    DATA.write_text(text, encoding="utf-8", newline="\n")
    print("\n✓ 已写入 %s" % DATA.relative_to(ROOT).as_posix())
    print("  接着跑：python tools/subset_font.py（新增汉字要进字体子集，否则运行期是方框）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
