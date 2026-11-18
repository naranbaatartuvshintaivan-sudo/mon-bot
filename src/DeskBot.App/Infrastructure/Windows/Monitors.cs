using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using static DeskBot.App.Infrastructure.Windows.NativeMethods;

namespace DeskBot.App.Infrastructure.Windows;

/// <summary>Нэг дэлгэцийн мэдээлэл — бүх координат physical pixel.</summary>
internal sealed record MonitorInfo(IntPtr Handle, string DeviceName, RECT Bounds, RECT WorkArea, bool IsPrimary, double Scale)
{
    public string DisplayLabel => $"{(IsPrimary ? "★ " : "")}{DeviceName.Replace(@"\\.\", "")} — {Bounds.Width}×{Bounds.Height} @ {Scale * 100:0}%";
}

internal static class Monitors
{
    public static List<MonitorInfo> All()
    {
        var list = new List<MonitorInfo>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr h, IntPtr _, ref RECT __, IntPtr ___) =>
        {
            var info = From(h);
            if (info is not null) list.Add(info);
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static MonitorInfo Resolve(string deviceName)
    {
        var all = All();
        return all.FirstOrDefault(m => !string.IsNullOrEmpty(deviceName) && m.DeviceName == deviceName)
            ?? all.FirstOrDefault(m => m.IsPrimary)
            ?? all.First();
    }

    public static MonitorInfo FromPoint(int x, int y) =>
        From(MonitorFromPoint(new POINT(x, y), MONITOR_DEFAULTTONEAREST)) ?? All().First();

    public static MonitorInfo? FromWindow(IntPtr hwnd) => From(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST));

    private static MonitorInfo? From(IntPtr h)
    {
        if (h == IntPtr.Zero) return null;
        var mi = new MONITORINFOEX { cbSize = Marshal.SizeOf<MONITORINFOEX>() };
        if (!GetMonitorInfo(h, ref mi)) return null;
        double scale = 1;
        try
        {
            if (GetDpiForMonitor(h, 0, out var dx, out _) == 0 && dx > 0) scale = dx / 96.0;
        }
        catch (DllNotFoundException) { /* Win7-оос доош — дэмжихгүй */ }
        return new MonitorInfo(h, mi.szDevice, mi.rcMonitor, mi.rcWork, (mi.dwFlags & MONITORINFOF_PRIMARY) != 0, scale);
    }
}
