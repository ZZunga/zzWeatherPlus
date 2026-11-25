<#  build-all.ps1 - build zzWeatherPlus for every target device. #>
param(
    [string]$Sdk = "$env:APPDATA\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-8.4.1-2026-02-03-e9f77eeaa",
    [string]$Key = "$env:USERPROFILE\.Garmin\ConnectIQ\developer_key"
)
$ErrorActionPreference = "Stop"
$devices = "edge540","edge550","edge840","edge850","edge1040","edge1050","edge1060"
$mc = Join-Path $Sdk "bin\monkeyc.bat"
New-Item -ItemType Directory -Force -Path bin | Out-Null

foreach ($d in $devices) {
    Write-Host "=== $d ===" -ForegroundColor Cyan
    & $mc -f monkey.jungle -d $d -o "bin/zzWeatherPlus-$d.prg" -y $Key -w
}
Write-Host "done." -ForegroundColor Green
