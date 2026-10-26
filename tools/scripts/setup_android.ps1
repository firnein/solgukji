# 안드로이드 빌드 도구를 tools/ 아래에 포터블로 받는다 —— 시스템에는 아무것도 설치하지 않는다.
#   JDK 17 (Temurin) → tools/jdk17
#   Android SDK (명령줄 도구 · platform-tools · build-tools 34 · android-34) → tools/android/sdk
#   Godot 4.4.1 내보내기 템플릿 → tools/editor_data/export_templates/4.4.1.stable
#   디버그 서명 키 → tools/android/debug.keystore
# tools/_sc_ 파일이 있으면 Godot 가 설정·템플릿을 tools/editor_data 에 둔다(포터블 모드).
# 이미 있는 것은 건너뛴다. 마지막에 Godot 편집기 설정에 SDK·JDK·키 경로를 적는다.
# 실행: powershell -ExecutionPolicy Bypass -File tools\scripts\setup_android.ps1
# Android SDK 라이선스는 이 스크립트가 대신 수락한다(sdkmanager --licenses).

$ErrorActionPreference = "Stop"
$tools = Split-Path -Parent $PSScriptRoot
$dl = Join-Path $tools "dl"
New-Item -ItemType Directory -Force $dl | Out-Null

# 폴더 옮기기 —— 백신이 막 푼 파일을 잠그면 Move-Item 이 거부된다. 잠시 기다려 다시, 안 되면 복사
function Move-Dir($from, $to) {
    for ($i = 0; $i -lt 5; $i++) {
        try { Move-Item $from $to -ErrorAction Stop; return } catch { Start-Sleep -Seconds 3 }
    }
    robocopy $from $to /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "복사 실패: $from -> $to" }
    Remove-Item $from -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

function Get-File($url, $out) {
    if (-not (Test-Path $out)) {
        Write-Host "받는 중: $url"
        Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    }
}

# JDK 17
$jdk = Join-Path $tools "jdk17"
if (-not (Test-Path (Join-Path $jdk "bin\java.exe"))) {
    $zip = Join-Path $dl "jdk17.zip"
    Get-File "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse" $zip
    $tmp = Join-Path $dl "jdk_tmp"
    Expand-Archive $zip $tmp -Force
    Move-Dir (Get-ChildItem $tmp | Select-Object -First 1).FullName $jdk
    Remove-Item $tmp -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

# Android SDK
$sdk = Join-Path $tools "android\sdk"
$sdkm = Join-Path $sdk "cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkm)) {
    $zip = Join-Path $dl "cmdline-tools.zip"
    Get-File "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" $zip
    $ct = Join-Path $sdk "cmdline-tools"
    New-Item -ItemType Directory -Force $ct | Out-Null
    Expand-Archive $zip $ct -Force
    Move-Dir (Join-Path $ct "cmdline-tools") (Join-Path $ct "latest")
}
$env:JAVA_HOME = $jdk
if (-not (Test-Path (Join-Path $sdk "build-tools\34.0.0"))) {
    # 라이선스 수락 —— 파이프로 y 를 넣으면 PowerShell 5.1 에서 안 먹을 때가 있어 cmd 로 파일을 흘려 넣는다
    $yes = Join-Path $dl "yes.txt"
    [System.IO.File]::WriteAllText($yes, ("y`r`n" * 20))
    cmd /c "`"$sdkm`" --sdk_root=`"$sdk`" --licenses < `"$yes`"" | Out-Null
    & $sdkm "--sdk_root=$sdk" "platform-tools" "build-tools;34.0.0" "platforms;android-34"
}

# Godot 내보내기 템플릿 (약 1.2GB)
New-Item -ItemType File -Force (Join-Path $tools "_sc_") | Out-Null
$tpl = Join-Path $tools "editor_data\export_templates\4.4.1.stable"
if (-not (Test-Path (Join-Path $tpl "android_debug.apk"))) {
    $tpz = Join-Path $dl "godot_templates.tpz"
    Get-File "https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_export_templates.tpz" $tpz
    $tmp = Join-Path $tools "editor_data\export_templates\tmp"
    $tzip = Join-Path $dl "godot_templates.zip"      # .tpz 는 zip 이다 —— Expand-Archive 는 확장자가 .zip 이어야 받는다
    if (-not (Test-Path $tzip)) { Copy-Item $tpz $tzip }
    Expand-Archive $tzip $tmp -Force
    Move-Dir (Join-Path $tmp "templates") $tpl
    Remove-Item $tmp -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

# 디버그 서명 키
$ks = Join-Path $tools "android\debug.keystore"
if (-not (Test-Path $ks)) {
    & (Join-Path $jdk "bin\keytool.exe") -genkeypair -keystore $ks -storepass android -alias androiddebugkey `
        -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
}

# Godot 편집기 설정 —— 경로만 적는다 (기존 설정 파일이 있으면 경로 줄만 바꾼다)
$es = Join-Path $tools "editor_data\editor_settings-4.4.tres"
$want = [ordered]@{
    "export/android/java_sdk_path" = $jdk.Replace("\", "/")
    "export/android/android_sdk_path" = $sdk.Replace("\", "/")
    "export/android/debug_keystore" = $ks.Replace("\", "/")
    "export/android/debug_keystore_user" = "androiddebugkey"
    "export/android/debug_keystore_pass" = "android"
}
if (Test-Path $es) {
    $lines = Get-Content $es -Encoding UTF8 | Where-Object { $l = $_; -not ($want.Keys | Where-Object { $l.StartsWith("$_ =") }) }
} else {
    $lines = @('[gd_resource type="EditorSettings" format=3]', '', '[resource]')
}
foreach ($k in $want.Keys) { $lines += "$k = `"$($want[$k])`"" }
[System.IO.File]::WriteAllLines($es, $lines, (New-Object System.Text.UTF8Encoding $false))
Write-Host "준비 끝 —— solgukji_godot\build_apk.bat 로 APK 를 만든다."
