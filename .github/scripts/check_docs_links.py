#!/usr/bin/env python3
"""检查 Markdown 文档中的相对链接是否指向真实存在的文件。

- 只检查仓库内相对链接；跳过 http(s)、mailto、纯锚点。
- 目标可以是文件或目录；带 #锚点 时只校验锚点前的路径。
- 任何失效链接都会使脚本以非零状态退出（CI 阻断）。
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
SKIP_PREFIX = ("http://", "https://", "mailto:", "#", "tel:")


def strip_anchor(target: str) -> str:
    return target.split("#", 1)[0].strip()


def main() -> int:
    # Windows 控制台默认 GBK，强制 UTF-8 输出，避免打印中文/符号时 UnicodeEncodeError
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except Exception:
        pass

    failures: list[str] = []
    checked = 0

    for md in sorted(ROOT.rglob("*.md")):
        if ".git" in md.parts:
            continue
        text = md.read_text(encoding="utf-8", errors="replace")
        for raw in LINK_RE.findall(text):
            target = raw.strip().strip("<>").split(" ", 1)[0]
            if not target or target.startswith(SKIP_PREFIX):
                continue
            path_part = strip_anchor(target)
            if not path_part:
                continue
            checked += 1
            resolved = (md.parent / path_part).resolve()
            if not resolved.exists():
                failures.append(f"{md.relative_to(ROOT)} -> {target}")

    print(f"检查了 {checked} 个相对链接")
    if failures:
        print("\n失效链接：")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("全部相对链接有效")
    return 0


if __name__ == "__main__":
    sys.exit(main())
