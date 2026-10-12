# 一键装 Android SDK（Windows / PowerShell）
#
# 用途：本项目要导出 Android APK，但本机还没装 Android SDK。
# 这个脚本下载 Google 官方的 command line tools，装好 platform-tools / platforms / build-tools，
# 并打印「接下来在 Godot 编辑器里要填什么、点什么」。
#
# 用法（在项目根目录打开 PowerShell）：
#     powershell -ExecutionPolicy Bypass -File tools/setup_android_sdk.ps1
#
# 装完之后还需要在 Godot 编辑器里手动填两个路径 + 下导出模板，脚本最后会打印出来。

$ErrorActionPreference = 'Stop'

# ---- 可按需改这两个 ----
$SdkRoot = 'D:\Android\Sdk'                                  # SDK 装到哪
$ToolsUrl = 'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip'
$AndroidPlatform = 'android-34'
$BuildTools = '34.0.0'

Write-Host "=== 1/5 准备目录 ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $SdkRoot | Out-Null
$cmdlineDir = Join-Path $SdkRoot 'cmdline-tools'
New-Item -ItemType Directory -Force -Path $cmdlineDir | Out-Null
Write-Host "  SDK 根目录：$SdkRoot"

Write-Host "=== 2/5 下载 command line tools ===" -ForegroundColor Cyan
$zip = Join-Path $env:TEMP 'cmdline-tools.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
# 走系统代理设置；如果你的代理是 127.0.0.1:7890，下面这行会自动用上
Invoke-WebRequest -Uri $ToolsUrl -OutFile $zip -UseBasicParsing
Write-Host ("  已下载 {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))

Write-Host "=== 3/5 解压到 cmdline-tools/latest ===" -ForegroundColor Cyan
$tmp = Join-Path $env:TEMP 'cmdline-tools-unzip'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $tmp -Force
$latest = Join-Path $cmdlineDir 'latest'
if (Test-Path $latest) { Remove-Item $latest -Recurse -Force }
# 压缩包里是 cmdline-tools/bin/...，sdkmanager 要求目录名叫 latest
Move-Item (Join-Path $tmp 'cmdline-tools') $latest
Remove-Item $tmp -Recurse -Force
Remove-Item $zip -Force
Write-Host "  已就位：$latest"

$sdkmanager = Join-Path $latest 'bin\sdkmanager.bat'
if (-not (Test-Path $sdkmanager)) { throw "找不到 sdkmanager：$sdkmanager" }

Write-Host "=== 4/5 接受许可 ===" -ForegroundColor Cyan
Write-Host "  （会连续问几个 y，脚本自动回答 yes）"
$yes = ("y`n" * 12)
$yes | & $sdkmanager --sdk_root="$SdkRoot" --licenses | Out-Null

Write-Host "=== 5/5 安装依赖包 ===" -ForegroundColor Cyan
& $sdkmanager --sdk_root="$SdkRoot" "platform-tools" "platforms;$AndroidPlatform" "build-tools;$BuildTools"

Write-Host ""
Write-Host "装完了。接下来在 Godot 编辑器里做三步（脚本没法代做）：" -ForegroundColor Green
Write-Host ""
Write-Host "  ① 编辑器 → 编辑器设置 → 导出 → Android"
Write-Host "       Java SDK Path    = C:/Users/$env:USERNAME/AppData/Local/Programs/Microsoft/jdk-21.0.7.6-hotspot"
Write-Host "       Android SDK Path = $SdkRoot"
Write-Host ""
Write-Host "  ② 编辑器 → 编辑器 → 管理导出模板 → 下载（把 Android 模板装上）"
Write-Host ""
Write-Host "  ③ 打 APK："
Write-Host "       编辑器里：项目 → 导出 → Android → 导出项目"
Write-Host "       或命令行：godot --headless --path . --export-debug `"Android`" `"build/android/下课十分钟.apk`""
Write-Host ""
Write-Host "签名已经在 export_presets.cfg 里配好了（debug keystore 在 C:/Users/$env:USERNAME/.android/debug.keystore）。"
