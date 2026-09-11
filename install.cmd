@echo off
setlocal EnableExtensions
set "PATH=%AppData%\npm;%LOCALAPPDATA%\npm;%PATH%"
set "VER=v1.3.5"
set "TGZ=%TEMP%\dsh-purge.tgz"
set "URL1=https://cdn.jsdelivr.net/gh/yanstu/dsh-purge-releases@%VER%/dsh-purge.tgz"
set "URL2=https://gh-proxy.org/https://github.com/yanstu/dsh-purge-releases/releases/download/%VER%/dsh-purge.tgz"
set "URL3=https://github.com/yanstu/dsh-purge-releases/releases/download/%VER%/dsh-purge.tgz"

if not exist "%AppData%\npm" mkdir "%AppData%\npm" >nul 2>&1

where node >nul 2>&1
if errorlevel 1 (
  echo 未找到 Node.js。请先安装 Node.js 18 或更高版本，安装时勾选 Add to PATH，关闭命令提示符后重新打开再运行本脚本。
  exit /b 1
)

where dsh >nul 2>&1
if errorlevel 1 (
  echo 正在安装 dsh...
  call npm install -g @deepseek-ai/dsh
  set "PATH=%AppData%\npm;%PATH%"
)
where dsh >nul 2>&1
if errorlevel 1 (
  echo 仍未找到 dsh。请关闭命令提示符后重新打开，再运行本脚本。
  exit /b 1
)

where pnpm >nul 2>&1
if errorlevel 1 (
  echo 正在安装 pnpm...
  call npm install -g pnpm --allow-scripts=pnpm
  set "PATH=%AppData%\npm;%PATH%"
)
if exist "%AppData%\npm\pnpm.cmd" set "PATH=%AppData%\npm;%PATH%"
where pnpm >nul 2>&1
if errorlevel 1 (
  echo 仍未找到 pnpm。请关闭命令提示符后重新打开，再运行本脚本。
  exit /b 1
)

del /f /q "%TGZ%" >nul 2>&1
call :fetch "%URL1%"
if errorlevel 1 call :fetch "%URL2%"
if errorlevel 1 call :fetch "%URL3%"
if errorlevel 1 (
  echo 安装包下载失败。不要使用 GitHub 源码 zip，dsh plugin add 只接受 .tgz。
  exit /b 1
)

for %%A in ("%TGZ%") do set "SZ=%%~zA"
if not defined SZ set "SZ=0"
if %SZ% LSS 100000 (
  echo 下载到的文件无效。
  exit /b 1
)

set "PROFILE=%~1"
if "%PROFILE%"=="" (
  call dsh plugin --profile web add "%TGZ%"
  if errorlevel 1 exit /b 1
  call dsh plugin --profile default add "%TGZ%"
  if errorlevel 1 (
    echo 网页 profile 已装好。桌面 profile 若不存在可忽略；存在则请指定：install.cmd default
    exit /b 0
  )
  echo 已写入网页与桌面 profile。请完全退出 dsh web 和桌面客户端后重新打开，再应用补丁或发送 /purge apply。
  exit /b 0
)

call dsh plugin --profile %PROFILE% add "%TGZ%"
exit /b %ERRORLEVEL%

:fetch
echo 正在下载 %~1
curl.exe -fsSL --retry 2 --connect-timeout 20 -o "%TGZ%" "%~1" 2>nul
if not errorlevel 1 exit /b 0
powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -Uri '%~1' -OutFile '%TGZ%'; exit 0 } catch { exit 1 }"
exit /b %ERRORLEVEL%
