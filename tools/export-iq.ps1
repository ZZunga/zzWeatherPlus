<#  export-iq.ps1 - 스토어 업로드용 .iq 패키지 (전 기기 포함, 릴리스 빌드)
    결과: bin/zzWeatherPlus.iq                                                    #>
param(
    [string]$Sdk = "$env:APPDATA\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.4.1-2026-02-03-e9f77eeaa",
    [string]$Key = "$env:USERPROFILE\.Garmin\ConnectIQ\developer_key"
)
$ErrorActionPreference = "Stop"
$mc = Join-Path $Sdk "bin\monkeyc.bat"
New-Item -ItemType Directory -Force -Path bin | Out-Null
& $mc -e -r -w -f monkey.jungle -o bin/zzWeatherPlus.iq -y $Key
Write-Host "-> bin/zzWeatherPlus.iq" -ForegroundColor Green
