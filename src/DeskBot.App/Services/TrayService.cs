using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using DeskBot.App.UI.Windows;
using DeskBot.Core.Expressions;
using DeskBot.Core.Settings;

namespace DeskBot.App.Services;

/// <summary>System tray icon — app-ийг ямар ч үед цэвэрхэн хаах, нуух, тохируулах.</summary>
public sealed class TrayService : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly IslandWindow _window;
    private readonly AppSettings _settings;
    private readonly Icon _iconImage;

    public event Action? ExitRequested;

    public TrayService(IslandWindow window, AppSettings settings)
    {
        _window = window;
        _settings = settings;
        _iconImage = DrawIcon();
        _icon = new NotifyIcon { Icon = _iconImage, Text = "DeskBot", Visible = false };
        _icon.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) _window.ToggleControlCenter(); };
        _icon.ContextMenuStrip = new ContextMenuStrip();
        _icon.ContextMenuStrip.Opening += (_, e) => { BuildMenu(); e.Cancel = false; }; // хоосон menu-г WinForms cancel хийдэг
    }

    public void Show() => _icon.Visible = true;

    private void BuildMenu()
    {
        var m = _icon.ContextMenuStrip!;
        m.Items.Clear();
        m.Items.Add(new ToolStripMenuItem("DeskBot") { Enabled = false });
        m.Items.Add(new ToolStripSeparator());
        m.Items.Add("Control center", null, (_, _) => _window.ToggleControlCenter());
        m.Items.Add(_window.IsHiddenByUser ? "Robot-ийг харуулах" : "Robot-ийг нуух", null, (_, _) => _window.SetHiddenByUser(!_window.IsHiddenByUser));

        var mood = new ToolStripMenuItem("Mood");
        foreach (var e in new[] { Expression.Idle, Expression.Happy, Expression.Excited, Expression.Sad, Expression.Confused, Expression.Sleepy })
        {
            var ex = e;
            mood.DropDownItems.Add(new ToolStripMenuItem(e.ToString(), null, (_, _) => _settings.BaseMood = ex) { Checked = _settings.BaseMood == e });
        }
        m.Items.Add(mood);

        var theme = new ToolStripMenuItem("Theme");
        foreach (var t in Enum.GetValues<FaceTheme>())
        {
            var th = t;
            theme.DropDownItems.Add(new ToolStripMenuItem(t.ToString(), null, (_, _) => _settings.Theme = th) { Checked = _settings.Theme == t });
        }
        m.Items.Add(theme);

        m.Items.Add(new ToolStripMenuItem("Pin", null, (_, _) => _settings.Pinned = !_settings.Pinned) { Checked = _settings.Pinned });
        m.Items.Add(new ToolStripMenuItem("Reduced motion", null, (_, _) => _settings.ReducedMotion = !_settings.ReducedMotion) { Checked = _settings.ReducedMotion });
        m.Items.Add("Settings", null, (_, _) => _window.OpenTab("Settings"));
        m.Items.Add("Байрлал reset", null, (_, _) => _window.ResetPosition());
        m.Items.Add(new ToolStripSeparator());
        m.Items.Add("Exit", null, (_, _) => ExitRequested?.Invoke());
    }

    /// <summary>Tray icon-ийг code-оор зурна — хар pill дээр 2 cyan нүд.</summary>
    private static Icon DrawIcon()
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            using var bg = new SolidBrush(Color.FromArgb(255, 8, 10, 14));
            using var path = RoundRect(new RectangleF(1, 5, 30, 22), 9);
            g.FillPath(bg, path);
            using var eye = new SolidBrush(Color.FromArgb(255, 0x33, 0xE1, 0xFF));
            using var l = RoundRect(new RectangleF(8, 10, 6, 12), 3);
            using var r = RoundRect(new RectangleF(18, 10, 6, 12), 3);
            g.FillPath(eye, l);
            g.FillPath(eye, r);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }

    private static GraphicsPath RoundRect(RectangleF r, float radius)
    {
        var d = radius * 2;
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    public void Dispose()
    {
        _icon.Visible = false; // tray-д "сүнс" icon үлдээхгүй
        _icon.Dispose();
        _iconImage.Dispose();
    }
}
