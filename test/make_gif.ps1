# Stitches the per-step screenshots from a test run into one side-by-side GIF,
# server on the left, client on the right.
#
#   powershell -File test\make_gif.ps1
#
# Reads logs\mptest_frames_server\ and logs\mptest_frames_client\ (written when
# the driver runs with --mptest-frames) and writes logs\mptest_run.gif.
# run_mp_test_windowed.ps1 calls this automatically; run it by hand to rebuild
# the GIF after a manual session, or to re-render at a different speed.
#
# Each frame already carries its own caption: the on-screen overlay in the
# capture starts with [SERVER] or [CLIENT] and shows that step's log lines.

param(
    [string]$FFmpeg = "ffmpeg",
    # Seconds each step is held on screen.
    [double]$SecondsPerStep = 1.2,
    # Width of each peer's half of the frame, in pixels.
    [int]$HalfWidth = 900,
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"
$proj = Split-Path -Parent $PSScriptRoot
$serverDir = Join-Path $proj "logs/mptest_frames_server"
$clientDir = Join-Path $proj "logs/mptest_frames_client"
if (-not $Out) { $Out = Join-Path $proj "logs/mptest_run.gif" }

if (-not (Get-Command $FFmpeg -EA SilentlyContinue)) {
    Write-Host "ffmpeg not found. Install it, or pass -FFmpeg <path to ffmpeg.exe>."
    exit 1
}

function Frame-Count($dir) {
    if (-not (Test-Path $dir)) { return 0 }
    return (Get-ChildItem (Join-Path $dir "frame_*.png") -EA SilentlyContinue).Count
}

$ns = Frame-Count $serverDir
$nc = Frame-Count $clientDir
Write-Host "server frames: $ns"
Write-Host "client frames: $nc"

if ($ns -eq 0 -and $nc -eq 0) {
    Write-Host ""
    Write-Host "No frames found. Run the test with frame capture first:"
    Write-Host "  powershell -File test\run_mp_test_windowed.ps1"
    Write-Host "(frame capture needs a real window - a headless run renders nothing to grab)"
    exit 1
}

$fps = [Math]::Round(1.0 / $SecondsPerStep, 4)

if ($ns -gt 0 -and $nc -gt 0) {
    if ($ns -ne $nc) {
        # hstack stops at the shorter input, so the tail of the longer one is lost.
        Write-Host "note: frame counts differ, the GIF will stop after $([Math]::Min($ns,$nc)) steps"
    }
    # Two passes in one command: build a palette from the stacked frames, then
    # apply it. A single global palette keeps the GIF small and stops colours
    # shifting from frame to frame.
    $filter = "[0:v]scale=${HalfWidth}:-1:flags=lanczos[l];" +
              "[1:v]scale=${HalfWidth}:-1:flags=lanczos[r];" +
              "[l][r]hstack=inputs=2[v];" +
              "[v]split[a][b];[a]palettegen=max_colors=192[p];[b][p]paletteuse=dither=bayer:bayer_scale=3"
    $args = @(
        "-y", "-hide_banner", "-loglevel", "error",
        "-framerate", $fps, "-i", (Join-Path $serverDir "frame_%04d.png"),
        "-framerate", $fps, "-i", (Join-Path $clientDir "frame_%04d.png"),
        "-filter_complex", $filter, "-loop", "0", $Out
    )
} else {
    # Only one peer produced frames (e.g. a solo manual session).
    $dir = if ($ns -gt 0) { $serverDir } else { $clientDir }
    $filter = "[0:v]scale=${HalfWidth}:-1:flags=lanczos[v];" +
              "[v]split[a][b];[a]palettegen=max_colors=192[p];[b][p]paletteuse=dither=bayer:bayer_scale=3"
    $args = @(
        "-y", "-hide_banner", "-loglevel", "error",
        "-framerate", $fps, "-i", (Join-Path $dir "frame_%04d.png"),
        "-filter_complex", $filter, "-loop", "0", $Out
    )
}

& $FFmpeg @args
if ($LASTEXITCODE -ne 0) { Write-Host "ffmpeg failed ($LASTEXITCODE)"; exit $LASTEXITCODE }

$size = [Math]::Round((Get-Item $Out).Length / 1MB, 2)
Write-Host ""
Write-Host "wrote $Out  (${size} MB)"
