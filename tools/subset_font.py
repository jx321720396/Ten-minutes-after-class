#!/usr/bin/env python3
"""字体子集：生成与覆盖检查。

默认（检查）：扫描仓库中的文本资源，确认当前 UI 字体覆盖它们用到的每一个字符。
    python tools/subset_font.py
新增了中文文案（尤其是新汉字）后，用下面的命令重建子集并重新导出：
    python tools/subset_font.py --write      # 需要 fontTools：py -m pip install fonttools

为什么需要这道检查：移动端为压包体把 HarmonyOS Sans SC 子集化到约 0.9 MiB
（2026-10-18，233.5 → 81.2 MiB）。子集只含生成当时扫描到的字符，之后新增文案若
出现新字符，运行时会显示方框（豆腐块）。本脚本把这件事变成推送前可发现的失败。

扫描范围：仓库内会被游戏读取的文本资源；docs/、tools/、tests/、build/ 等不参与
（它们不进包，也不在运行时显示）。`font_subset_exceptions.txt` 记录上游字体本身就
没有、只能靠系统回退渲染的字符。
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "assets/fonts/harmonyos-sans/HarmonyOS_Sans_SC.ttf"
EXCEPTIONS_FILE = Path(__file__).with_name("font_subset_exceptions.txt")

SCAN_EXTS = (
    ".gd", ".tscn", ".tres", ".json", ".csv", ".cfg", ".godot",
    ".shader", ".gdshader", ".txt", ".import",
)
SKIP_DIRS = {
    ".git", ".godot", "build", "docs", "addons", "tests", "tools",
    ".claude", ".venv", "node_modules",
}

# 不作为运行期文本处理的字符：控制符、变体选择符、零宽字符、BOM。
_IGNORED_RANGES = (
    (0x0000, 0x001F), (0x007F, 0x009F), (0x200B, 0x200F),
    (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF),
)

# 无法从文本资源推断、但界面一定会用到的字符（ASCII 与中文标点/符号）。
SAFETY_CHARS = (
    "".join(chr(c) for c in range(0x20, 0x7F))
    + "　、。〃〈〉《》「」『』【】〔〕〖〗〘〙〚〛〜〝〞〟〰〾〿–—―‗‘’‚‛“”„‟…‧﹏"
    + "！＂＃＄％＆＇（）＊＋，－．／：；＜＝＞？＠［＼］＾＿｀｛｜｝～￥·×÷←→↑↓"
    + "★☆√✕✓✗℃‰±§¶†‡•∞≈≠≤≥"
)


def _ignored(cp: int) -> bool:
    return any(lo <= cp <= hi for lo, hi in _IGNORED_RANGES)


def iter_text_files():
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.suffix not in SCAN_EXTS:
            continue
        rel = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in rel.parts[:-1]):
            continue
        yield path, rel


def collect_char_sources() -> dict[str, set[str]]:
    """字符 -> 出现它的文件集合（只保留前若干个，用于报错定位）。"""
    sources: dict[str, set[str]] = {}
    for path, rel in iter_text_files():
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for ch in text:
            if _ignored(ord(ch)):
                continue
            bucket = sources.setdefault(ch, set())
            if len(bucket) < 3:
                bucket.add(rel.as_posix())
    for ch in SAFETY_CHARS:
        sources.setdefault(ch, set())
    return sources


def load_exceptions() -> set[str]:
    if not EXCEPTIONS_FILE.exists():
        return set()
    allowed: set[str] = set()
    for line in EXCEPTIONS_FILE.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("#"):
            continue
        # 行内 "字符  # 说明"
        allowed.update(ch for ch in line.split("#", 1)[0] if not ch.isspace())
    return allowed


def _cmap_offset(data: bytes) -> int:
    num_tables = struct.unpack_from(">H", data, 4)[0]
    for i in range(num_tables):
        rec = 12 + i * 16
        if data[rec:rec + 4] == b"cmap":
            return struct.unpack_from(">I", data, rec + 8)[0]
    raise ValueError("字体缺少 cmap 表")


def _parse_format4(data: bytes, off: int) -> set[int]:
    seg = struct.unpack_from(">H", data, off + 6)[0] // 2
    end_off = off + 14
    ends = struct.unpack_from(f">{seg}H", data, end_off)
    start_off = end_off + seg * 2 + 2
    starts = struct.unpack_from(f">{seg}H", data, start_off)
    delta_off = start_off + seg * 2
    deltas = struct.unpack_from(f">{seg}h", data, delta_off)
    range_off = delta_off + seg * 2
    ranges = struct.unpack_from(f">{seg}H", data, range_off)
    cps: set[int] = set()
    for i in range(seg):
        if starts[i] == 0xFFFF:
            continue
        for cp in range(starts[i], ends[i] + 1):
            if ranges[i] == 0:
                gid = (cp + deltas[i]) & 0xFFFF
            else:
                addr = range_off + i * 2 + ranges[i] + (cp - starts[i]) * 2
                if addr + 2 > len(data):
                    continue
                gid = struct.unpack_from(">H", data, addr)[0]
                if gid:
                    gid = (gid + deltas[i]) & 0xFFFF
            if gid:
                cps.add(cp)
    return cps


def _parse_format12(data: bytes, off: int) -> set[int]:
    groups = struct.unpack_from(">I", data, off + 12)[0]
    cps: set[int] = set()
    for i in range(groups):
        start, end, _ = struct.unpack_from(">III", data, off + 16 + i * 12)
        cps.update(range(start, end + 1))
    return cps


def font_codepoints(path: Path) -> set[int]:
    """读取 TTF 的 cmap，支持 format 4 / 12（不依赖 fontTools）。"""
    data = path.read_bytes()
    cmap_off = _cmap_offset(data)
    _, count = struct.unpack_from(">HH", data, cmap_off)
    best = None
    for i in range(count):
        pid, eid, sub_off = struct.unpack_from(">HHI", data, cmap_off + 4 + i * 8)
        fmt = struct.unpack_from(">H", data, cmap_off + sub_off)[0]
        priority = {(3, 10, 12): 3, (0, 4, 12): 3, (3, 1, 4): 2, (0, 3, 4): 2}.get(
            (pid, eid, fmt), 0
        )
        if priority and (best is None or priority > best[0]):
            best = (priority, fmt, cmap_off + sub_off)
    if best is None:
        raise ValueError("字体缺少可用的 Unicode cmap 子表")
    _, fmt, off = best
    return _parse_format4(data, off) if fmt == 4 else _parse_format12(data, off)


def check() -> int:
    if not FONT.exists():
        print(f"错误：找不到字体 {FONT.relative_to(ROOT)}", file=sys.stderr)
        return 1
    sources = collect_char_sources()
    covered = font_codepoints(FONT)
    allowed = load_exceptions()
    missing = [ch for ch in sorted(sources) if ord(ch) not in covered and ch not in allowed]
    total = len(sources)
    ignored = sum(1 for ch in missing if ch in allowed)
    if not missing:
        print(f"字体子集检查通过：{total} 个字符全部覆盖（另有 {len(allowed)} 个已知字体缺字）。")
        return 0
    print(f"字体子集检查失败：{len(missing)} 个字符不在当前字体里。", file=sys.stderr)
    for ch in missing[:40]:
        where = "、".join(sorted(sources.get(ch, []))) or "（安全字符集）"
        print(f"  缺失 {ch!r} U+{ord(ch):04X} <- {where}", file=sys.stderr)
    if len(missing) > 40:
        print(f"  ……另有 {len(missing) - 40} 个", file=sys.stderr)
    print(
        "\n修复：安装 fontTools 后运行 `python tools/subset_font.py --write` 重建子集，再重新导出。\n"
        "若该字符上游字体本来就没有，请登进 tools/font_subset_exceptions.txt。",
        file=sys.stderr,
    )
    return 1


def write() -> int:
    try:
        from fontTools.subset import main as subset_main
    except ImportError:
        print(
            "错误：--write 需要 fontTools。请先安装：\n"
            "  py -m pip install fonttools\n"
            "（本机 uv 管理的 Python 若报 externally-managed，可建一个临时 venv 再执行）",
            file=sys.stderr,
        )
        return 1
    sources = collect_char_sources()
    text = "".join(sorted(sources))
    tmp_text = FONT.with_suffix(".chars.txt")
    tmp_font = FONT.with_suffix(".subset.ttf")
    tmp_text.write_text(text, encoding="utf-8")
    try:
        subset_main([
            str(FONT),
            f"--output-file={tmp_font}",
            f"--text-file={tmp_text}",
            "--layout-features=*",
            "--glyph-names",
            "--symbol-cmap",
            "--legacy-cmap",
            "--notdef-glyph",
            "--notdef-outline",
            "--recommended-glyphs",
            "--name-IDs=*",
            "--name-legacy",
            "--name-languages=*",
        ])
        tmp_font.replace(FONT)
    finally:
        tmp_text.unlink(missing_ok=True)
        tmp_font.unlink(missing_ok=True)
    print(
        f"已重建字体子集：{len(sources)} 个字符，"
        f"{FONT.stat().st_size / 1048576:.2f} MiB -> {FONT.relative_to(ROOT)}"
    )
    print("请重新导入（godot --headless --import）并重新导出包体。")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="字体子集生成与覆盖检查")
    parser.add_argument("--write", action="store_true", help="重建子集（需要 fontTools）")
    args = parser.parse_args()
    return write() if args.write else check()


if __name__ == "__main__":
    raise SystemExit(main())
