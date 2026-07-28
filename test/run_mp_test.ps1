# Runs the two-instance multiplayer test and ALWAYS produces a GIF of the run.
#
#   powershell -File test\run_mp_test.ps1
#
# Starts a server instance and a client instance on test/multiPlayerTest.tscn,
# lets test/mp_test_driver.gd drive the scripted kitchen sequence, then writes:
#   logs\mptest_report.txt   - every check, pass/fail, plus failure details
#   logs\mptest_run.gif      - both peers side by side, one frame per step
#   logs\mptest_{server,client}.log - full step logs
# Exits non-zero if any check failed.
#
# The windows are visible because frame capture needs a real framebuffer: a
# headless Godot renders nothing, so there would be no GIF. Use -Headless when
# you only want the pass/fail result (faster, but no GIF).

param(
    [string]$Godot = "C:\Users\Aqua Aurora\Desktop\Godot_v4.7-stable_win64.exe",
    [int]$TimeoutSec = 400,
    # Seconds to pause between steps, and to hold the final state on screen.
    [double]$Pause = 0.4,
    [double]$Hold = 3,
    # Passed through to make_gif.ps1.
    [int]$HalfWidth = 900,
    [double]$SecondsPerStep = 1.2,
    # Skip the windows entirely. No frames are captured, so no GIF is produced.
    [switch]$Headless
)

$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent $PSScriptRoot
# The two peers deliberately load DIFFERENT scenes, mirroring the real game:
# the host opens whatever world it is running, the client opens the bare
# multiplayer scene and must receive the entire layout over the network. That is
# also exactly what a client joining mid-session goes through.
$serverScene = "res://test/multiPlayerTest.tscn"
$clientScene = "res://Scenes/multiPlayer.tscn"
$serverLog = Join-Path $proj "logs/mptest_server.log"
$clientLog = Join-Path $proj "logs/mptest_client.log"
$report    = Join-Path $proj "logs/mptest_report.txt"
$gif       = Join-Path $proj "logs/mptest_run.gif"

foreach ($f in @($serverLog, $clientLog, $report, $gif)) { if (Test-Path $f) { Remove-Item $f -Force } }

. (Join-Path $PSScriptRoot "mp_window_layout.ps1")

function Start-Instance($extraArgs, $sceneFor) {
    # --xr-mode off keeps it on the desktop (SteamVR's OpenXR runtime otherwise
    # takes over, and two instances can't share a headset anyway).
    $a = "--xr-mode off"
    if ($Headless) { $a = "--headless " + $a }
    $a += " --resolution 900x600 --path `"$proj`" $sceneFor -- $($extraArgs -join ' ') --mptest"
    if (-not $Headless) { $a += " --mptest-frames" }
    $a += " --mptest-pause $Pause --mptest-hold $Hold"
    $p = Start-Process -FilePath $Godot -ArgumentList $a -PassThru -NoNewWindow:$Headless
    # Touching .Handle caches it, which is what makes .ExitCode readable later.
    $null = $p.Handle
    return $p
}

Write-Host "Starting SERVER..."
$server = Start-Instance @("--server") $serverScene
if (-not $Headless) { $w = Move-GameWindow $server 20 60 }
Start-Sleep -Seconds 5
Write-Host "Starting CLIENT..."
$client = Start-Instance @("--join", "127.0.0.1") $clientScene
if (-not $Headless) { $null = Move-GameWindow $client (20 + $w + 12) 60 }

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline -and -not $server.HasExited) { Start-Sleep -Milliseconds 500 }

foreach ($p in @($server, $client)) {
    if (-not $p.HasExited) { Write-Host "Killing pid $($p.Id) (still running)"; $p.Kill() }
}
Start-Sleep -Milliseconds 500

if (-not $Headless) {
    Write-Host ""
    Write-Host "======================== GIF ========================"
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "make_gif.ps1") `
        -HalfWidth $HalfWidth -SecondsPerStep $SecondsPerStep
} else {
    Write-Host ""
    Write-Host "(headless run: no frames captured, so no GIF - drop -Headless to get one)"
}

Write-Host ""
Write-Host "======================== REPORT ========================"
if (Test-Path $report) { Get-Content $report -Encoding UTF8 } else { Write-Host "(no report written - the run did not finish)" }

$server.WaitForExit(2000) | Out-Null
$code = if ($server.HasExited) { $server.ExitCode } else { 1 }
Write-Host ""
Write-Host "report: $report"
if (-not $Headless -and (Test-Path $gif)) { Write-Host "gif:    $gif" }
Write-Host "logs:   $serverLog"
Write-Host "        $clientLog"
Write-Host "server exit code: $code"
exit $code
