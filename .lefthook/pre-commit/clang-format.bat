echo "clang-format.bat"
setlocal EnableExtensions EnableDelayedExpansion

where clang-format >nul 2>nul
if errorlevel 1 (
  echo [pre-commit] ERROR: clang-format not found in PATH
  exit /b 2
)

set "TMPDIR=%TEMP%\lhk_cf_%RANDOM%%RANDOM%"
mkdir "%TMPDIR%" >nul 2>nul

set "STAGED_LIST=%TMPDIR%\staged.txt"
git diff --cached --name-only --diff-filter=ACMR > "%STAGED_LIST%"

set "CHANGED=0"
set "SKIPPED_WORKTREE=0"

for /f "usebackq delims=" %%F in ("%STAGED_LIST%") do (
  set "FILE=%%F"
  if "!FILE!"=="" goto :continue_file

  rem 仅处理常见 C/C++ 文件（按需扩展）
  call :IsCppFile "!FILE!"
  if errorlevel 1 goto :continue_file

  rem 工作区是否干净（working tree vs index）
  git diff --quiet -- "!FILE!"
  if errorlevel 1 (
    set "WT_CLEAN=0"
  ) else (
    set "WT_CLEAN=1"
  )

  rem 从 index 取 staged 版本到临时文件
  git show ":!FILE!" > "%TMPDIR%\in.txt" 2>nul
  if errorlevel 1 goto :continue_file

  rem 格式化 staged 内容输出到 out
  clang-format --style=file --assume-filename="!FILE!" "%TMPDIR%\in.txt" > "%TMPDIR%\out.txt"
  if errorlevel 1 (
    echo [pre-commit] ERROR: clang-format failed on "!FILE!"
    exit /b 1
  )

  rem 比较 in/out 是否不同（按二进制比较）
  fc /b "%TMPDIR%\in.txt" "%TMPDIR%\out.txt" >nul
  if not errorlevel 1 (
    goto :continue_file
  )

  rem 发生变化：写回 index（保持原 mode）
  for /f "tokens=1" %%M in ('git ls-files -s -- "!FILE!"') do set "MODE=%%M"
  if "!MODE!"=="" goto :continue_file

  for /f "usebackq delims=" %%H in (`git hash-object -w "%TMPDIR%\out.txt"`) do set "NEWHASH=%%H"
  if "!NEWHASH!"=="" goto :continue_file

  git update-index --cacheinfo !MODE! !NEWHASH! "!FILE!"
  if errorlevel 1 (
    echo [pre-commit] ERROR: failed to update index for "!FILE!"
    exit /b 1
  )

  set "CHANGED=1"

  rem 若工作区没有未暂存改动，则安全同步工作区，避免 staged/unstaged 双重 modified
  if "!WT_CLEAN!"=="1" (
    copy /y "%TMPDIR%\out.txt" "!FILE!" >nul
  ) else (
    set "SKIPPED_WORKTREE=1"
  )

  :continue_file
)

if "%CHANGED%"=="1" (
  echo.
  echo 已格式化本次提交内容（已写入 staged/index）。
  echo 请复核后重新 commit：git diff --cached
  if "%SKIPPED_WORKTREE%"=="1" (
    echo 注意：部分文件工作区存在未暂存改动，为避免覆盖，本次未同步写回工作区文件。
  )
  echo.
  exit /b 1
)

exit /b 0


:IsCppFile
set "P=%~1"
set "EXT=%~x1"
if /i "%EXT%"==".c"   exit /b 0
if /i "%EXT%"==".cc"  exit /b 0
if /i "%EXT%"==".cpp" exit /b 0
if /i "%EXT%"==".cxx" exit /b 0
if /i "%EXT%"==".h"   exit /b 0
if /i "%EXT%"==".hh"  exit /b 0
if /i "%EXT%"==".hpp" exit /b 0
if /i "%EXT%"==".hxx" exit /b 0
exit /b 1
