using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using DeskBot.App.Features.ControlCenter;
using DeskBot.App.Infrastructure;
using DeskBot.App.Infrastructure.Windows;
using DeskBot.App.Services;
using DeskBot.Core.Reminders;
using DeskBot.Core.Settings;
using static DeskBot.App.Infrastructure.Windows.NativeMethods;

namespace DeskBot.App.UI.Windows;

/// <summary>
/// Dynamic Island — дэлгэцийн дээд төвд байрлах transparent, borderless, topmost цонх.
/// Collapsed → (hover) → Hover → (click) → Expanded. Reminder ирэхэд Alert.
/// Island-ээс гадуурх тунгалаг хэсэг click-through (layered window alpha = 0).
/// </summary>
public partial class IslandWindow : Window
{
    private enum Mode { Collapsed, Hover, Alert, Expanded }

    private const double PadX = 28;     // glow + BackEase overshoot-д зай
    private const double PadBottom = 30;

    private readonly AppServices _svc;
    private AppSettings S => _svc.Settings;

    private readonly DispatcherTimer _cursorTimer = new(DispatcherPriority.Input) { Interval = TimeSpan.FromMilliseconds(33) };
    private readonly DispatcherTimer _hoverTimer = new();
    private readonly DispatcherTimer _collapseTimer = new();
    private readonly DispatcherTimer _clockTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly GlobalMouseHook _hook = new();
    private readonly GlobalHotkey _hotkey = new();
    private readonly Queue<Reminder> _alerts = new();

    private IntPtr _hwnd;
    private Mode _mode = Mode.Collapsed;
    private MonitorInfo? _monitor;
    private ControlCenterView? _center;
    private int _animVersion;
    private Reminder? _currentAlert;

    private bool _pressed, _dragging;
    private POINT _pressPoint;
    private POINT _lastCursor = new(int.MinValue, int.MinValue);
    private DateTime _lastNear = DateTime.Now, _lastGameCheck = DateTime.MinValue, _lastTopmost = DateTime.MinValue;
    private bool _hiddenUp, _fullscreenHidden, _userHidden;

    public event Action? ExitRequested;

    public IslandWindow(AppServices services)
    {
        _svc = services;
        InitializeComponent();
        Face.Bind(S);
        Face.Expression = _svc.Brain.Machine.Current;

        _svc.Brain.ExpressionChanged += e =>
        {
            Face.Expression = e;
            _center?.OnExpression(e);
        };
        _svc.Media.Changed += UpdateMini;
        _svc.Reminders.Fired += r => { _alerts.Enqueue(r); ShowNextAlert(); };
        _svc.Reminders.ListChanged += UpdateIndicators;
        S.PropertyChanged += OnSettingsChanged;

        _cursorTimer.Tick += (_, _) => OnCursorTick();
        _hoverTimer.Tick += (_, _) => { _hoverTimer.Stop(); if (_mode == Mode.Collapsed && IsCursorOverIsland()) SetMode(Mode.Hover); };
        _collapseTimer.Tick += (_, _) => OnCollapseTimer();
        _clockTimer.Tick += (_, _) => UpdateClock();

        Island.MouseEnter += (_, _) => OnIslandEnter();
        Island.MouseLeave += (_, _) => OnIslandLeave();
        Header.MouseLeftButtonDown += Header_MouseLeftButtonDown;
        Header.MouseMove += Header_MouseMove;
        Header.MouseLeftButtonUp += Header_MouseLeftButtonUp;
        Header.MouseRightButtonUp += (_, e) => { BuildContextMenu().IsOpen = true; e.Handled = true; };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape && _mode == Mode.Expanded) { SetMode(Mode.Collapsed); e.Handled = true; } };
        Deactivated += (_, _) => { if (_mode == Mode.Expanded && !S.Pinned) SetMode(Mode.Collapsed); };
        DpiChanged += (_, _) => Dispatcher.BeginInvoke(() => PlaceWindow(Island.ActualWidth, Island.ActualHeight), DispatcherPriority.Background);

        _hook.MouseDown += (x, y) => Dispatcher.BeginInvoke(() => OnGlobalMouseDown(x, y));
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        _hwnd = new WindowInteropHelper(this).Handle;
        // Alt+Tab-д харагдахгүй, focus хулгайлахгүй
        AddExStyle(_hwnd, WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);

        _monitor = Monitors.Resolve(S.MonitorDeviceName);
        ApplyAppearance();
        SetMode(Mode.Collapsed, instant: true);
        ApplyHotkey();
        if (S.ReactToGlobalClicks) _hook.Start();

        UpdateClock();
        UpdateMini();
        UpdateIndicators();
        _cursorTimer.Start();
        _clockTimer.Start();
    }

    protected override void OnClosed(EventArgs e)
    {
        _cursorTimer.Stop();
        _clockTimer.Stop();
        _hoverTimer.Stop();
        _collapseTimer.Stop();
        _hook.Dispose();
        _hotkey.Dispose();
        S.PropertyChanged -= OnSettingsChanged;
        base.OnClosed(e);
    }

    // ═════════════════════ Public API (tray / panels) ═════════════════════

    public void ToggleControlCenter()
    {
        if (_fullscreenHidden || _userHidden) { ShowIsland(); }
        SetMode(_mode == Mode.Expanded ? Mode.Collapsed : Mode.Expanded);
    }

    public void OpenTab(string tab)
    {
        ShowIsland();
        SetMode(Mode.Expanded);
        _center?.Select(tab);
    }

    public void ResetPosition()
    {
        S.OffsetX = 0;
        S.TopOffset = 0;
        S.MonitorDeviceName = "";
    }

    public bool IsHiddenByUser => _userHidden;

    public void SetHiddenByUser(bool hidden)
    {
        _userHidden = hidden;
        if (hidden) { Visibility = Visibility.Hidden; Face.Paused = true; }
        else ShowIsland();
    }

    /// <summary>Hotkey-г дахин бүртгэнэ. Алдаа байвал мессеж буцаана.</summary>
    public string? ApplyHotkey()
    {
        if (_hwnd == IntPtr.Zero) return null;
        return _hotkey.Register(_hwnd, S.Hotkey) ? null : _hotkey.LastError;
    }

    private void ShowIsland()
    {
        _userHidden = false;
        if (_fullscreenHidden) return;
        Visibility = Visibility.Visible;
        Face.Paused = false;
        PlaceWindow(Island.ActualWidth, Island.ActualHeight);
    }

    // ═════════════════════ Mode / animation ═════════════════════

    private (double W, double H) SizeFor(Mode m) => m switch
    {
        Mode.Collapsed => (S.IslandWidth, S.IslandHeight),
        Mode.Hover => (S.HoverWidth, S.IslandHeight + 8),
        Mode.Alert => (Math.Max(S.HoverWidth, 400), S.IslandHeight + 8 + 58),
        _ => (S.PanelWidth, S.PanelHeight),
    };

    private void SetMode(Mode m, bool instant = false)
    {
        var old = _mode;
        _mode = m;
        var (w, h) = SizeFor(m);
        var headerH = m == Mode.Collapsed ? S.IslandHeight : S.IslandHeight + 8;
        var faceW = m == Mode.Collapsed ? Math.Clamp(S.IslandWidth * 0.6, 80, 160) : 124;

        if (m == Mode.Expanded)
        {
            EnsureCenter();
            PanelHost.Visibility = Visibility.Visible;
            SetActivatable(true);
            _svc.System.SetFastMode(true);
            _center?.OnShown();
        }
        else if (old == Mode.Expanded)
        {
            SetActivatable(false);
            _svc.System.SetFastMode(false);
            _center?.OnHidden();
        }

        AlertBar.Visibility = m == Mode.Alert ? Visibility.Visible : Visibility.Collapsed;
        ExpandedActions.Visibility = m == Mode.Expanded ? Visibility.Visible : Visibility.Collapsed;
        RightInfo.IsHitTestVisible = m == Mode.Hover;
        UpdatePinGlyph();
        UpdateIndicators();
        ApplyCorner();

        // Цонхыг эхлээд томруулна (animation тайрагдахгүй), дууссаны дараа зорилтот хэмжээнд
        var curW = double.IsNaN(Island.Width) ? w : Island.ActualWidth;
        var curH = double.IsNaN(Island.Height) ? h : Island.ActualHeight;
        PlaceWindow(Math.Max(curW, w), Math.Max(curH, h));

        var version = ++_animVersion;
        var grow = w * h >= curW * curH;
        var fast = instant || S.ReducedMotion;

        Animate(Island, WidthProperty, w, grow, fast);
        Animate(Island, HeightProperty, h, grow, fast, () =>
        {
            if (version != _animVersion) return;
            PlaceWindow(w, h);
            if (_mode != Mode.Expanded) PanelHost.Visibility = Visibility.Collapsed;
        });
        Animate(Header, HeightProperty, headerH, grow, fast);
        Animate(Face, WidthProperty, faceW, grow, fast);
        Animate(LeftInfo, OpacityProperty, m == Mode.Collapsed ? 0 : 1, grow, fast);
        Animate(RightInfo, OpacityProperty, m == Mode.Hover || m == Mode.Alert ? 1 : 0, grow, fast);
        Animate(PanelHost, OpacityProperty, m == Mode.Expanded ? 1 : 0, grow, fast);
    }

    private static void Animate(UIElement el, DependencyProperty dp, double to, bool grow, bool instant, Action? done = null)
    {
        if (instant)
        {
            el.BeginAnimation(dp, null);
            el.SetValue(dp, to);
            done?.Invoke();
            return;
        }
        var anim = new DoubleAnimation(to, TimeSpan.FromMilliseconds(grow ? 360 : 240))
        {
            EasingFunction = grow
                ? new BackEase { Amplitude = 0.22, EasingMode = EasingMode.EaseOut }
                : new CubicEase { EasingMode = EasingMode.EaseOut },
        };
        if (done is not null) anim.Completed += (_, _) => done();
        el.BeginAnimation(dp, anim, HandoffBehavior.SnapshotAndReplace);
    }

    private void SetActivatable(bool on)
    {
        if (_hwnd == IntPtr.Zero) return;
        if (on)
        {
            RemoveExStyle(_hwnd, WS_EX_NOACTIVATE);
            Activate();
        }
        else
        {
            AddExStyle(_hwnd, WS_EX_NOACTIVATE);
        }
    }

    private void EnsureCenter()
    {
        if (_center is not null) return;
        _center = new ControlCenterView(_svc, this);
        PanelHost.Content = _center;
    }

    // ═════════════════════ Placement (multi-monitor + DPI) ═════════════════════

    private void PlaceWindow(double islandW, double islandH)
    {
        if (_hwnd == IntPtr.Zero || islandW <= 0 || islandH <= 0) return;
        _monitor = Monitors.Resolve(S.MonitorDeviceName);
        var mon = _monitor;
        var sc = mon.Scale;
        var pw = (int)Math.Ceiling((islandW + PadX * 2) * sc);
        var ph = (int)Math.Ceiling((islandH + PadBottom) * sc);
        var x = mon.Bounds.Left + (mon.Bounds.Width - pw) / 2 + (int)Math.Round(S.OffsetX * sc);
        x = Math.Clamp(x, mon.Bounds.Left - (int)(PadX * sc), mon.Bounds.Right - pw + (int)(PadX * sc));
        var y = mon.Bounds.Top + (int)Math.Round(S.TopOffset * sc);
        SetWindowPos(_hwnd, HWND_TOPMOST, x, y, pw, ph, SWP_NOACTIVATE);
    }

    private void ApplyAppearance()
    {
        var alpha = (byte)(255 * S.BackgroundOpacity);
        Island.Background = S.Background == IslandBackground.Translucent
            ? new SolidColorBrush(Color.FromArgb((byte)(alpha * 0.78), 0x12, 0x16, 0x1E))
            : new SolidColorBrush(Color.FromArgb(alpha, 0x05, 0x06, 0x08));
        ApplyCorner();
    }

    private void ApplyCorner()
    {
        var attached = S.TopOffset < 0.5;
        var r = S.CornerRadius + (_mode == Mode.Expanded ? 8 : 0);
        Island.CornerRadius = attached ? new CornerRadius(0, 0, r, r) : new CornerRadius(r);
        Island.BorderThickness = attached ? new Thickness(1, 0, 1, 1) : new Thickness(1);
    }

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(AppSettings.IslandWidth) or nameof(AppSettings.IslandHeight) or nameof(AppSettings.HoverWidth)
                or nameof(AppSettings.PanelWidth) or nameof(AppSettings.PanelHeight):
                SetMode(_mode, instant: true);
                break;
            case nameof(AppSettings.CornerRadius) or nameof(AppSettings.BackgroundOpacity) or nameof(AppSettings.Background):
                ApplyAppearance();
                break;
            case nameof(AppSettings.TopOffset) or nameof(AppSettings.OffsetX) or nameof(AppSettings.MonitorDeviceName):
                ApplyCorner();
                PlaceWindow(Island.ActualWidth, Island.ActualHeight);
                break;
            case nameof(AppSettings.ReactToGlobalClicks):
                if (S.ReactToGlobalClicks) _hook.Start(); else _hook.Dispose();
                break;
            case nameof(AppSettings.Pinned):
                UpdatePinGlyph();
                break;
            case nameof(AppSettings.AutoHide):
                if (!S.AutoHide) SlideUp(false);
                break;
            case nameof(AppSettings.GameModeAutoHide):
                if (!S.GameModeAutoHide && _fullscreenHidden) { _fullscreenHidden = false; if (!_userHidden) ShowIsland(); }
                break;
        }
    }

    // ═════════════════════ Hover / collapse ═════════════════════

    private void OnIslandEnter()
    {
        _collapseTimer.Stop();
        _lastNear = DateTime.Now;
        if (_hiddenUp) SlideUp(false);
        if (_mode != Mode.Collapsed) return;
        _hoverTimer.Interval = TimeSpan.FromMilliseconds(Math.Max(1, S.HoverDelayMs));
        _hoverTimer.Start();
    }

    private void OnIslandLeave()
    {
        _hoverTimer.Stop();
        if (_mode is Mode.Hover or Mode.Expanded)
        {
            var ms = _mode == Mode.Expanded ? Math.Max(S.AutoCollapseMs, 900) : S.AutoCollapseMs;
            _collapseTimer.Interval = TimeSpan.FromMilliseconds(Math.Max(1, ms));
            _collapseTimer.Stop();
            _collapseTimer.Start();
        }
    }

    private void OnCollapseTimer()
    {
        _collapseTimer.Stop();
        if (IsCursorOverIsland()) return;           // Resize-ийн үеийн хуурамч MouseLeave
        if (_mode == Mode.Alert) return;            // Хэрэглэгч Done/Snooze дарах хүртэл
        if (_mode == Mode.Expanded && (S.Pinned || Keyboard.FocusedElement is TextBox)) return;
        SetMode(Mode.Collapsed);
    }

    private bool IsCursorOverIsland() => GetCursorPos(out var p) && IsPointOverIsland(p.X, p.Y);

    private bool IsPointOverIsland(int x, int y)
    {
        if (PresentationSource.FromVisual(Island) is null || !IsVisible) return false;
        var local = Island.PointFromScreen(new Point(x, y));
        return local.X >= -2 && local.Y >= -2 && local.X <= Island.ActualWidth + 2 && local.Y <= Island.ActualHeight + 2;
    }

    // ═════════════════════ Click / drag ═════════════════════

    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _pressed = true;
        _dragging = false;
        GetCursorPos(out _pressPoint);
        Header.CaptureMouse();
    }

    private void Header_MouseMove(object sender, MouseEventArgs e)
    {
        if (!_pressed || _dragging || e.LeftButton != MouseButtonState.Pressed || S.LockPosition) return;
        GetCursorPos(out var p);
        var threshold = 6 * (_monitor?.Scale ?? 1);
        if (Math.Abs(p.X - _pressPoint.X) < threshold && Math.Abs(p.Y - _pressPoint.Y) < threshold) return;

        _dragging = true;
        Header.ReleaseMouseCapture();
        try { DragMove(); } catch (InvalidOperationException) { }
        OnDragEnd();
        _pressed = false;
    }

    private void Header_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        Header.ReleaseMouseCapture();
        if (_pressed && !_dragging) OnFaceClick();
        _pressed = false;
        _dragging = false;
    }

    private void OnFaceClick()
    {
        Face.Pulse();
        _svc.Brain.Click();
        switch (_mode)
        {
            case Mode.Expanded: SetMode(Mode.Collapsed); break;
            case Mode.Alert: OpenTab("Reminders"); break;
            default: SetMode(Mode.Expanded); break;
        }
    }

    private void OnDragEnd()
    {
        if (!GetWindowRect(_hwnd, out var r)) return;
        var cx = (r.Left + r.Right) / 2;
        var mon = Monitors.FromPoint(cx, r.Top + 4);
        var sc = mon.Scale;
        var offX = (cx - (mon.Bounds.Left + mon.Bounds.Width / 2.0)) / sc;
        var top = (r.Top - mon.Bounds.Top) / sc;
        // Magnetic snap — төв болон дээд ирмэгт наалдана
        if (Math.Abs(offX) < 18) offX = 0;
        if (top < 14) top = 0;
        S.MonitorDeviceName = mon.DeviceName;
        S.OffsetX = Math.Round(offX);
        S.TopOffset = Math.Round(Math.Max(0, top));
        PlaceWindow(Island.ActualWidth, Island.ActualHeight);
    }

    private ContextMenu BuildContextMenu()
    {
        var menu = new ContextMenu();
        MenuItem Item(string header, Action action, bool isChecked = false)
        {
            var mi = new MenuItem { Header = header, IsCheckable = isChecked, IsChecked = isChecked };
            mi.Click += (_, _) => action();
            return mi;
        }
        menu.Items.Add(Item(_mode == Mode.Expanded ? "Control center хаах" : "Control center нээх", ToggleControlCenter));
        var pin = new MenuItem { Header = "Pin", IsCheckable = true, IsChecked = S.Pinned };
        pin.Click += (_, _) => S.Pinned = pin.IsChecked;
        menu.Items.Add(pin);
        var lockItem = new MenuItem { Header = "Байрлал түгжих", IsCheckable = true, IsChecked = S.LockPosition };
        lockItem.Click += (_, _) => S.LockPosition = lockItem.IsChecked;
        menu.Items.Add(lockItem);
        menu.Items.Add(Item("Байрлалыг reset хийх", ResetPosition));
        menu.Items.Add(Item("Түр нуух", () => SetHiddenByUser(true)));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("DeskBot-ийг хаах", () => ExitRequested?.Invoke()));
        return menu;
    }

    private void PinButton_Click(object sender, RoutedEventArgs e) => S.Pinned = !S.Pinned;
    private void CloseButton_Click(object sender, RoutedEventArgs e) => SetMode(Mode.Collapsed);
    private async void MiniPlay_Click(object sender, RoutedEventArgs e) => await _svc.Media.PlayPauseAsync();

    private void UpdatePinGlyph()
    {
        PinButton.Content = S.Pinned ? "" : "";
        PinButton.Foreground = S.Pinned ? (Brush)FindResource("AccentBrush") : (Brush)FindResource("TextPrimary");
    }

    // ═════════════════════ Global cursor / game mode / auto-hide ═════════════════════

    private void OnCursorTick()
    {
        var now = DateTime.Now;

        if (S.GameModeAutoHide && now - _lastGameCheck > TimeSpan.FromSeconds(1.5))
        {
            _lastGameCheck = now;
            CheckFullscreen();
        }
        if (_fullscreenHidden || _userHidden) return;

        if (!GetCursorPos(out var p)) return;
        if (p.X != _lastCursor.X || p.Y != _lastCursor.Y)
        {
            _lastCursor = p;
            Face.SetCursorScreen(p.X, p.Y);
            _center?.OnCursor(p.X, p.Y);
        }

        UpdateAutoHide(p, now);

        // Бусад topmost цонх (taskbar г.м.) дарахаас сэргийлнэ
        if (now - _lastTopmost > TimeSpan.FromSeconds(5))
        {
            _lastTopmost = now;
            SetWindowPos(_hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
    }

    private void CheckFullscreen()
    {
        if (_monitor is null || _hwnd == IntPtr.Zero) return;
        var fs = FullscreenDetector.IsFullscreenOn(_monitor, _hwnd);
        if (fs == _fullscreenHidden) return;
        _fullscreenHidden = fs;
        if (fs)
        {
            if (_mode != Mode.Collapsed && _mode != Mode.Alert) SetMode(Mode.Collapsed, instant: true);
            Visibility = Visibility.Hidden;
            Face.Paused = true;
            _cursorTimer.Interval = TimeSpan.FromMilliseconds(400); // тоглоомын үед бараг юу ч хийхгүй
        }
        else
        {
            _cursorTimer.Interval = TimeSpan.FromMilliseconds(33);
            if (!_userHidden) ShowIsland();
            if (_currentAlert is not null) SetMode(Mode.Alert); // тоглоомын үед хойшилсон reminder
        }
    }

    private void UpdateAutoHide(POINT p, DateTime now)
    {
        if (!S.AutoHide || _mode != Mode.Collapsed)
        {
            if (_hiddenUp) SlideUp(false);
            return;
        }
        var near = IsPointOverIsland(p.X, p.Y);
        if (!near && _monitor is { } mon && GetWindowRect(_hwnd, out var r))
        {
            var sc = mon.Scale;
            var cx = (r.Left + r.Right) / 2;
            var halfW = (S.IslandWidth / 2 + 40) * sc;
            near = Math.Abs(p.X - cx) < halfW && p.Y <= r.Top + 8 * sc;
        }
        if (near)
        {
            _lastNear = now;
            if (_hiddenUp) SlideUp(false);
        }
        else if (!_hiddenUp && now - _lastNear > TimeSpan.FromSeconds(2.5))
        {
            SlideUp(true);
        }
    }

    private void SlideUp(bool up)
    {
        _hiddenUp = up;
        var to = up ? -(S.IslandHeight - 4) : 0;
        var anim = new DoubleAnimation(to, TimeSpan.FromMilliseconds(S.ReducedMotion ? 0 : 260))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
        };
        IslandShift.BeginAnimation(TranslateTransform.YProperty, anim);
        Face.Paused = up; // нуугдсан үед render хийхгүй
    }

    private void OnGlobalMouseDown(int x, int y)
    {
        if (!S.ReactToGlobalClicks || _fullscreenHidden || _userHidden || _hiddenUp) return;
        if (IsPointOverIsland(x, y)) return;
        Face.Glance(x, y);
    }

    // ═════════════════════ Content updates ═════════════════════

    private void UpdateClock()
    {
        var now = DateTime.Now;
        ClockText.Text = now.ToString("HH:mm");
        DateText.Text = now.ToString("ddd d");
    }

    private void UpdateMini()
    {
        var m = _svc.Media.Current;
        if (m is null)
        {
            MiniTitle.Text = _svc.Media.Available ? "Nothing playing" : "Media unavailable";
            MiniTitle.Foreground = (Brush)FindResource("TextSecondary");
            MiniArt.Source = null;
            MiniPlay.IsEnabled = false;
            MiniPlay.Content = "";
        }
        else
        {
            MiniTitle.Text = string.IsNullOrEmpty(m.Artist) ? m.Title : $"{m.Title} · {m.Artist}";
            MiniTitle.Foreground = (Brush)FindResource("TextPrimary");
            MiniArt.Source = m.Art;
            MiniPlay.IsEnabled = m.CanPlayPause;
            MiniPlay.Content = m.IsPlaying ? "" : "";
        }
        UpdateIndicators();
    }

    private void UpdateIndicators()
    {
        var collapsed = _mode == Mode.Collapsed;
        MusicGlyph.Visibility = collapsed && _svc.Media.Current is { IsPlaying: true } ? Visibility.Visible : Visibility.Collapsed;
        var now = DateTimeOffset.Now;
        var next = _svc.Reminders.Book.NextUpcoming(now);
        var soon = next is not null && next.DueAt - now <= ReminderService.ApproachWindow;
        ReminderDot.Visibility = collapsed && (soon || _svc.Reminders.Book.HasFiredPending) ? Visibility.Visible : Visibility.Collapsed;
    }

    // ═════════════════════ Reminder alerts ═════════════════════

    private void ShowNextAlert()
    {
        if (_currentAlert is not null || _alerts.Count == 0) return;
        _currentAlert = _alerts.Dequeue();
        AlertTitle.Text = _currentAlert.Title;
        AlertTime.Text = "Reminder · " + _currentAlert.DueAt.ToLocalTime().ToString("HH:mm");
        if (_fullscreenHidden) return; // Тоглоомын үед саад болохгүй — дараа гарна
        ShowIsland();
        SetMode(Mode.Alert);
    }

    private void AlertSnooze_Click(object sender, RoutedEventArgs e)
    {
        if (_currentAlert is { } r) _svc.Reminders.Snooze(r.Id, TimeSpan.FromMinutes(5));
        FinishAlert();
    }

    private void AlertDone_Click(object sender, RoutedEventArgs e)
    {
        if (_currentAlert is { } r) _svc.Reminders.Complete(r.Id);
        FinishAlert();
    }

    private void FinishAlert()
    {
        _currentAlert = null;
        if (_alerts.Count > 0) { ShowNextAlert(); return; }
        SetMode(IsCursorOverIsland() ? Mode.Hover : Mode.Collapsed);
    }
}
