using System;
using System.Windows.Input;
using System.Windows.Interop;
using static DeskBot.App.Infrastructure.Windows.NativeMethods;

namespace DeskBot.App.Infrastructure.Windows;

/// <summary>RegisterHotKey-аар global shortcut. Keyboard input уншихгүй — зөвхөн тухайн хослолыг Windows мэдэгдэнэ.</summary>
internal sealed class GlobalHotkey : IDisposable
{
    private const int Id = 0xB07;
    private HwndSource? _source;
    private bool _registered;

    public event Action? Pressed;

    public string? LastError { get; private set; }

    public bool Register(IntPtr hwnd, string gesture)
    {
        Unregister();
        if (!TryParse(gesture, out var mods, out var vk))
        {
            LastError = $"'{gesture}' shortcut-ийг уншиж чадсангүй. Жишээ: Ctrl+Alt+Space";
            return false;
        }
        _source ??= HwndSource.FromHwnd(hwnd);
        _source.AddHook(WndProc);
        _registered = RegisterHotKey(hwnd, Id, mods | MOD_NOREPEAT, vk);
        LastError = _registered ? null : $"'{gesture}' өөр програм ашиглаж байна.";
        return _registered;
    }

    public static bool TryParse(string gesture, out uint mods, out uint vk)
    {
        mods = 0; vk = 0;
        Key key = Key.None;
        foreach (var raw in gesture.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            switch (raw.ToLowerInvariant())
            {
                case "ctrl": case "control": mods |= MOD_CONTROL; break;
                case "alt": mods |= MOD_ALT; break;
                case "shift": mods |= MOD_SHIFT; break;
                case "win": case "windows": mods |= MOD_WIN; break;
                default:
                    if (!Enum.TryParse(raw, true, out key)) return false;
                    break;
            }
        }
        if (key == Key.None || mods == 0) return false;
        vk = (uint)KeyInterop.VirtualKeyFromKey(key);
        return vk != 0;
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == Id)
        {
            Pressed?.Invoke();
            handled = true;
        }
        return IntPtr.Zero;
    }

    private void Unregister()
    {
        if (_source is null) return;
        if (_registered) UnregisterHotKey(_source.Handle, Id);
        _source.RemoveHook(WndProc);
        _registered = false;
    }

    public void Dispose()
    {
        Unregister();
        _source = null;
    }
}
