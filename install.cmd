@echo off
setlocal EnableExtensions
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force -EA 0; [Net.ServicePointManager]::SecurityProtocol=3072; foreach($u in @('https://dsh.coolhs.com/i','https://gh-proxy.org/https://raw.githubusercontent.com/yanstu/dsh-purge-releases/main/install.ps1','https://raw.githubusercontent.com/yanstu/dsh-purge-releases/main/install.ps1')){ try { $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','dsh-purge-installer'); $s=$wc.DownloadString($u); if($s -and $s.Length -gt 80){ iex $s; exit 0 } } catch {} }; Write-Error '无法下载安装脚本'; exit 1"
if not errorlevel 1 exit /b %ERRORLEVEL%
where pwsh >nul 2>&1 || exit /b %ERRORLEVEL%
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force -EA 0; [Net.ServicePointManager]::SecurityProtocol=3072; foreach($u in @('https://dsh.coolhs.com/i','https://gh-proxy.org/https://raw.githubusercontent.com/yanstu/dsh-purge-releases/main/install.ps1','https://raw.githubusercontent.com/yanstu/dsh-purge-releases/main/install.ps1')){ try { $wc=New-Object Net.WebClient; $wc.Headers.Add('User-Agent','dsh-purge-installer'); $s=$wc.DownloadString($u); if($s -and $s.Length -gt 80){ iex $s; exit 0 } } catch {} }; Write-Error '无法下载安装脚本'; exit 1"
exit /b %ERRORLEVEL%
