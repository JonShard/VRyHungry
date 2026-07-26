# Runs the two-instance multiplayer test in two VISIBLE windows, side by side,
# pausing between steps so you can watch what happens on each peer.
#
#   powershell -File test\run_mp_test_windowed.ps1
#
# Same test as run_mp_test.ps1 (headless); this one is for watching it. Each
# window shows an on-screen overlay of the step log for that peer.
#
# To drive it yourself instead, see test\play_mp_test.ps1 (manual mode).

param(
    [string]$Godot = "C:\Users\Aqua Aurora\Desktop\Godot_v4.7-stable_win64.exe",
    # Seconds to pause between steps, and to hold the final state on screen.
    [double]$Pause = 1.5,
    [double]$Hold = 20,
    [int]$TimeoutSec = 300,
    # Passed through to make_gif.ps1. HalfWidth 900 keeps the on-screen
    # step log readable in the GIF; lower it to shrink the file.
    [int]$HalfWidth = 900,
    [double]$SecondsPerStep = 1.2,
    # Skip building the GIF (frames are still captured).
    [switch]$NoGif
)

$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent $PSScriptRoot
$scene = "res://test/multiPlayerTest.tscn"
$serverLog = Join-Path $proj "logs/mptest_server.log"
$clientLog = Join-Path $proj "logs/mptest_client.log"

foreach ($f in @($serverLog, $clientLog)) { if (Test-Path $f) { Remove-Item $f -Force } }

. (Join-Path $PSScriptRoot "mp_window_layout.ps1")

function Start-Instance($extraArgs) {
    # --xr-mode off keeps it on the desktop (SteamVR's OpenXR runtime otherwise
    # takes over, and two instances can't share a headset anyway).
    $a = "--xr-mode off --resolution 900x600 --path `"$proj`" $scene -- " +
         "$($extraArgs -join ' ') --mptest --mptest-frames --mptest-pause $Pause --mptest-hold $Hold"
    $p = Start-Process -FilePath $Godot -ArgumentList $a -PassThru
    # Touching .Handle caches it, which is what makes .ExitCode readable later.
    $null = $p.Handle
    return $p
}

Write-Host "Starting SERVER window (left)..."
$server = Start-Instance @("--server")
$w = Move-GameWindow $server 20 60
Start-Sleep -Seconds 5
Write-Host "Starting CLIENT window (right)..."
$client = Start-Instance @("--join", "127.0.0.1")
$null = Move-GameWindow $client (20 + $w + 12) 60

Write-Host "Watch the two windows (each has a fixed camera on the test area)."
Write-Host "Step logs: $serverLog"
Write-Host "           $clientLog"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline -and -not $server.HasExited) { Start-Sleep -Milliseconds 500 }

foreach ($p in @($server, $client)) {
    if (-not $p.HasExited) { Write-Host "Killing pid $($p.Id) (still running)"; $p.Kill() }
}
Start-Sleep -Milliseconds 500

foreach ($pair in @(@("SERVER", $serverLog), @("CLIENT", $clientLog))) {
    Write-Host ""
    Write-Host "======================== $($pair[0]) ========================"
    if (Test-Path $pair[1]) { Get-Content $pair[1] -Encoding UTF8 } else { Write-Host "(no log written)" }
}

if (-not $NoGif) {
    Write-Host ""
    Write-Host "======================== GIF ========================"
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "make_gif.ps1") `
        -HalfWidth $HalfWidth -SecondsPerStep $SecondsPerStep
}

$server.WaitForExit(2000) | Out-Null
$code = if ($server.HasExited) { $server.ExitCode } else { 1 }
Write-Host ""
Write-Host "server exit code: $code"
exit $code
