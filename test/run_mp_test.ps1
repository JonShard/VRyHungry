# Runs the headless two-instance multiplayer test (test/multiPlayerTest.tscn).
#
#   powershell -File test\run_mp_test.ps1
#
# Starts a server instance and a client instance of the game with --xr-mode off
# (SteamVR's OpenXR runtime crashes a headless process), lets test/mp_test_driver.gd
# drive the scripted plate/dirt-station sequence, then prints both logs.
# Exits non-zero if any check failed.

param(
    [string]$Godot = "C:\Users\Aqua Aurora\Desktop\Godot_v4.7-stable_win64.exe",
    [int]$TimeoutSec = 120
)

$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent $PSScriptRoot
$scene = "res://test/multiPlayerTest.tscn"
$serverLog = Join-Path $proj "logs/mptest_server.log"
$clientLog = Join-Path $proj "logs/mptest_client.log"

foreach ($f in @($serverLog, $clientLog)) { if (Test-Path $f) { Remove-Item $f -Force } }

function Start-Instance($extraArgs) {
    # Single argument string with the project path quoted: Start-Process does
    # not quote array elements, so the space in the path would split it.
    $a = "--headless --xr-mode off --path `"$proj`" $scene -- $($extraArgs -join ' ')"
    $p = Start-Process -FilePath $Godot -ArgumentList $a -PassThru -NoNewWindow
    # Touching .Handle caches it, which is what makes .ExitCode readable later;
    # without this it comes back empty even after the process has exited.
    $null = $p.Handle
    return $p
}

Write-Host "Starting server..."
$server = Start-Instance @("--server", "--mptest")
Start-Sleep -Seconds 4
Write-Host "Starting client..."
$client = Start-Instance @("--join", "127.0.0.1", "--mptest")

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

# ExitCode is only populated on the process object after a WaitForExit() call,
# even when HasExited is already true - without this it reads back empty.
$server.WaitForExit(2000) | Out-Null
$code = if ($server.HasExited) { $server.ExitCode } else { 1 }
Write-Host ""
Write-Host "server exit code: $code"
exit $code
