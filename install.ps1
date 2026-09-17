# Windows PowerShell 2+ / PowerShell 7
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch {}
$ErrorActionPreference = 'Stop'
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
} catch {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]3072 } catch {}
}
try { [Net.ServicePointManager]::Expect100Continue = $false } catch {}

$Boot = Join-Path $env:LOCALAPPDATA 'dsh-bootstrap'
$NodeHome = Join-Path $Boot 'node'
$NpmPrefix = Join-Path $Boot 'npm'
$Tgz = Join-Path $env:TEMP 'dsh-purge.tgz'
$PinnedNode = '22.20.0'
$Rel = 'v1.3.5'
$Repo = 'yanstu/dsh-purge-releases'
$RegCn = 'https://registry.npmmirror.com'
$RegIo = 'https://registry.npmjs.org'

function Test-Blank([string]$Value) {
  return ($null -eq $Value) -or ($Value.Trim().Length -eq 0)
}

function Write-Step([string]$Message) {
  Write-Host $Message
}

function Test-Cmd([string]$Name) {
  return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
}

function Copy-Stream($Source, $Dest) {
  $buffer = New-Object byte[] 8192
  while (($n = $Source.Read($buffer, 0, $buffer.Length)) -gt 0) {
    $Dest.Write($buffer, 0, $n)
  }
}

function Import-MachinePath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $npmRoaming = Join-Path $env:AppData 'npm'
  $env:Path = "$NodeHome;$NpmPrefix;$npmRoaming;$user;$machine;$env:Path"
}

function Add-UserPath([string]$Dir) {
  if (-not (Test-Path -LiteralPath $Dir)) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
  }
  $current = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (Test-Blank $current) {
    $current = ''
  }
  $parts = @($current -split ';' | Where-Object { $_ -and ($_ -ne $Dir) })
  [Environment]::SetEnvironmentVariable('Path', (@($Dir) + $parts) -join ';', 'User')
  if ($env:Path -notlike "*$Dir*") {
    $env:Path = "$Dir;$env:Path"
  }
}

function Expand-ZipFile([string]$ZipPath, [string]$DestPath) {
  if (Test-Path -LiteralPath $DestPath) {
    Remove-Item -LiteralPath $DestPath -Recurse -Force
  }
  New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
  $zipFull = [IO.Path]::GetFullPath($ZipPath)
  $destFull = [IO.Path]::GetFullPath($DestPath)
  if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
    Expand-Archive -LiteralPath $zipFull -DestinationPath $destFull -Force
    return
  }
  $ok = $false
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zipFull, $destFull)
    $ok = $true
  } catch {
    $ok = $false
  }
  if ($ok) {
    return
  }
  $shell = New-Object -ComObject Shell.Application
  $zipNs = $shell.NameSpace($zipFull)
  $destNs = $shell.NameSpace($destFull)
  if (-not $zipNs -or -not $destNs) {
    throw '无法解压 Node.js 压缩包。'
  }
  $destNs.CopyHere($zipNs.Items(), 20)
  $deadline = (Get-Date).AddSeconds(180)
  do {
    Start-Sleep -Seconds 1
    $n = @($destNs.Items()).Count
  } while (($n -lt 1) -and ((Get-Date) -lt $deadline))
  Start-Sleep -Seconds 2
}

function Save-Url {
  param(
    [string]$Url,
    [string]$OutFile,
    [int]$TimeoutSec = 45,
    [int]$MinBytes = 1
  )
  $parent = Split-Path -Parent $OutFile
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  if (Test-Path -LiteralPath $OutFile) {
    Remove-Item -LiteralPath $OutFile -Force
  }
  $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
  if ($curl) {
    foreach ($extra in @(@(), @('--ipv4'))) {
      $curlArgs = @('-fsSL', '--connect-timeout', '12', '--max-time', "$TimeoutSec", '-A', 'dsh-purge-installer', '-o', $OutFile, $Url) + $extra
      & curl.exe @curlArgs 2>$null
      if (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -ge $MinBytes)) {
        return $true
      }
    }
  }
  try {
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Timeout = $TimeoutSec * 1000
    $req.ReadWriteTimeout = $TimeoutSec * 1000
    $req.UserAgent = 'dsh-purge-installer'
    $req.AllowAutoRedirect = $true
    $resp = $req.GetResponse()
    try {
      $src = $resp.GetResponseStream()
      $fs = [IO.File]::Create($OutFile)
      try {
        Copy-Stream $src $fs
      } finally {
        $fs.Close()
      }
    } finally {
      $resp.Close()
    }
    return ((Get-Item -LiteralPath $OutFile).Length -ge $MinBytes)
  } catch {
  }
  try {
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', 'dsh-purge-installer')
    $wc.DownloadFile($Url, $OutFile)
    return ((Test-Path -LiteralPath $OutFile) -and ((Get-Item -LiteralPath $OutFile).Length -ge $MinBytes))
  } catch {
    return $false
  }
}

function Test-Url([string]$Url, [int]$TimeoutSec = 8) {
  $tmp = Join-Path $env:TEMP ("dsh-probe-" + [Guid]::NewGuid().ToString('n'))
  try {
    return (Save-Url -Url $Url -OutFile $tmp -TimeoutSec $TimeoutSec -MinBytes 1)
  } finally {
    if (Test-Path -LiteralPath $tmp) {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
  }
}

function Test-GzipFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return $false
  }
  $fs = [IO.File]::OpenRead($Path)
  try {
    $buf = New-Object byte[] 2
    if ($fs.Read($buf, 0, 2) -lt 2) {
      return $false
    }
    return (($buf[0] -eq 0x1F) -and ($buf[1] -eq 0x8B))
  } finally {
    $fs.Close()
  }
}

function Get-NodeMajor {
  if (-not (Test-Cmd 'node')) {
    return 0
  }
  try {
    $raw = (& node -p "process.versions.node.split('.')[0]" 2>$null)
    return [int]$raw
  } catch {
    return 0
  }
}

function Get-NodeArch {
  $arch = $env:PROCESSOR_ARCHITECTURE
  $wow = $env:PROCESSOR_ARCHITEW6432
  if (($arch -eq 'ARM64') -or ($wow -eq 'ARM64')) {
    return 'arm64'
  }
  if (($arch -eq 'AMD64') -or ($wow -eq 'AMD64')) {
    return 'x64'
  }
  return 'x86'
}

function Get-NodeLts([string]$FileTag) {
  if (-not (Get-Command ConvertFrom-Json -ErrorAction SilentlyContinue)) {
    return $PinnedNode
  }
  foreach ($idx in @('https://npmmirror.com/mirrors/node/index.json', 'https://nodejs.org/dist/index.json')) {
    $tmp = Join-Path $env:TEMP 'dsh-node-index.json'
    if (-not (Save-Url -Url $idx -OutFile $tmp -TimeoutSec 12 -MinBytes 100)) {
      continue
    }
    try {
      $text = [IO.File]::ReadAllText($tmp)
      $data = $text | ConvertFrom-Json
      foreach ($row in $data) {
        if ($row.lts -and ($row.files -contains $FileTag)) {
          return ([string]$row.version).TrimStart('v')
        }
      }
    } catch {
    }
  }
  return $PinnedNode
}

function Install-PortableNode {
  $arch = Get-NodeArch
  $fileTag = "win-$arch-zip"
  $ver = Get-NodeLts $fileTag
  $zipName = "node-v$ver-win-$arch.zip"
  $zip = Join-Path $env:TEMP $zipName
  $urls = @(
    "https://npmmirror.com/mirrors/node/v$ver/$zipName",
    "https://cdn.npmmirror.com/binaries/node/v$ver/$zipName",
    "https://nodejs.org/dist/v$ver/$zipName"
  )
  Write-Step "未找到可用的 Node.js，正在安装 $ver（用户目录，无需管理员）..."
  $got = $false
  foreach ($url in $urls) {
    Write-Step "正在下载 $url"
    if (Save-Url -Url $url -OutFile $zip -TimeoutSec 90 -MinBytes 1000000) {
      $got = $true
      break
    }
  }
  if (-not $got) {
    if (Test-Cmd 'winget') {
      Write-Step '压缩包下载失败，改用 winget 安装 Node.js LTS...'
      & winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
      Import-MachinePath
      return
    }
    throw '无法下载 Node.js。请稍后重试，或先安装 Node.js 18 及以上再执行同一条命令。'
  }
  $extract = Join-Path $env:TEMP ("node-extract-" + $ver)
  Expand-ZipFile -ZipPath $zip -DestPath $extract
  $inner = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
  if (-not $inner) {
    throw 'Node.js 压缩包内容无效。'
  }
  if (Test-Path -LiteralPath $NodeHome) {
    Remove-Item -LiteralPath $NodeHome -Recurse -Force
  }
  New-Item -ItemType Directory -Path $Boot -Force | Out-Null
  Move-Item -LiteralPath $inner.FullName -Destination $NodeHome
  Add-UserPath $NodeHome
  Import-MachinePath
}

function Resolve-Node {
  Import-MachinePath
  $common = New-Object System.Collections.ArrayList
  [void]$common.Add($NodeHome)
  if ($env:ProgramFiles) {
    [void]$common.Add((Join-Path $env:ProgramFiles 'nodejs'))
  }
  $pf86 = ${env:ProgramFiles(x86)}
  if ($pf86) {
    [void]$common.Add((Join-Path $pf86 'nodejs'))
  }
  if ($env:LOCALAPPDATA) {
    [void]$common.Add((Join-Path $env:LOCALAPPDATA 'Programs\nodejs'))
  }
  if ($env:USERPROFILE) {
    [void]$common.Add((Join-Path $env:USERPROFILE 'scoop\apps\nodejs\current'))
  }
  if ($env:NVM_HOME) {
    [void]$common.Add($env:NVM_HOME)
  }
  foreach ($dir in $common) {
    if ($dir -and (Test-Path -LiteralPath (Join-Path $dir 'node.exe'))) {
      $env:Path = "$dir;$env:Path"
    }
  }
  if (((Get-NodeMajor) -ge 18) -and (Test-Cmd 'npm')) {
    return
  }
  Install-PortableNode
  if (((Get-NodeMajor) -lt 18) -or (-not (Test-Cmd 'npm'))) {
    throw '仍未找到 Node.js 18 或更高版本。'
  }
}

function Get-Registries {
  $order = New-Object System.Collections.ArrayList
  if (Test-Url "$RegCn/@deepseek-ai/dsh") {
    [void]$order.Add($RegCn)
  }
  if (Test-Url "$RegIo/@deepseek-ai/dsh") {
    [void]$order.Add($RegIo)
  }
  if ($order.Count -eq 0) {
    [void]$order.Add($RegCn)
    [void]$order.Add($RegIo)
  }
  return ,$order.ToArray()
}

function Use-Registry([string]$Registry) {
  $env:npm_config_registry = $Registry
  $env:PNPM_REGISTRY = $Registry
}

function Invoke-NpmInstall([string[]]$Packages) {
  $prefix = $null
  try {
    $prefix = (& npm prefix -g 2>$null)
  } catch {
    $prefix = $null
  }
  if (-not $prefix -or -not (Test-Path -LiteralPath $prefix)) {
    $prefix = $NpmPrefix
  }
  $writable = $false
  try {
    $probe = Join-Path $prefix ('.dsh-write-' + [Guid]::NewGuid().ToString('n'))
    New-Item -ItemType File -Path $probe -Force | Out-Null
    Remove-Item -LiteralPath $probe -Force
    $writable = $true
  } catch {
    $writable = $false
  }
  if (-not $writable) {
    New-Item -ItemType Directory -Path $NpmPrefix -Force | Out-Null
    $env:npm_config_prefix = $NpmPrefix
    Add-UserPath $NpmPrefix
  } else {
    Add-UserPath $prefix
  }
  $npmDir = Join-Path $env:AppData 'npm'
  if (-not (Test-Path -LiteralPath $npmDir)) {
    New-Item -ItemType Directory -Path $npmDir -Force | Out-Null
  }
  Add-UserPath $npmDir
  $ok = $false
  $last = ''
  foreach ($reg in $script:Registries) {
    Use-Registry $reg
    Write-Step "正在从 $reg 安装 $($Packages -join ' ') ..."
    $npmArgs = @('install', '-g') + $Packages + @('--registry', $reg)
    & npm @npmArgs
    if ($LASTEXITCODE -eq 0) {
      $ok = $true
      break
    }
    $last = "npm 退出码 $LASTEXITCODE @ $reg"
  }
  Import-MachinePath
  if (-not $ok) {
    throw "安装失败：$last"
  }
}

function Get-TarballUrls {
  return @(
    'https://dsh.coolhs.com/dsh-purge.tgz',
    "https://cdn.jsdelivr.net/gh/$Repo/dsh-purge.tgz",
    "https://fastly.jsdelivr.net/gh/$Repo/dsh-purge.tgz",
    "https://gcore.jsdelivr.net/gh/$Repo/dsh-purge.tgz",
    "https://cdn.jsdelivr.net/gh/$Repo@$Rel/dsh-purge.tgz",
    "https://gh-proxy.org/https://github.com/$Repo/releases/download/$Rel/dsh-purge.tgz",
    "https://ghproxy.net/https://github.com/$Repo/releases/download/$Rel/dsh-purge.tgz",
    "https://github.com/$Repo/releases/download/$Rel/dsh-purge.tgz"
  )
}

function Save-Tarball {
  foreach ($url in Get-TarballUrls) {
    Write-Step "正在下载安装包 $url"
    if ((Save-Url -Url $url -OutFile $Tgz -TimeoutSec 45 -MinBytes 100000) -and (Test-GzipFile $Tgz)) {
      return
    }
    Write-Step '该源不可用，换下一个。'
  }
  throw '安装包下载失败。请检查网络后重试同一条命令。'
}

function Add-Plugin([string]$ProfileName) {
  & dsh plugin --profile $ProfileName add $Tgz
  if ($LASTEXITCODE -ne 0) {
    throw "写入 $ProfileName 失败"
  }
}

Import-MachinePath
New-Item -ItemType Directory -Path $Boot -Force | Out-Null
Resolve-Node

$script:Registries = Get-Registries
Use-Registry $script:Registries[0]
Write-Step "npm 将优先使用 $($script:Registries[0])，失败时自动换源。"

if (-not (Test-Cmd 'dsh')) {
  Invoke-NpmInstall @('@deepseek-ai/dsh')
}
if (-not (Test-Cmd 'dsh')) {
  throw '仍未找到 dsh。请关闭终端后重新打开，再执行同一条命令。'
}

if (-not (Test-Cmd 'pnpm')) {
  try {
    Invoke-NpmInstall @('pnpm', '--allow-scripts=pnpm')
  } catch {
    Invoke-NpmInstall @('pnpm')
  }
}
if (-not (Test-Cmd 'pnpm')) {
  throw '仍未找到 pnpm。请关闭终端后重新打开，再执行同一条命令。'
}

Save-Tarball

$ProfileName = $args[0]
if (Test-Blank $ProfileName) {
  Add-Plugin 'web'
  try {
    Add-Plugin 'default'
  } catch {
    Write-Step '网页 profile 已装好。桌面 profile 若不存在可忽略。'
  }
} else {
  Add-Plugin $ProfileName
}

Write-Step '安装完成。请完全退出 dsh web 和桌面客户端后重新打开，再应用补丁或发送 /purge apply。'
