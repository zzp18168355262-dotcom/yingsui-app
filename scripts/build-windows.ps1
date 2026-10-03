<#
英语角 / English Corner —— Windows 构建脚本

用法（在本仓库的 Windows PowerShell 里执行）：
    .\scripts\build-windows.ps1                 # release 构建 + 打包 zip
    .\scripts\build-windows.ps1 -SkipPackage    # 只构建，不打包
    .\scripts\build-windows.ps1 -SkipFfmpeg     # 允许缺少内置 ffmpeg（AI 字幕会不可用）

为什么 Windows 要单独一个脚本：
  1) Flutter 不支持交叉编译桌面端 —— Windows 包**只能**在 Windows 上编。
     在 macOS/Linux 上执行 flutter build windows 会直接报不支持。
     所以仓库里的 build-all.sh / build-macos.sh 都覆盖不到它。
  2) 需要 Visual Studio 2022 的「使用 C++ 的桌面开发」工作负载，
     flutter doctor 会检查；缺了会在 CMake 阶段失败。
  3) 应用内的 AI 字幕依赖**内置 ffmpeg**，查找路径固定为
     <exe 所在目录>\ffmpeg\ffmpeg.exe（见 desktop_ffmpeg.dart）。
     flutter build 不会自动打包它，必须在本脚本里补进去，
     否则用户在应用里会看到「应用内置音频组件缺失或无法运行」。
#>

[CmdletBinding()]
param(
    # 只构建，不生成 zip。
    [switch]$SkipPackage,
    # 允许没有内置 ffmpeg（仅用于先看界面）。
    [switch]$SkipFfmpeg
)

$ErrorActionPreference = 'Stop'

# 脚本在 <repo>\scripts\ 下，仓库根目录是它的上一级。
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Write-Step([string]$Text) {
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Fail([string]$Text) {
    Write-Host "错误：$Text" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- 环境检查

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Fail @"
PATH 里找不到 flutter。

请先安装 Flutter 3.44.4（与本仓库其他平台保持一致），并把它加进 PATH：
    https://docs.flutter.dev/get-started/install/windows
装好后新开一个 PowerShell 窗口，执行 flutter --version 确认能看到 3.44.4。
"@
}

Write-Step 'flutter doctor（确认 Visual Studio 工作负载）'
& flutter doctor
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'flutter doctor 报了问题，但不一定影响 Windows 构建，继续尝试。'
}

# ---------------------------------------------------------------- 版本号

$pubspecPath = Join-Path $root 'pubspec.yaml'
$pubspec = Get-Content $pubspecPath -Raw
# 用正向 -match：$Matches 只在这种情况下可靠地被填充（-notmatch 不保证）。
if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)') {
    $version = $Matches[1]
    $buildNumber = $Matches[2]
}
else {
    Fail "在 pubspec.yaml 里读不到形如 0.3.6+36 的 version。"
}
Write-Step "版本：$version+$buildNumber"

# ---------------------------------------------------------------- 内置 ffmpeg

$ffmpegSrcDir = Join-Path $root 'build\ffmpeg-bundle\windows-x64'
$ffmpegSrcExe = Join-Path $ffmpegSrcDir 'ffmpeg.exe'

if (-not (Test-Path $ffmpegSrcExe)) {
    if (-not $SkipFfmpeg) {
        Fail @"
找不到内置 ffmpeg：$ffmpegSrcExe

应用内的 AI 字幕依赖它，缺了会在使用时报
「应用内置音频组件缺失或无法运行」。
它是裁剪编译的（约 2.6 MB），带了 DTS 等影视常见音轨的解码器。

在 Windows 上编译它（需要 MSYS2 + MINGW64）：
    1) 安装 MSYS2：https://www.msys2.org/
    2) 打开「MSYS2 MINGW64」终端，执行：
         pacman -S --needed make diffutils nasm mingw-w64-x86_64-gcc
    3) 回到仓库根目录执行：
         bash tool/ffmpeg/build_ffmpeg.sh windows-x64 build/ffmpeg-bundle/windows-x64

如果只是想先看看界面，加 -SkipFfmpeg 跳过这项检查。
"@
    }
    Write-Warning '缺少内置 ffmpeg：本次构建出来的包，AI 字幕功能不可用。'
}

# ---------------------------------------------------------------- 构建

Write-Step 'flutter pub get'
& flutter pub get
if ($LASTEXITCODE -ne 0) { Fail 'flutter pub get 失败。' }

Write-Step 'flutter build windows --release'
& flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Fail @"
flutter build windows 失败。

最常见的原因是 Visual Studio 缺少「使用 C++ 的桌面开发」工作负载：
    打开 Visual Studio Installer → 修改 → 勾选
    「使用 C++ 的桌面开发」→ 安装后重试。
"@
}

$releaseDir = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path $releaseDir)) {
    Fail "构建结束但找不到产物目录：$releaseDir"
}

# ---------------------------------------------------------------- 嵌入 ffmpeg

if (Test-Path $ffmpegSrcExe) {
    Write-Step '把内置 ffmpeg 复制进发布目录'
    $ffmpegDestDir = Join-Path $releaseDir 'ffmpeg'
    New-Item -ItemType Directory -Force $ffmpegDestDir | Out-Null
    Copy-Item (Join-Path $ffmpegSrcDir '*') $ffmpegDestDir -Recurse -Force

    $bundledExe = Join-Path $ffmpegDestDir 'ffmpeg.exe'
    if (-not (Test-Path $bundledExe)) {
        Fail "ffmpeg 复制失败，$bundledExe 不存在。"
    }
    # 实测能否运行：编译环境不匹配（缺 DLL）会在这里暴露，
    # 而不是等用户在应用里点到 AI 字幕才发现。
    $ffmpegVersion = & $bundledExe -version 2>&1 | Select-Object -First 1
    # 先把退出码取出来再判断：$LASTEXITCODE 会被后续原生命令覆盖。
    $ffmpegExit = $LASTEXITCODE
    if ($ffmpegExit -ne 0) {
        Fail "内置 ffmpeg 无法运行：$bundledExe（$ffmpegVersion）"
    }
    Write-Host "    $ffmpegVersion"
}

# ---------------------------------------------------------------- 打包

$exePath = Join-Path $releaseDir 'yingsui.exe'
if (-not (Test-Path $exePath)) {
    Fail "发布目录里没有 yingsui.exe：$releaseDir"
}

if ($SkipPackage) {
    Write-Step "完成（未打包）：$releaseDir"
    Write-Host '    直接双击其中的 yingsui.exe 即可运行。'
    exit 0
}

$distDir = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $distDir | Out-Null
$zipPath = Join-Path $distDir "EnglishCorner-$version-windows-x64.zip"

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Write-Step '打包 zip'
# 注意：必须把 Release 目录**整包**打进去（exe + DLL + data\ + ffmpeg\），
# 只拷 exe 是跑不起来的。
Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath -CompressionLevel Optimal

$hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
$sizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)

Write-Step "完成：dist\EnglishCorner-$version-windows-x64.zip"
Write-Host "    体积：$sizeMb MB"
Write-Host "    SHA256：$hash"
Write-Host ''
Write-Host '    分发说明：用户解压**整个 zip** 后双击 yingsui.exe，' -ForegroundColor Yellow
Write-Host '    不要只把 exe 单独拷出来 —— 它依赖同目录的 DLL、data\ 和 ffmpeg\。' -ForegroundColor Yellow
