using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Media;

namespace DeskBot.App.UI;

/// <summary>Code-оор panel бүтээх жижиг helper-ууд — бүх panel нэг төрхтэй байна.</summary>
internal static class Ui
{
    public static T Res<T>(string key) => (T)Application.Current.FindResource(key);

    public static Border Card(UIElement child, Thickness? margin = null) => new()
    {
        Style = Res<Style>("Card"),
        Child = child,
        Margin = margin ?? new Thickness(0, 0, 0, 10),
    };

    public static TextBlock Section(string text) => new() { Text = text.ToUpperInvariant(), Style = Res<Style>("SectionTitle") };

    public static TextBlock Caption(string text) => new() { Text = text, Style = Res<Style>("Caption"), TextWrapping = TextWrapping.Wrap };

    public static TextBlock Text(string text, double size = 12, FontWeight? weight = null) =>
        new() { Text = text, FontSize = size, FontWeight = weight ?? FontWeights.Normal, TextTrimming = TextTrimming.CharacterEllipsis };

    public static TextBlock Icon(string glyph, double size = 14, Brush? fg = null)
    {
        var t = new TextBlock { Text = glyph, FontSize = size, Style = Res<Style>("Icon") };
        if (fg is not null) t.Foreground = fg;
        return t;
    }

    public static Button Button(string content, Action onClick, bool accent = false)
    {
        var b = new Button { Content = content, Style = Res<Style>(accent ? "AccentButton" : "PillButton") };
        b.Click += (_, _) => onClick();
        return b;
    }

    public static Button IconButton(string glyph, Action onClick, string? tooltip = null, double size = 28)
    {
        var b = new Button { Content = glyph, Style = Res<Style>("IconButton"), Width = size, Height = size, FontSize = 12, ToolTip = tooltip };
        b.Click += (_, _) => onClick();
        return b;
    }

    public static ToggleButton Chip(object content, bool isChecked, Action onClick)
    {
        var t = new ToggleButton { Content = content, IsChecked = isChecked, Style = Res<Style>("ChipToggle") };
        t.Click += (_, _) => onClick();
        return t;
    }

    /// <summary>Label + утга + slider. Settings-тэй TwoWay binding → real-time preview.</summary>
    public static FrameworkElement SliderRow(string label, object source, string path, double min, double max, string format = "0.00", double tick = 0)
    {
        var grid = new Grid { Margin = new Thickness(0, 2, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var name = new TextBlock { Text = label, FontSize = 12 };
        var value = new TextBlock { Style = Res<Style>("Caption") };
        value.SetBinding(TextBlock.TextProperty, new Binding(path) { Source = source, StringFormat = "{0:" + format + "}" });
        Grid.SetColumn(value, 1);
        grid.Children.Add(name);
        grid.Children.Add(value);

        var slider = new Slider { Minimum = min, Maximum = max };
        if (tick > 0) { slider.TickFrequency = tick; slider.IsSnapToTickEnabled = true; }
        slider.SetBinding(RangeBase.ValueProperty, new Binding(path) { Source = source, Mode = BindingMode.TwoWay });

        var sp = new StackPanel();
        sp.Children.Add(grid);
        sp.Children.Add(slider);
        return sp;
    }

    public static CheckBox Toggle(string label, object source, string path, string? hint = null)
    {
        var cb = new CheckBox { Content = label, ToolTip = hint };
        cb.SetBinding(ToggleButton.IsCheckedProperty, new Binding(path) { Source = source, Mode = BindingMode.TwoWay });
        return cb;
    }

    public static WrapPanel Wrap() => new() { Orientation = Orientation.Horizontal };

    public static StackPanel Row(params UIElement[] children)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var c in children) sp.Children.Add(c);
        return sp;
    }

    public static StackPanel Stack(params UIElement[] children)
    {
        var sp = new StackPanel();
        foreach (var c in children) sp.Children.Add(c);
        return sp;
    }
}
