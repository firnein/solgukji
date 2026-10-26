# 솔국지 — 스토어 배포용(릴리스) 서명 키를 한 번 만든다.
#
#   powershell -ExecutionPolicy Bypass -File tools\scripts\make_release_key.ps1
#
# 키 파일은 저장소 밖(%USERPROFILE%\.solgukji\release.keystore)에 둔다 — 깃에 올리면 안 된다.
# 비밀번호는 실행할 때 묻고, 어디에도 적지 않는다. 키와 비밀번호를 잃어버리면 같은 앱으로 업데이트를
# 올릴 수 없으니 키 파일을 따로 백업하고 비밀번호는 비밀번호 관리자에 둔다.
# (구글 플레이는 'Play 앱 서명'을 켜면 이 키는 업로드 키가 되고, 잃어버려도 재설정을 요청할 수 있다.)
#
# 만든 뒤 릴리스 빌드: build_release.bat (환경 변수로 키 위치·비밀번호를 넘긴다)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$keytool = Join-Path $root "tools\jdk17\bin\keytool.exe"
if (-not (Test-Path $keytool)) {
    Write-Host "JDK 가 없습니다. 먼저 tools\scripts\setup_android.ps1 을 실행하세요."
    exit 1
}
$dir = Join-Path $env:USERPROFILE ".solgukji"
$ks = Join-Path $dir "release.keystore"
if (Test-Path $ks) {
    Write-Host "이미 있습니다: $ks  (새로 만들면 기존 앱을 업데이트할 수 없게 됩니다 — 지우지 마세요)"
    exit 0
}
New-Item -ItemType Directory -Force $dir | Out-Null
$alias = "solgukji"
$sec = Read-Host "키 비밀번호 (6자 이상)" -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
& $keytool -genkeypair -v -keystore $ks -storepass $pw -keypass $pw -alias $alias `
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Solgukji, O=Solgukji, C=KR"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host ""
Write-Host "만들었습니다: $ks (별칭 $alias)"
Write-Host "이 파일을 USB·클라우드 등 다른 곳에 백업해 두세요."
