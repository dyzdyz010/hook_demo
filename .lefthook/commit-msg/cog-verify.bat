@echo off
setlocal EnableExtensions

where cog >nul 2>nul
if errorlevel 1 (
  echo [commit-msg] ERROR: cog not found in PATH
  exit /b 2
)

rem %1 是提交说明文件路径
cog verify --file "%~1"
exit /b %ERRORLEVEL%
