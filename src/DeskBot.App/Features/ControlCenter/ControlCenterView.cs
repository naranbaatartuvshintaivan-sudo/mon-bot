using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using DeskBot.App.Features.Face;
using DeskBot.App.Features.Home;
using DeskBot.App.Features.Music;
using DeskBot.App.Features.Reminders;
using DeskBot.App.Features.Settings;
using DeskBot.App.Services;
using DeskBot.App.UI.Windows;
using DeskBot.Core.Expressions;

namespace DeskBot.App.Features.ControlCenter;

/// <summary>Feature module бүр энэ interface-ийг хэрэгжүүлнэ — харагдах үедээ л ажиллана.</summary>
public interface IFeaturePanel
{
    void OnShown();
    void OnHidden();
}

/// <summary>
/// Modular control center. Tab бүр өөрийн panel + service-тэй, lazy үүснэ.
/// Шинэ module нэмэхэд Registry-д нэг мөр нэмэхэд хангалттай.
/// </summary>
public sealed class ControlCenterView : UserControl
{
    private sealed record TabDef(string Key, string Glyph, string Label, Func<FrameworkElement> Create);

    private readonly AppServices _svc;
    private readonly IslandWindow _window;
    private readonly Dictionary<string, FrameworkElement> _panels = new();
    private readonly Dictionary<string, RadioButton> _tabs = new();
    private readonly ContentControl _content = new() { Focusable = false };
    private readonly List<TabDef> _registry;
    private FrameworkElement? _current;
    private bool _shown;

    public ControlCenterView(AppServices svc, IslandWindow window)
    {
        _svc = svc;
        _window = window;
        _registry = new()
        {
            new("Home", "", "Home", () => new HomePanel(_svc)),
            new("Music", "", "Music", () => new MusicPanel(_svc)),
            new("Reminders", "", "Reminders", () => new RemindersPanel(_svc)),
            new("Face", "", "Face", () => new FacePanel(_svc)),
            new("Settings", "", "Settings", () => new SettingsPanel(_svc, _window)),
        };

        var root = new Grid { Margin = new Thickness(14, 2, 14, 14) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var bar = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 10) };
        foreach (var t in _registry)
        {
            var rb = new RadioButton { Style = (Style)FindResource("TabButton"), GroupName = "cc-tabs", Tag = t.Key, Content = TabContent(t) };
            rb.Checked += (_, _) => Show(t.Key);
            _tabs[t.Key] = rb;
            bar.Children.Add(rb);
        }
        root.Children.Add(bar);
        Grid.SetRow(_content, 1);
        root.Children.Add(_content);
        Content = root;

        _tabs["Home"].IsChecked = true;
    }

    private static UIElement TabContent(TabDef t)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        var fg = new Binding(nameof(Foreground)) { RelativeSource = new RelativeSource(RelativeSourceMode.FindAncestor, typeof(RadioButton), 1) };
        var icon = new TextBlock { Text = t.Glyph, FontSize = 12, Margin = new Thickness(0, 0, 6, 0), Style = (Style)Application.Current.FindResource("Icon") };
        icon.SetBinding(TextBlock.ForegroundProperty, fg);
        var label = new TextBlock { Text = t.Label };
        label.SetBinding(TextBlock.ForegroundProperty, fg);
        sp.Children.Add(icon);
        sp.Children.Add(label);
        return sp;
    }

    public void Select(string key)
    {
        if (_tabs.TryGetValue(key, out var rb)) rb.IsChecked = true;
    }

    private void Show(string key)
    {
        if (_current is IFeaturePanel old && _shown) old.OnHidden();
        if (!_panels.TryGetValue(key, out var panel))
        {
            panel = _registry.Find(r => r.Key == key)!.Create();
            _panels[key] = panel;
        }
        _current = panel;
        _content.Content = panel;
        if (_shown && panel is IFeaturePanel p) p.OnShown();
    }

    public void OnShown()
    {
        _shown = true;
        if (_current is IFeaturePanel p) p.OnShown();
    }

    public void OnHidden()
    {
        _shown = false;
        if (_current is IFeaturePanel p) p.OnHidden();
    }

    public void OnCursor(int x, int y)
    {
        if (_shown && _current is FacePanel f) f.OnCursor(x, y);
    }

    public void OnExpression(Expression e)
    {
        if (_panels.TryGetValue("Face", out var f) && f is FacePanel fp) fp.OnExpression(e);
    }
}
