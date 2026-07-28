# Opens two windows on the multiplayer test scene in MANUAL mode, so you can
# drive the plate / dirt-station flow yourself and watch both peers.
#
#   powershell -File test\play_mp_test.ps1
#
# No scripted sequence runs. Click a window to focus it, then:
#
#   1  grab the plate           2  drop it
#   3  carry it to the dirt zone  4  drop it at the dirt zone
#   5  check it snapped + went dirty
#   6  run the whole automatic sequence (server window only)
#   0  dump the current state of everything
#   C  toggle between the fixed debug camera and the XR rig camera
#
# Keys act on whichever window has focus, so you can grab on the CLIENT and
# watch the SERVER window follow. Each window opens on a fixed camera looking
# at the test area, overlays its own step log, and writes it to
# logs\mptest_server.log / logs\mptest_client.log.
#
# The typical repro: on the CLIENT press 1, 2 (grab and drop), then on the
# SERVER press 1, 2. Then on the CLIENT press 1, 3, 4 and press 5 on both.

param(
    [string]$Godot = "C:\Users\Aqua Aurora\Desktop\Godot_v4.7-stable_win64.exe",
    # Pass -Solo to open a single window with no networking, to compare the
    # same steps against single-player behaviour.
    [switch]$Solo
)

$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent $PSScriptRoot
$serverScene = "res://test/multiPlayerTest.tscn"
$clientScene = "res://Scenes/multiPlayer.tscn"

. (Join-Path $PSScriptRoot "mp_window_layout.ps1")

function Start-Instance($extraArgs, $sceneFor) {
    $a = "--xr-mode off --resolution 900x600 --path `"$proj`" $sceneFor -- --mptest-manual"
    if ($extraArgs) { $a += " $($extraArgs -join ' ')" }
    return Start-Process -FilePath $Godot -ArgumentList $a -PassThru
}

if ($Solo) {
    Write-Host "Opening a single offline window (no networking)."
    $null = Move-GameWindow (Start-Instance $null $serverScene) 300 100
    return
}

Write-Host "Opening SERVER window (left)..."
$w = Move-GameWindow (Start-Instance @("--server") $serverScene) 20 60
Start-Sleep -Seconds 5
Write-Host "Opening CLIENT window (right)..."
$null = Move-GameWindow (Start-Instance @("--join", "127.0.0.1") $clientScene) (20 + $w + 12) 60

Write-Host ""
Write-Host "Both windows are up. Click one to focus it, then press:"
Write-Host "  1 grab   2 drop   3 carry-to-dirt   4 drop-at-dirt   5 verify   0 dump"
Write-Host "  6 runs the whole automatic sequence (server window only)   C toggles the camera"
Write-Host ""
Write-Host "Step logs: $(Join-Path $proj 'logs\mptest_server.log')"
Write-Host "           $(Join-Path $proj 'logs\mptest_client.log')"
Write-Host "Close the windows when you're done (Esc quits)."
