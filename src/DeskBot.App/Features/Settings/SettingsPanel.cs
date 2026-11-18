using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DeskBot.App.Features.ControlCenter;
using DeskBot.App.Infrastructure;
using DeskBot.App.Infrastructure.Windows;
using DeskBot.App.Services;
using DeskBot.App.UI;
using DeskBot.App.UI.Windows;
using DeskBot.Core.Settings;

namespace DeskBot.App.Features.Settings;

/// <summary>Island, behavior, privacy тохиргоо. Бүгд real-time, debounce-тэй хадгалагдана.</summary>
public sealed class SettingsPanel : UserControl, IFeaturePanel
{
    private readonly AppServices _svc;
    private readonly IslandWindow _window;
    private AppSettings S => _svc.Settings;
    private readonly ComboBox _monitors = new() { MinWidth = 260 };
    private readonly ComboBox _background = new() { Width = 140 };
    private readonly TextBox _hotkey = new() { Width = 150 };
    private readonly TextBlock _hotkeyStatus = Ui.Caption("");

    public SettingsPanel(AppServices svc, IslandWindow window)
    {
        _svc = svc;
        _window = window;

        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // ── Island ──
        _background.ItemsSource = Enum.GetValues<IslandBackground>();
        _background.SelectedItem = S.Background;
        _background.SelectionChanged += (_, _) => { if (_background.SelectedItem is IslandBackground b) S.Background = b; };

        _monitors.SelectionChanged += (_, _) =>
        {
            if (_monitors.SelectedItem is ComboBoxItem { Tag: string dev } && dev != S.MonitorDeviceName)
            {
                S.MonitorDeviceName = dev;
                S.OffsetX = 0;
            }
        };

        var left = Ui.Stack(
            Ui.Section("Dynamic Island"),
            Ui.Caption("Дэлгэц"), _monitors,
            Ui.SliderRow("Collapsed өргөн", S, nameof(AppSettings.IslandWidth), 120, 400, "0", 2),
            Ui.SliderRow("Өндөр", S, nameof(AppSettings.IslandHeight), 26, 60, "0", 1),
            Ui.SliderRow("Hover өргөн", S, nameof(AppSettings.HoverWidth), 200, 600, "0", 2),
            Ui.SliderRow("Panel өргөн", S, nameof(AppSettings.PanelWidth), 480, 1000, "0", 10),
            Ui.SliderRow("Panel өндөр", S, nameof(AppSettings.PanelHeight), 320, 800, "0", 10),
            Ui.SliderRow("Corner radius", S, nameof(AppSettings.CornerRadius), 0, 30, "0", 1),
            Ui.SliderRow("Тунгалаг бус байдал", S, nameof(AppSettings.BackgroundOpacity), 0.4, 1, "0.00"),
            Ui.SliderRow("Дээрээс зай (0 = notch)", S, nameof(AppSettings.TopOffset), 0, 200, "0", 1),
            Ui.Row(Ui.Caption("Background "), _background),
            Ui.SliderRow("Auto-collapse (ms)", S, nameof(AppSettings.AutoCollapseMs), 0, 3000, "0", 50),
            Ui.SliderRow("Hover мэдрэмж — delay (ms)", S, nameof(AppSettings.HoverDelayMs), 0, 800, "0", 10),
            Ui.Row(Ui.Button("Байрлал reset", _window.ResetPosition)));

        // ── Behavior ──
        _hotkey.Text = S.Hotkey;
        var right = Ui.Stack(
            Ui.Section("Behavior"),
            Ui.Toggle("Pinned — panel нээлттэй үлдэнэ", S, nameof(AppSettings.Pinned)),
            Ui.Toggle("Auto-hide — ашиглахгүй үед дээш нуугдана", S, nameof(AppSettings.AutoHide)),
            Ui.Toggle("Байрлал түгжих", S, nameof(AppSettings.LockPosition)),
            Ui.Toggle("Game mode — fullscreen үед нуугдана", S, nameof(AppSettings.GameModeAutoHide)),
            Ui.Toggle("Performance mode (glow, effect бууруулна)", S, nameof(AppSettings.PerformanceMode)),
            Ui.Toggle("Windows-той хамт асах", S, nameof(AppSettings.StartWithWindows)),
            Ui.Section("Global shortcut"),
            Ui.Row(_hotkey, new FrameworkElement { Width = 8 }, Ui.Button("Хэрэглэх", ApplyHotkey)),
            _hotkeyStatus,
            Ui.Section("Өгөгдөл ба privacy"),
            Ui.Caption("Бүх тохиргоо, reminder таны компьютер дээр л хадгалагдана. Keyboard уншихгүй, дэлгэц бичихгүй, юу ч сервер рүү илгээхгүй. Mouse hook нь зөвхөн click-ийн байрлалыг нүдний animation-д ашиглана."),
            Ui.Row(
                Ui.Button("Data folder", () => OpenFolder(AppPaths.DataDir)),
                Ui.Button("Logs", () => OpenFolder(AppPaths.LogDir))),
            Ui.Caption($"DeskBot v{typeof(SettingsPanel).Assembly.GetName().Version?.ToString(3)}"));

        root.Children.Add(new ScrollViewer { Content = left, Padding = new Thickness(0, 0, 8, 0) });
        var rs = new ScrollViewer { Content = right, Padding = new Thickness(0, 0, 8, 0) };
        Grid.SetColumn(rs, 2);
        root.Children.Add(rs);
        Content = root;
    }

    public void OnShown()
    {
        var items = Monitors.All().Select(m => new ComboBoxItem { Content = m.DisplayLabel, Tag = m.DeviceName }).ToList();
        _monitors.ItemsSource = items;
        var current = Monitors.Resolve(S.MonitorDeviceName).DeviceName;
        _monitors.SelectedItem = items.FirstOrDefault(i => (string)i.Tag == current);
        _hotkeyStatus.Text = "";
    }

    public void OnHidden() { }

    private void ApplyHotkey()
    {
        var old = S.Hotkey;
        if (!GlobalHotkey.TryParse(_hotkey.Text, out _, out _))
        {
            Status("Буруу формат. Жишээ: Ctrl+Alt+Space, Win+Shift+D", error: true);
            return;
        }
        S.Hotkey = _hotkey.Text.Trim();
        var err = _window.ApplyHotkey();
        if (err is not null)
        {
            S.Hotkey = old;
            _window.ApplyHotkey();
            Status(err, error: true);
        }
        else Status($"✓ {S.Hotkey} идэвхжлээ", error: false);
    }

    private void Status(string text, bool error)
    {
        _hotkeyStatus.Text = text;
        _hotkeyStatus.Foreground = error ? Ui.Res<Brush>("DangerBrush") : Ui.Res<Brush>("AccentBrush");
    }

    private static void OpenFolder(string path)
    {
        try
        {
            Directory.CreateDirectory(path);
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
        }
        catch (Exception ex) { CrashLog.Write("Folder нээх алдаа", ex); }
    }
}
