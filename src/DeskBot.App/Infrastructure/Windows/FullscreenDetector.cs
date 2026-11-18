using System;
using System.Text;
using static DeskBot.App.Infrastructure.Windows.NativeMethods;

namespace DeskBot.App.Infrastructure.Windows;

/// <summary>Game Mode — fullscreen тоглоом/видео/presentation илрүүлэх.</summary>
internal static class FullscreenDetector
{
    private const int QUNS_RUNNING_D3D_FULL_SCREEN = 3;
    private const int QUNS_PRESENTATION_MODE = 4;

    public static bool IsFullscreenOn(MonitorInfo monitor, IntPtr self)
    {
        try
        {
            if (SHQueryUserNotificationState(out var state) == 0 &&
                state is QUNS_RUNNING_D3D_FULL_SCREEN or QUNS_PRESENTATION_MODE)
                return true;
        }
        catch (EntryPointNotFoundException) { }

        var fg = GetForegroundWindow();
        if (fg == IntPtr.Zero || fg == self || fg == GetShellWindow() || fg == GetDesktopWindow())
            return false;

        var cls = new StringBuilder(64);
        GetClassName(fg, cls, cls.Capacity);
        var name = cls.ToString();
        if (name is "WorkerW" or "Progman" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd")
            return false;

        if (!GetWindowRect(fg, out var r)) return false;
        var fgMon = Monitors.FromWindow(fg);
        if (fgMon is null || fgMon.Handle != monitor.Handle) return false;

        var b = monitor.Bounds;
        return r.Left <= b.Left && r.Top <= b.Top && r.Right >= b.Right && r.Bottom >= b.Bottom;
    }
}
