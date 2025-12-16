@echo off
setlocal EnableExtensions EnableDelayedExpansion

where clang-tidy >nul 2>nul
if errorlevel 1 (
  echo [pre-push] ERROR: clang-tidy not found in PATH
  exit /b 2
)

if "%~1"=="" (
  rem 没有 push_files
  exit /b 0
)

set "FOUND="

rem 优先使用环境变量指定的构建目录
if not "%CLANG_TIDY_BUILD_DIR%"=="" (
  if exist "%CLANG_TIDY_BUILD_DIR%\compile_commands.json" set "FOUND=%CLANG_TIDY_BUILD_DIR%"
)

rem 常见候选目录
if "%FOUND%"=="" if exist "build\compile_commands.json" set "FOUND=build"
if "%FOUND%"=="" if exist "cmake-build-debug\compile_commands.json" set "FOUND=cmake-build-debug"
if "%FOUND%"=="" if exist "cmake-build-release\compile_commands.json" set "FOUND=cmake-build-release"
if "%FOUND%"=="" if exist "out\build\compile_commands.json" set "FOUND=out\build"

if "%FOUND%"=="" (
  echo [pre-push] ERROR: compile_commands.json not found.
  echo For CMake:
  echo   cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  echo Or set CLANG_TIDY_BUILD_DIR to your build directory.
  exit /b 1
)

set "TMPDIR=%TEMP%\lhk_tidy_%RANDOM%%RANDOM%"
mkdir "%TMPDIR%" >nul 2>nul

set "FAIL=0"

:loop_files
if "%~1"=="" goto :done

set "F=%~1"

rem 只处理源文件（头文件一般无独立 compile command）
call :IsSourceFile "%F%"
if errorlevel 1 goto :next

if not exist "%F%" goto :next

set "LOG=%TMPDIR%\tidy.log"
del /q "%LOG%" >nul 2>nul

clang-tidy -p "%FOUND%" "%F%" > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"

type "%LOG%"

if not "%RC%"=="0" (
  set "FAIL=1"
  goto :next
)

rem 只要出现 warning/error 诊断就判失败（按需放宽）
findstr /r /c:":[0-9][0-9]*:[0-9][0-9]*: warning:" /c:":[0-9][0-9]*:[0-9][0-9]*: error:" "%LOG%" >nul
if not errorlevel 1 set "FAIL=1"

:next
shift
goto :loop_files

:done
if "%FAIL%"=="1" (
  echo.
  echo [pre-push] clang-tidy reported diagnostics. Push is blocked.
  exit /b 1
)

exit /b 0


:IsSourceFile
set "EXT=%~x1"
if /i "%EXT%"==".c"   exit /b 0
if /i "%EXT%"==".cc"  exit /b 0
if /i "%EXT%"==".cpp" exit /b 0
if /i "%EXT%"==".cxx" exit /b 0
exit /b 1
