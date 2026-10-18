#!/usr/bin/env bash
# =============================================================================
# tools/run_tests.sh —— 一键跑测试
#
# 顺序：① 离线六道门（tools/*.py） → ①b 导出前置检查（CSV 导入模式）
#       → ①c 导出前置检查（字体子集覆盖） → ② 铁律测试（tests/invariants/）
#       → ③ Godot 侧 GUT 单测（需要 Godot 可执行文件）
#
# 本机没有 Godot 时，①② 照跑，③ 自动跳过并给出提示（不算失败）——
# 这台机器上 Godot 未加入 PATH，所以「填 Godot 完整路径」是使用本脚本的关键一步。
#
# 用法：
#   bash tools/run_tests.sh
#   bash tools/run_tests.sh --godot "E:/godot/Godot_v4.7.2-stable_win64_console.exe"
#   bash tools/run_tests.sh --no-godot          # 只跑离线部分
#   GODOT_BIN="/e/godot/Godot_v4.7.2-stable_win64_console.exe" bash tools/run_tests.sh
#   echo "E:/godot/Godot_v4.7.2-stable_win64_console.exe" > .godot_path   # 长期记住路径
#
# Windows 提示：headless 输出要用 **console 版**（Godot_v4.7.2-stable_win64_console.exe），
#              普通版抓不到 stdout（见 tests/README.md）。
#
# 退出码：0 = 全部通过（跳过不算失败）；1 = 有失败。
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT" || exit 1

# Windows GBK 控制台下 ✓/✗ 会抛 UnicodeEncodeError，必须强制 UTF-8（见 tests/invariants/README.md）
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
export PYTHONUTF8="${PYTHONUTF8:-1}"

GODOT_PATH_FILE="$ROOT/.godot_path"
PYTHON=""
GODOT_BIN="${GODOT_BIN:-}"   # 环境变量 GODOT_BIN 也认；--godot 会覆盖它
NO_GODOT=0

RESULT_PASS=0
RESULT_FAIL=0
RESULT_SKIP=0

usage() {
  cat <<'EOF'
用法：bash tools/run_tests.sh [选项]

  --godot <路径>   Godot 可执行文件完整路径（Windows 建议用 console 版）
  --python <命令>  指定 Python 解释器（默认自动找 python / python3 / py）
  --no-godot       跳过 Godot 段，只跑离线六道门 + 铁律测试
  -h, --help       显示本帮助

Godot 路径查找顺序：--godot 参数 > $GODOT_BIN > 仓库根 .godot_path 文件 > PATH。
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --godot)
      if [ $# -lt 2 ]; then
        printf '错误：--godot 需要给出 Godot 可执行文件完整路径\n\n' >&2
        usage >&2
        exit 2
      fi
      GODOT_BIN="$2"
      shift 2
      ;;
    --godot=*)
      GODOT_BIN="${1#*=}"
      shift
      ;;
    --python)
      if [ $# -lt 2 ]; then
        printf '错误：--python 需要给出 Python 解释器命令\n\n' >&2
        usage >&2
        exit 2
      fi
      PYTHON="$2"
      shift 2
      ;;
    --python=*)
      PYTHON="${1#*=}"
      shift
      ;;
    --no-godot)
      NO_GODOT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '错误：未知参数 %s\n\n' "$1"
      usage
      exit 2
      ;;
  esac
done

# ------------------------------------------------------------------ 工具函数
mark_pass() {
  RESULT_PASS=$((RESULT_PASS + 1))
  printf -- '--> [PASS] %s\n' "$1"
}

mark_fail() {
  RESULT_FAIL=$((RESULT_FAIL + 1))
  printf -- '--> [FAIL] %s\n' "$1"
}

mark_skip() {
  RESULT_SKIP=$((RESULT_SKIP + 1))
  printf -- '--> [SKIP] %s\n' "$1"
}

# 运行一步；名字与「未测到」区分开：缺文件 = SKIP，跑失败 = FAIL
run_step() {
  local name="$1"
  shift
  printf '\n=== %s ===\n' "$name"
  "$@"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    mark_pass "$name"
  else
    mark_fail "$name (exit=$rc)"
  fi
}

# ------------------------------------------------------------------ 解释器探测
find_python() {
  if [ -n "$PYTHON" ]; then
    printf '%s' "$PYTHON"
    return 0
  fi
  local cand
  for cand in python python3 py; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys' >/dev/null 2>&1; then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

to_posix_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p" 2>/dev/null || printf '%s' "$p"
  else
    printf '%s' "$p"
  fi
}

find_godot() {
  if [ -n "$GODOT_BIN" ]; then
    printf '%s' "$GODOT_BIN"
    return 0
  fi
  if [ -f "$GODOT_PATH_FILE" ]; then
    local line
    line="$(grep -v '^[[:space:]]*#' "$GODOT_PATH_FILE" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)"
    if [ -n "$line" ]; then
      printf '%s' "$line"
      return 0
    fi
  fi
  local cand
  for cand in godot godot4 godot4.7 \
      Godot_v4.7.2-stable_win64_console.exe Godot_v4.7.2-stable_win64.exe Godot.exe; do
    if command -v "$cand" >/dev/null 2>&1; then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

# ------------------------------------------------------------------ 前置检查
printf '仓库根：%s\n' "$ROOT"

PYTHON="$(find_python)" || {
  printf '错误：找不到可用的 Python 解释器（试过 python / python3 / py）。\n' >&2
  printf '请用 --python <命令> 指定，例如：bash tools/run_tests.sh --python "C:/Python311/python.exe"\n' >&2
  exit 1
}
printf 'Python：%s（%s）\n' "$PYTHON" "$("$PYTHON" --version 2>&1)"

if [ "$NO_GODOT" -eq 1 ]; then
  GODOT_BIN=""
else
  GODOT_BIN="$(find_godot)" || GODOT_BIN=""
fi
if [ -n "$GODOT_BIN" ]; then
  GODOT_BIN="$(to_posix_path "$GODOT_BIN")"
  printf 'Godot ：%s\n' "$GODOT_BIN"
else
  printf 'Godot ：未找到 —— Godot 段将跳过（用 --godot <完整路径> 指定）\n'
fi

# ------------------------------------------------------------------ ① 六道门
GATES="check_config test_core verify_formula check_metrics diversity_report check_docs"
for gate in $GATES; do
  if [ -f "tools/$gate.py" ]; then
    run_step "门 $gate" "$PYTHON" "tools/$gate.py"
  else
    printf '\n=== 门 %s ===\n' "$gate"
    mark_skip "门 $gate（tools/$gate.py 不存在）"
  fi
done

# ------------------------------------------------------- ①b 导出前置检查
# 不属于六道门，但导出 APK 前必须通过：CSV 若不是 keep 模式，安卓包会丢表。
printf '\n=== 导出前置检查 ===\n'
if [ -f "tools/check_export_imports.py" ]; then
  run_step "导出前检查 check_export_imports" "$PYTHON" "tools/check_export_imports.py"
else
  printf '\n=== 导出前检查 ===\n'
  mark_skip "导出前检查（tools/check_export_imports.py 不存在）"
fi

# ------------------------------------------------------- ①c 字体子集覆盖检查
# 包体内的 UI 字体是子集化的（2026-10-18 起，约 0.9 MiB）。新增文案若出现新字符，
# 运行期会显示方框；这里提前失败，提示重建子集（python tools/subset_font.py --write）。
printf '\n=== 字体子集覆盖检查 ===\n'
if [ -f "tools/subset_font.py" ]; then
  run_step "字体子集 check_font_subset" "$PYTHON" "tools/subset_font.py"
else
  printf '\n=== 字体子集覆盖检查 ===\n'
  mark_skip "字体子集检查（tools/subset_font.py 不存在）"
fi

# -------------------------------------------------------------- ② 铁律测试
INVARIANTS="check_no_character_id check_observer_readonly check_magic_numbers"
for inv in $INVARIANTS; do
  if [ -f "tests/invariants/$inv.py" ]; then
    run_step "铁律 $inv" "$PYTHON" "tests/invariants/$inv.py"
  else
    printf '\n=== 铁律 %s ===\n' "$inv"
    mark_skip "铁律 $inv（tests/invariants/$inv.py 不存在）"
  fi
done

# ------------------------------------------------------- ③ 逐 tick 对拍（离线）
printf '\n=== 对拍：Python ↔ GDScript 逐 tick ===\n'
if [ -f "tests/integration/test_tick_parity.py" ]; then
  if [ -n "$GODOT_BIN" ]; then
    run_step "对拍 test_tick_parity" "$PYTHON" "tests/integration/test_tick_parity.py" --godot "$GODOT_BIN"
  else
    run_step "对拍 test_tick_parity" "$PYTHON" "tests/integration/test_tick_parity.py"
  fi
else
  mark_skip "对拍（tests/integration/test_tick_parity.py 不存在）"
fi

# ------------------------------------------------------------------ ④ Godot
printf '\n=== Godot 段 ===\n'
if [ -z "$GODOT_BIN" ]; then
  mark_skip "Godot 段（未指定 Godot 可执行文件）"
elif [ ! -f "addons/gut/gut_cmdln.gd" ]; then
  mark_skip "GUT 单测（addons/gut 未接入）"
else
  run_step "GUT 单测（tests/unit）" \
    "$GODOT_BIN" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
  run_step "GUT 涌现验收（tests/emergence，当前全部 pending）" \
    "$GODOT_BIN" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/emergence -gexit
fi

# ------------------------------------------------------------------ 汇总
printf '\n===================================\n'
printf '汇总：通过 %d 段，失败 %d 段，跳过 %d 段\n' "$RESULT_PASS" "$RESULT_FAIL" "$RESULT_SKIP"
if [ "$RESULT_FAIL" -gt 0 ]; then
  printf '结论：有失败 —— 见上方 [FAIL]\n'
  exit 1
fi
printf '结论：全部通过（跳过段不视为失败）\n'
exit 0
