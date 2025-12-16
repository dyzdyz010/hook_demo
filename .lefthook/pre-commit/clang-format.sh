#!/usr/bin/env sh

command -v clang-format >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "[pre-commit] 错误：PATH 中未找到 clang-format" >&2
  exit 2
fi

TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t lhk_cf)
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

STAGED_LIST="$TMPDIR/staged.txt"
git diff --cached --name-only --diff-filter=ACMR >"$STAGED_LIST"

CHANGED=0
SKIPPED_WORKTREE=0

is_cpp_file() {
  case "$1" in
    *.c | *.cc | *.cpp | *.cxx | *.h | *.hh | *.hpp | *.hxx) return 0 ;;
    *) return 1 ;;
  esac
}

while IFS= read -r FILE; do
  [ -z "$FILE" ] && continue

  is_cpp_file "$FILE" || continue

  if git diff --quiet -- "$FILE"; then
    WT_CLEAN=1
  else
    WT_CLEAN=0
  fi

  if ! git show ":$FILE" >"$TMPDIR/in.txt" 2>/dev/null; then
    continue
  fi

  clang-format --style=file --assume-filename="$FILE" "$TMPDIR/in.txt" >"$TMPDIR/out.txt"
  if [ $? -ne 0 ]; then
    echo "[pre-commit] 错误：clang-format 处理 \"$FILE\" 失败" >&2
    exit 1
  fi

  if cmp -s "$TMPDIR/in.txt" "$TMPDIR/out.txt"; then
    continue
  fi

  MODE=$(git ls-files -s -- "$FILE" | awk '{print $1}')
  [ -z "$MODE" ] && continue

  NEWHASH=$(git hash-object -w "$TMPDIR/out.txt")
  [ -z "$NEWHASH" ] && continue

  git update-index --cacheinfo "$MODE" "$NEWHASH" "$FILE"
  if [ $? -ne 0 ]; then
    echo "[pre-commit] 错误：更新索引 \"$FILE\" 失败" >&2
    exit 1
  fi

  CHANGED=1

  if [ "$WT_CLEAN" -eq 1 ]; then
    cp "$TMPDIR/out.txt" "$FILE"
  else
    SKIPPED_WORKTREE=1
  fi
done <"$STAGED_LIST"

if [ "$CHANGED" -eq 1 ]; then
  echo
  echo "[pre-commit] 已格式化暂存内容并更新索引。"
  echo "请复核：git diff --cached"
  if [ "$SKIPPED_WORKTREE" -eq 1 ]; then
    echo "注意：因工作区有未暂存的修改，已跳过写回工作区。"
  fi
  echo
  exit 1
fi

exit 0
