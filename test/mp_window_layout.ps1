# Shared helper for placing the two game windows side by side.
#
# Godot's --position flag is ignored on this setup (the window lands at x=-7
# whatever you pass), so the windows are moved with the Win32 API after they
# come up. Dot-source this file to get Move-GameWindow.

if (-not ('MpWin' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MpWin {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
}

# Godot's windows are DPI aware; PowerShell's process is not by default, so
# GetWindowRect/SetWindowPos would otherwise be talking in virtualised
# coordinates and the windows land nowhere near where we asked.
[void][MpWin]::SetProcessDPIAware()

# Moves a just-launched game window to (x, y) and returns its width, so the
# caller can place the next window immediately to its right. Never resizes:
# changing the window size independently of Godot's --resolution distorts the
# rendered aspect ratio.
function Move-GameWindow($proc, [int]$x, [int]$y) {
    for ($i = 0; $i -lt 60 -and $proc.MainWindowHandle -eq 0; $i++) {
        Start-Sleep -Milliseconds 250
        $proc.Refresh()
    }
    if ($proc.MainWindowHandle -eq 0) {
        Write-Host "  (window never appeared; leaving it where it is)"
        return 620
    }
    # The handle shows up before Godot has finished sizing/positioning the
    # window - moving it too early gets overwritten by Godot's own setup.
    Start-Sleep -Milliseconds 2500
    $h = $proc.MainWindowHandle
    # SWP_NOSIZE (0x1) | SWP_NOZORDER (0x4)
    [void][MpWin]::SetWindowPos($h, [IntPtr]::Zero, $x, $y, 0, 0, 0x0005)
    $r = New-Object MpWin+RECT
    [void][MpWin]::GetWindowRect($h, [ref]$r)
    return [int]($r.Right - $r.Left)
}
