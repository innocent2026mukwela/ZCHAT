# Rebuild & install ZCHAT on a connected phone with DEMO_AUTH (local OTP, no Node).
# Usage (from repo root):  powershell -File tools\run_demo_phone.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "Devices:" -ForegroundColor Cyan
flutter devices
Write-Host ""
Write-Host "Running with DEMO_AUTH=true (local OTP, offline login)..." -ForegroundColor Cyan
flutter run --dart-define-from-file=dart_defines.demo.json @args
