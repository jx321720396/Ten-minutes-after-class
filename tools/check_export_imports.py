"""导出前检查：data/**/*.csv 必须使用「Keep File」导入模式。

运行：python tools/check_export_imports.py
任一项失败则以非零码退出，导出 APK 前必须通过。

背景（2026-10-17 手机卡死事故）：
  Godot 默认把 .csv 当作翻译源（importer="csv_translation"）。这种模式下导出只打包
  编译后的 .translation，**原始 CSV 不进包**，安卓运行期 ConfigLoader 扫不到这些表。
  老师版新增的 11 张表因此全部缺失（activities / psyche / risk / harm / passives /
  passive_params / seat_relations / teacher_commands / chat_space / audio / pick_layers），
  表现为 _init_grade() 中止、is_broken() 越界刷屏、skip_class 卡住，帧率跌到 1。
  桌面端直接读源码目录，不经过导入，所以只有手机出错。

检查项：
  1. data/ 下每个 .csv 都有同名 .csv.import；
  2. 每个 .csv.import 的 importer 必须是 keep（type 必须为空）；
  3. source_file 必须指向真实存在的 CSV（防止改名后残留存根）；
  4. 不允许只有 .import、没有 .csv 的孤儿存根。

修复：Godot 编辑器里选中 CSV → 导入面板选「Keep File」→ 重新导入；
      或把 .import 里的 importer="csv_translation" 改为 importer="keep"、type=""，
      再跑 `godot --headless --path . --import`。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

FAILED = []


def check(name, problems):
    """problems 为空即通过；否则打印最多 10 条明细。"""
    problems = list(problems)
    print("  %s %s" % ("✓" if not problems else "✗", name))
    if problems:
        FAILED.append(name)
        for item in problems[:10]:
            print("      - %s" % item)
        if len(problems) > 10:
            print("      … 以及另外 %d 项" % (len(problems) - 10))


def read_setting(path, key):
    """从 .import 里读一行 `key="value"`；没有该键返回 None。"""
    with open(path, encoding="utf-8") as f:
        for line in f:
            match = re.match(r'^%s="(.*)"\s*$' % re.escape(key), line.strip())
            if match:
                return match.group(1)
    return None


def walk_data():
    """返回 (csv 相对路径列表, import 相对路径列表)，均为 data/ 下的 POSIX 路径。"""
    csvs = []
    imports = []
    for root, _dirs, files in os.walk(DATA):
        for name in files:
            rel = os.path.relpath(os.path.join(root, name), DATA).replace(os.sep, "/")
            if name.endswith(".csv"):
                csvs.append(rel)
            elif name.endswith(".csv.import"):
                imports.append(rel)
    return sorted(csvs), sorted(imports)


csvs, imports = walk_data()
print("=== 导出前检查：data/**/*.csv 的导入模式 ===")
print("  共 %d 个 CSV，%d 个 .import" % (len(csvs), len(imports)))

missing_import = [rel for rel in csvs if not os.path.isfile(os.path.join(DATA, rel + ".import"))]
check("每个 CSV 都有 .csv.import", missing_import)

wrong_importer = []
wrong_type = []
for rel in csvs:
    path = os.path.join(DATA, rel + ".import")
    if not os.path.isfile(path):
        continue
    importer = read_setting(path, "importer")
    if importer != "keep":
        wrong_importer.append("%s：importer=%r（应为 keep）" % (rel, importer))
    entry_type = read_setting(path, "type")
    if entry_type != "":
        wrong_type.append("%s：type=%r（应为空）" % (rel, entry_type))
check("导入模式全部为 keep", wrong_importer)
check("type 全部为空（keep 模式无资源类型）", wrong_type)

bad_source = []
known_csv = set(csvs)
for rel in imports:
    source = read_setting(os.path.join(DATA, rel), "source_file")
    expected = "res://data/" + rel[: -len(".import")]
    if source != expected:
        bad_source.append("%s：source_file=%r（应为 %r）" % (rel, source, expected))
check("source_file 指向的真实 CSV", bad_source)

orphans = [
    rel for rel in imports if rel[: -len(".import")] not in known_csv
]
check("没有只有 .import、没有 .csv 的孤儿存根", orphans)

if FAILED:
    print("  失败 %d 项：%s" % (len(FAILED), "；".join(FAILED)))
    print("  提示：导出前所有 CSV 必须是 keep，否则安卓包会丢表（见脚本抬头）。")
    sys.exit(1)
print("  全部通过：可以导出。")
