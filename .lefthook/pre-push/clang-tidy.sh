#!/usr/bin/env sh

command -v clang-tidy >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "[pre-push] ERROR: clang-tidy not found in PATH" >&2
  exit 2
fi

if [ "$#" -eq 0 ]; then
  # no push_files
  exit 0
fi

FOUND=""

# prefer build dir set via env var
if [ -n "${CLANG_TIDY_BUILD_DIR:-}" ] && [ -f "$CLANG_TIDY_BUILD_DIR/compile_commands.json" ]; then
  FOUND="$CLANG_TIDY_BUILD_DIR"
fi

# common candidates
[ -z "$FOUND" ] && [ -f "build/compile_commands.json" ] && FOUND="build"
[ -z "$FOUND" ] && [ -f "cmake-build-debug/compile_commands.json" ] && FOUND="cmake-build-debug"
[ -z "$FOUND" ] && [ -f "cmake-build-release/compile_commands.json" ] && FOUND="cmake-build-release"
[ -z "$FOUND" ] && [ -f "out/build/compile_commands.json" ] && FOUND="out/build"

if [ -z "$FOUND" ]; then
  echo "[pre-push] ERROR: compile_commands.json not found." >&2
  echo "For CMake:" >&2
  echo "  cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON" >&2
  echo "Or set CLANG_TIDY_BUILD_DIR to your build directory." >&2
  exit 1
fi

TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t lhk_tidy)
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

FAIL=0

is_source_file() {
  case "$1" in
    *.c | *.cc | *.cpp | *.cxx) return 0 ;;
    *) return 1 ;;
  esac
}

for F in "$@"; do
  [ -z "$F" ] && continue

  is_source_file "$F" || continue
  [ -f "$F" ] || continue

  LOG="$TMPDIR/tidy.log"
  rm -f "$LOG"

  if ! clang-tidy -p "$FOUND" "$F" >"$LOG" 2>&1; then
    cat "$LOG"
    FAIL=1
    continue
  fi

  cat "$LOG"

  # treat any warning/error diagnostic as failure (tighten as needed)
  if grep -E ":[0-9]+:[0-9]+: (warning|error):" "$LOG" >/dev/null 2>&1; then
    FAIL=1
  fi
done

if [ "$FAIL" -eq 1 ]; then
  echo
  echo "[pre-push] clang-tidy reported diagnostics. Push is blocked."
  exit 1
fi

exit 0
