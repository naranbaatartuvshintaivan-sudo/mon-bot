using System;
using System.Runtime.InteropServices;
using System.Threading;
using static DeskBot.App.Infrastructure.Windows.NativeMethods;

namespace DeskBot.App.Infrastructure.Windows;

/// <summary>
/// WH_MOUSE_LL hook-ийг ТУСДАА thread дээр (өөрийн message loop-тэй) ажиллуулна.
/// Ингэснээр UI thread завгүй байсан ч Windows-ийн mouse хэзээ ч гацахгүй.
/// Зөвхөн товчны down event уншина, mouse-ийг хэзээ ч блоклохгүй (CallNextHookEx үргэлж).
/// </summary>
internal sealed class GlobalMouseHook : IDisposable
{
    private Thread? _thread;
    private uint _threadId;
    private IntPtr _hook;
    private LowLevelMouseProc? _proc; // GC-д цуглуулагдахаас сэргийлж field-д барина

    /// <summary>Hook thread дээрээс дуудагдана — consumer нь Dispatcher.BeginInvoke хийх ёстой.</summary>
    public event Action<int, int>? MouseDown;

    public void Start()
    {
        if (_thread is not null) return;
        var ready = new ManualResetEventSlim(); // thread дуусах хүртэл амьд байх ёстой (dispose хийхгүй)
        _thread = new Thread(() => Run(ready)) { IsBackground = true, Name = "DeskBot.MouseHook" };
        _thread.Start();
        ready.Wait(TimeSpan.FromSeconds(2));
    }

    private void Run(ManualResetEventSlim ready)
    {
        _threadId = GetCurrentThreadId();
        _proc = HookProc;
        _hook = SetWindowsHookEx(WH_MOUSE_LL, _proc, GetModuleHandle(null), 0);
        ready.Set();
        if (_hook == IntPtr.Zero)
        {
            CrashLog.Write("Mouse hook суулгаж чадсангүй: " + Marshal.GetLastWin32Error());
            return;
        }
        while (GetMessage(out _, IntPtr.Zero, 0, 0) > 0) { }
        UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
    }

    private IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var msg = wParam.ToInt32();
            if (msg is WM_LBUTTONDOWN or WM_RBUTTONDOWN)
            {
                var info = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
                try { MouseDown?.Invoke(info.pt.X, info.pt.Y); } catch { /* hook-д exception гаргахгүй */ }
            }
        }
        return CallNextHookEx(IntPtr.Zero, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (_thread is null) return;
        if (_threadId != 0) PostThreadMessage(_threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        _thread.Join(1000);
        _thread = null;
    }
}
