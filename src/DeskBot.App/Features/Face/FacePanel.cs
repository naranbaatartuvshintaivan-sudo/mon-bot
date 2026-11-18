using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Shapes;
using DeskBot.App.Features.ControlCenter;
using DeskBot.App.Services;
using DeskBot.App.UI;
using DeskBot.App.UI.Controls;
using DeskBot.Core.Expressions;
using DeskBot.Core.Settings;

namespace DeskBot.App.Features.Face;

/// <summary>
/// Robot customization — mood, expression preview, theme, eye shape, slider-ууд.
/// Том preview face нь island дээрх face-тэй ижил settings-ийг хуваалцана (real-time).
/// </summary>
public sealed class FacePanel : UserControl, IFeaturePanel
{
    private static readonly Expression[] Moods = { Expression.Idle, Expression.Happy, Expression.Excited, Expression.Sad, Expression.Confused, Expression.Sleepy };
    private static readonly Expression[] Previews = { Expression.Surprised, Expression.Angry, Expression.Processing, Expression.Listening, Expression.Error, Expression.NewMessage, Expression.Reminder, Expression.LowBattery, Expression.Music };

    private readonly AppServices _svc;
    private AppSettings S => _svc.Settings;
    private readonly RobotFace _preview = new() { Height = 92, Width = 260 };
    private readonly TextBlock _exprLabel = Ui.Caption("");
    private readonly List<(ToggleButton Btn, Expression Mood)> _moodChips = new();
    private readonly List<(ToggleButton Btn, FaceTheme Theme)> _themeChips = new();
    private readonly List<(ToggleButton Btn, EyeShape Shape)> _shapeChips = new();
    private readonly TextBox _customColor = new() { Width = 90 };

    public FacePanel(AppServices svc)
    {
        _svc = svc;
        _preview.Bind(S);
        _preview.Expression = _svc.Brain.Machine.Current;

        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(290) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // ── Left: preview + sliders ──
        var stage = new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(0x03, 0x04, 0x06)),
            CornerRadius = new CornerRadius(22),
            Height = 112,
            Child = _preview,
            Margin = new Thickness(0, 0, 0, 6),
        };
        _exprLabel.HorizontalAlignment = HorizontalAlignment.Center;
        var sliders = Ui.Stack(
            Ui.SliderRow("Нүдний хэмжээ", S, nameof(AppSettings.EyeSize), 0.5, 1.6),
            Ui.SliderRow("Нүдний зай", S, nameof(AppSettings.EyeSpacing), 0.6, 1.8),
            Ui.SliderRow("Glow", S, nameof(AppSettings.GlowIntensity), 0, 1),
            Ui.SliderRow("Анивчих давтамж", S, nameof(AppSettings.BlinkFrequency), 0.2, 3),
            Ui.SliderRow("Animation хурд", S, nameof(AppSettings.AnimationSpeed), 0.25, 2.5));
        var left = Ui.Stack(stage, _exprLabel, new FrameworkElement { Height = 8 }, sliders);
        root.Children.Add(new ScrollViewer { Content = left });

        // ── Right: chips ──
        var moods = Ui.Wrap();
        foreach (var m in Moods)
        {
            var mood = m;
            var chip = Ui.Chip(Label(m), S.BaseMood == m, () => S.BaseMood = mood);
            _moodChips.Add((chip, m));
            moods.Children.Add(chip);
        }

        var previews = Ui.Wrap();
        foreach (var e in Previews)
        {
            var ex = e;
            previews.Children.Add(Ui.Button(Label(e), () => _svc.Brain.Preview(ex)));
        }

        var themes = Ui.Wrap();
        foreach (var t in Enum.GetValues<FaceTheme>())
        {
            var theme = t;
            var content = Ui.Row(new Ellipse { Width = 10, Height = 10, Fill = Swatch(t), Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center }, Ui.Text(t.ToString()));
            var chip = Ui.Chip(content, S.Theme == t, () => S.Theme = theme);
            _themeChips.Add((chip, t));
            themes.Children.Add(chip);
        }

        var shapes = Ui.Wrap();
        foreach (var sh in Enum.GetValues<EyeShape>())
        {
            var shape = sh;
            var chip = Ui.Chip(sh.ToString(), S.EyeShape == sh, () => S.EyeShape = shape);
            _shapeChips.Add((chip, sh));
            shapes.Children.Add(chip);
        }

        _customColor.Text = S.CustomColor;
        _customColor.LostFocus += (_, _) => ApplyCustomColor();
        _customColor.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) ApplyCustomColor(); };

        var right = Ui.Stack(
            Ui.Section("Mood (default төлөв)"), moods,
            Ui.Section("Expression туршиж үзэх · 3 сек"), previews,
            Ui.Section("Theme"), themes,
            Ui.Row(Ui.Caption("Custom өнгө"), new FrameworkElement { Width = 8 }, _customColor),
            Ui.Section("Нүдний хэлбэр"), shapes,
            Ui.Section("Хөдөлгөөн"),
            Ui.Toggle("Cursor дагах", S, nameof(AppSettings.FollowCursor)),
            Ui.Toggle("Хаана ч click хийхэд тийш харах", S, nameof(AppSettings.ReactToGlobalClicks)),
            Ui.Toggle("5 мин хөдөлгөөнгүй бол унтах", S, nameof(AppSettings.SleepWhenIdle)),
            Ui.Toggle("Reduced motion", S, nameof(AppSettings.ReducedMotion)));
        ((FrameworkElement)right.Children[0]).Margin = new Thickness(0, 0, 0, 6);
        var rightScroll = new ScrollViewer { Content = right, Padding = new Thickness(0, 0, 6, 0) };
        Grid.SetColumn(rightScroll, 2);
        root.Children.Add(rightScroll);

        Content = root;
        S.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppSettings.BaseMood) or nameof(AppSettings.Theme) or nameof(AppSettings.EyeShape)) SyncChips();
        };
        OnExpression(_svc.Brain.Machine.Current);
    }

    public void OnShown() => _preview.Paused = false;
    public void OnHidden() => _preview.Paused = true;

    public void OnCursor(int x, int y) => _preview.SetCursorScreen(x, y);

    public void OnExpression(Expression e)
    {
        _preview.Expression = e;
        _exprLabel.Text = $"{Label(e)} · {S.Theme}";
    }

    private void SyncChips()
    {
        foreach (var (b, m) in _moodChips) b.IsChecked = S.BaseMood == m;
        foreach (var (b, t) in _themeChips) b.IsChecked = S.Theme == t;
        foreach (var (b, sh) in _shapeChips) b.IsChecked = S.EyeShape == sh;
        _exprLabel.Text = $"{Label(_preview.Expression)} · {S.Theme}";
    }

    private void ApplyCustomColor()
    {
        var v = _customColor.Text.Trim();
        if (!v.StartsWith('#')) v = "#" + v;
        if (AppSettings.IsHexColor(v))
        {
            S.CustomColor = v.ToUpperInvariant();
            S.Theme = FaceTheme.Custom;
        }
        _customColor.Text = S.CustomColor;
    }

    private Brush Swatch(FaceTheme t) => t switch
    {
        FaceTheme.Aurora => new LinearGradientBrush(Color.FromRgb(0x33, 0xE1, 0xFF), Color.FromRgb(0xA8, 0x5C, 0xFF), 45),
        FaceTheme.Matrix => new SolidColorBrush(Color.FromRgb(0x39, 0xFF, 0x6A)),
        FaceTheme.Glitch => new LinearGradientBrush(Color.FromRgb(0x7C, 0xF7, 0xFF), Color.FromRgb(0xFF, 0x3D, 0xF5), 0),
        FaceTheme.Cyberpunk => new SolidColorBrush(Color.FromRgb(0xFF, 0x2E, 0x88)),
        FaceTheme.Minimal => new SolidColorBrush(Color.FromRgb(0xF2, 0xF5, 0xF7)),
        FaceTheme.Custom => new SolidColorBrush(RobotFace.ParseHex(S.CustomColor)),
        _ => new SolidColorBrush(Color.FromRgb(0x33, 0xE1, 0xFF)),
    };

    private static string Label(Expression e) => e switch
    {
        Expression.NewMessage => "New message",
        Expression.LowBattery => "Low battery",
        _ => e.ToString(),
    };
}
