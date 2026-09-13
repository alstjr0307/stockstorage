$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "StockStorage 실행기"

$SDK      = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$EMULATOR = Join-Path $SDK "emulator\emulator.exe"
$ADB      = Join-Path $SDK "platform-tools\adb.exe"
$AVD      = "Medium_Phone_API_36.1"
$PROJECT  = "C:\Users\alswp\stockstorage"

Set-Location $PROJECT

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  StockStorage 자동 실행" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

function Get-OnlineDevice {
    $lines = & $ADB devices
    foreach ($line in $lines) {
        if ($line -match '^(emulator-\d+|\S+)\s+device$') {
            return $matches[1]
        }
    }
    return $null
}

# --- 이미 정상 연결된 기기 확인 ---
$device = Get-OnlineDevice
if ($device) {
    Write-Host "[1/3] 이미 실행 중인 기기 발견: $device" -ForegroundColor Green
    Write-Host "[2/3] 대기 생략"
} else {
    Write-Host "[1/3] 에뮬레이터 부팅 중... ($AVD)" -ForegroundColor Yellow
    Start-Process -FilePath $EMULATOR -ArgumentList "-avd", $AVD

    Write-Host "[2/3] 부팅 완료 대기 중 (보통 40초~1분)..." -ForegroundColor Yellow
    & $ADB wait-for-device

    $booted = $false
    for ($i = 0; $i -lt 60; $i++) {
        $boot = (& $ADB shell getprop sys.boot_completed 2>$null | Out-String).Trim()
        if ($boot -eq "1") { $booted = $true; break }
        Start-Sleep -Seconds 3
        Write-Host "      ...대기 중 ($([int]($i*3))초)" -ForegroundColor DarkGray
    }

    if (-not $booted) {
        Write-Host "부팅 확인 실패. 에뮬레이터 창을 확인해 주세요." -ForegroundColor Red
        Read-Host "엔터를 누르면 종료"
        exit 1
    }
    Write-Host "      부팅 완료!" -ForegroundColor Green
}

Write-Host "[3/3] 앱 실행 중..." -ForegroundColor Green
& flutter run --dart-define-from-file=dart_defines.json

Write-Host ""
Read-Host "종료되었습니다. 엔터를 누르면 창이 닫힙니다"
