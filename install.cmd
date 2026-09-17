@echo off
setlocal EnableExtensions
powershell -NoProfile -ExecutionPolicy Bypass -Command "foreach($u in @('https://dsh.coolhs.com/i','https://gh-proxy.org/https://raw.githubusercontent.com/yanstu/dsh-purge-releases/main/install.ps1','https://raw.githubusercontent.com/yanstu/dsh-purge-releases/main/install.ps1','https://fastly.jsdelivr.net/gh/yanstu/dsh-purge-releases@main/install.ps1')){try{$s=irm $u;if($s){iex $s;exit 0}}catch{}}; Write-Error '无法下载安装脚本'; exit 1"
exit /b %ERRORLEVEL%
