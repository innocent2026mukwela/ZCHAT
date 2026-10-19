# fix_backend_cors.ps1
# Simple CORS fix for unza-z-chat-backend server.js (ASCII only).
#
# Finds server.js at sibling ..\unza-z-chat-backend\server.js
# or uses -BackendRoot. Backs up to server.js.bak, then replaces
# throwing CORS denies with localhost-allowing callback(null, true).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\fix_backend_cors.ps1
#   powershell -ExecutionPolicy Bypass -File .\tools\fix_backend_cors.ps1 -BackendRoot "D:\path\unza-z-chat-backend"

[CmdletBinding()]
param(
  [string]$BackendRoot = ""
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$msg) { Write-Host "[CORS] $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "[CORS] $msg" -ForegroundColor Green }
function Write-Warn2([string]$msg){ Write-Host "[CORS] $msg" -ForegroundColor Yellow }
function Write-Err2([string]$msg) { Write-Host "[CORS] $msg" -ForegroundColor Red }

# Default: sibling of this repo (ZCHAT-main\..\unza-z-chat-backend)
if (-not $BackendRoot) {
  $repoRoot = Split-Path -Parent $PSScriptRoot
  $BackendRoot = Join-Path (Split-Path -Parent $repoRoot) "unza-z-chat-backend"
}

$serverJs = Join-Path $BackendRoot "server.js"
Write-Info "BackendRoot = $BackendRoot"
Write-Info "server.js   = $serverJs"

if (-not (Test-Path $BackendRoot)) {
  Write-Err2 "Backend folder not found: $BackendRoot"
  Write-Warn2 "Pass -BackendRoot if your clone lives elsewhere."
  Write-Warn2 "Or paste the 8 lines from tools\fix_backend_cors_SIMPLE.md into server.js."
  exit 1
}

if (-not (Test-Path $serverJs)) {
  Write-Err2 "server.js not found in $BackendRoot"
  exit 1
}

# Backup
$backup = Join-Path $BackendRoot "server.js.bak"
Copy-Item $serverJs $backup -Force
Write-Ok "Backup: $backup"

$text = Get-Content -Path $serverJs -Raw -Encoding UTF8
$changed = $false

# Simple string replaces (no complex regex). Allow instead of throw.
# Throwing Error becomes HTTP 500 and Chrome shows "No Access-Control-Allow-Origin".
$pairs = @(
  @{ Old = "callback(new Error('Not allowed by CORS'))"; New = "callback(null, true)" },
  @{ Old = 'callback(new Error("Not allowed by CORS"))'; New = "callback(null, true)" },
  @{ Old = "throw new Error('Not allowed by CORS')"; New = "return callback(null, true)" },
  @{ Old = 'throw new Error("Not allowed by CORS")'; New = "return callback(null, true)" }
)

foreach ($p in $pairs) {
  if ($text.Contains($p.Old)) {
    $text = $text.Replace($p.Old, $p.New)
    $changed = $true
    Write-Info "Replaced: $($p.Old)"
  }
}

if ($changed) {
  Set-Content -Path $serverJs -Value $text -Encoding UTF8 -NoNewline
  Write-Ok "Patched $serverJs"
} else {
  Write-Warn2 "No throwing CORS string found. File may already be fixed."
  Write-Warn2 "If Chrome still fails, paste the block in tools\fix_backend_cors_SIMPLE.md"
}

Write-Host ""
Write-Ok "NEXT:"
Write-Host "  1) cd `"$BackendRoot`""
Write-Host "  2) npm start"
Write-Host "  3) Flutter Chrome with BACKEND_URL=http://localhost:5000"
Write-Host ""
exit 0
