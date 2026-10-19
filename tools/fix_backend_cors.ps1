<#
.SYNOPSIS
  One-click CORS fix for Innocent's unza-z-chat-backend server.js

.DESCRIPTION
  Cursor on Ruth's PC cannot edit C:\Users\TINOTECH\... — that path is on
  Innocent's Windows user profile only. Run THIS script on the PC that has
  the Node backend so Chrome (Flutter on any localhost port) can call :5000.

  What it does:
  - Backs up server.js → server.js.bak-cors-YYYYMMDD-HHmmss
  - Replaces origin callbacks that throw Error('Not allowed by CORS')
  - Ensures app.use(cors(...)) allows localhost / 127.0.0.1 on ANY port
  - Adds app.options('*', cors(...)) for Chrome preflight if missing
  - Optionally copies tools/backend_accept_demo_auth.js into middleware/

.EXAMPLE
  # From ZCHAT clone (default Innocent path):
  powershell -ExecutionPolicy Bypass -File .\tools\fix_backend_cors.ps1

.EXAMPLE
  # Custom backend folder:
  powershell -ExecutionPolicy Bypass -File .\tools\fix_backend_cors.ps1 -BackendRoot "D:\FINAL YEAR PROJECT\unza-z-chat-backend"
#>

[CmdletBinding()]
param(
  [string]$BackendRoot = "C:\Users\TINOTECH\Desktop\FINAL YEAR PROJECT\unza-z-chat-backend",
  [string]$FlutterRoot = "",
  [switch]$SkipMiddlewareCopy
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$msg) { Write-Host "[CORS] $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "[CORS] $msg" -ForegroundColor Green }
function Write-Warn2([string]$msg){ Write-Host "[CORS] $msg" -ForegroundColor Yellow }
function Write-Err2([string]$msg) { Write-Host "[CORS] $msg" -ForegroundColor Red }

# Resolve Flutter/ZCHAT root (where this script lives → tools/ → repo root)
if (-not $FlutterRoot) {
  $FlutterRoot = Split-Path -Parent $PSScriptRoot
  if (-not (Test-Path (Join-Path $FlutterRoot "tools\backend_accept_demo_auth.js"))) {
    $FlutterRoot = "C:\Users\user\Desktop\ZCHAT-main"
  }
}

$serverJs = Join-Path $BackendRoot "server.js"
Write-Info "BackendRoot = $BackendRoot"
Write-Info "server.js   = $serverJs"
Write-Info "FlutterRoot = $FlutterRoot"

if (-not (Test-Path $BackendRoot)) {
  Write-Err2 "Backend folder not found: $BackendRoot"
  Write-Warn2 "This script must run on the PC that owns unza-z-chat-backend (usually Innocent / TINOTECH)."
  Write-Warn2 "Ruth's Cursor cannot edit that path — it is a different Windows user home."
  Write-Warn2 "Pass -BackendRoot if your clone lives elsewhere."
  exit 1
}

if (-not (Test-Path $serverJs)) {
  Write-Err2 "server.js not found in $BackendRoot"
  Write-Warn2 "Look for the file, then re-run with -BackendRoot pointing at that folder."
  exit 1
}

# --- Backup ---
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $BackendRoot "server.js.bak-cors-$stamp"
Copy-Item $serverJs $backup -Force
Write-Ok "Backup: $backup"

$text = Get-Content -Path $serverJs -Raw -Encoding UTF8

# Canonical CORS options (never throw — throw → HTTP 500 → Chrome "No ACAO")
$corsBlock = @'
const zchatCorsOptions = {
  origin: function (origin, callback) {
    if (
      !origin ||
      origin === "null" ||
      (typeof origin === "string" && origin.startsWith("file://")) ||
      /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)
    ) {
      return callback(null, true);
    }
    return callback(null, false); // quiet deny — never throw
  },
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: ["Authorization", "Content-Type", "X-ZChat-Demo-Auth"],
};
'@

$corsUse = @'
app.use(cors(zchatCorsOptions));
app.options("*", cors(zchatCorsOptions)); // Chrome preflight
'@

$changed = $false

# 1) Soften any throwing origin callback: callback(new Error(...)) / throw new Error('Not allowed by CORS')
if ($text -match "Not allowed by CORS|callback\(\s*new\s+Error") {
  Write-Info "Found throwing CORS deny — rewriting origin callbacks to quiet deny / localhost allow..."
  # Replace common throw patterns inside origin handlers with quiet deny
  $text = [regex]::Replace(
    $text,
    "callback\(\s*new\s+Error\([^)]*\)\s*\)",
    "callback(null, false)"
  )
  $text = [regex]::Replace(
    $text,
    "throw\s+new\s+Error\(\s*['\`"]Not allowed by CORS['\`"]\s*\)\s*;?",
    "return callback(null, false);"
  )
  $changed = $true
}

# 2) Inject zchatCorsOptions if missing
if ($text -notmatch "zchatCorsOptions") {
  Write-Info "Injecting zchatCorsOptions + app.use(cors(zchatCorsOptions))..."

  # Prefer after first require('cors') line
  if ($text -match "(?m)^(.*require\(['\`"]cors['\`"].*)$") {
    $text = [regex]::Replace(
      $text,
      "(?m)^(.*require\(['\`"]cors['\`"].*)$",
      "`$1`r`n`r`n$corsBlock",
      1
    )
  } else {
    # Fallback: after first `const app = express()`
    if ($text -match "(?m)^(.*(express\(\)|createServer).*)") {
      $text = [regex]::Replace(
        $text,
        "(?m)^(.*(express\(\)).*)$",
        "`$1`r`n`r`n$corsBlock",
        1
      )
    } else {
      $text = $corsBlock + "`r`n`r`n" + $text
    }
  }

  # Replace first app.use(cors(...)) with our block; else insert after options
  if ($text -match "app\.use\(\s*cors\s*\(") {
    $text = [regex]::Replace(
      $text,
      "app\.use\(\s*cors\s*\([^;]*\)\s*\)\s*;?",
      $corsUse.Trim(),
      1
    )
  } else {
    # Insert after zchatCorsOptions closing };
    $text = [regex]::Replace(
      $text,
      "(zchatCorsOptions\s*=\s*\{[\s\S]*?\};\s*)",
      "`$1`r`n$corsUse`r`n",
      1
    )
  }

  # Ensure options preflight exists somewhere
  if ($text -notmatch "app\.options\s*\(") {
    $text = [regex]::Replace(
      $text,
      "(app\.use\(\s*cors\(zchatCorsOptions\)\s*\)\s*;)",
      "`$1`r`napp.options(`"*`", cors(zchatCorsOptions));",
      1
    )
  }

  $changed = $true
} else {
  Write-Info "zchatCorsOptions already present — ensuring localhost regex allows any port..."
  # Make sure origin allows any localhost port
  if ($text -notmatch '\\\(localhost\|127\\\.0\\\.0\\\.1\\\)\(:\\\d\+\)\?') {
    # If a restrictive origin list exists, leave zchatCorsOptions alone if already good
    Write-Warn2 "Could not verify localhost regex; open server.js and confirm origin allows localhost any port."
  }
}

# 3) Optional: copy demo auth helper
$helperSrc = Join-Path $FlutterRoot "tools\backend_accept_demo_auth.js"
$mwDir = Join-Path $BackendRoot "middleware"
$helperDst = Join-Path $mwDir "backend_accept_demo_auth.js"

if (-not $SkipMiddlewareCopy) {
  if (Test-Path $helperSrc) {
    New-Item -ItemType Directory -Force -Path $mwDir | Out-Null
    Copy-Item $helperSrc $helperDst -Force
    Write-Ok "Copied middleware → $helperDst"
    if ($text -notmatch "backend_accept_demo_auth") {
      Write-Warn2 "Wire it in server.js (once):"
      Write-Host @"
  const { corsOptions, demoAuthMiddleware } = require('./middleware/backend_accept_demo_auth');
  // OR use the injected zchatCorsOptions above.
  app.use('/api/ai', demoAuthMiddleware(admin));
"@
    }
  } else {
    Write-Warn2 "Helper not found at $helperSrc — skip middleware copy."
  }
}

if ($changed) {
  Set-Content -Path $serverJs -Value $text -Encoding UTF8 -NoNewline
  Write-Ok "Patched $serverJs"
} else {
  Write-Warn2 "No textual change applied (file may already be fixed). Backup kept."
}

Write-Host ""
Write-Ok "NEXT:"
Write-Host "  1) cd `"$BackendRoot`""
Write-Host "  2) npm start   # must listen on port 5000"
Write-Host "  3) Flutter: flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:5000 --dart-define=DEMO_AUTH=true"
Write-Host ""
Write-Info "If CORS still fails, open DevTools → Network → failed OPTIONS and compare Origin header."
exit 0
