using System;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using DeskBot.App.Features.ControlCenter;
using DeskBot.App.Services;
using DeskBot.App.UI;
using DeskBot.Core.Reminders;

namespace DeskBot.App.Features.Reminders;

/// <summary>
/// Сарын calendar (Даваа гарагаас эхэлнэ) + reminder нэмэх/жагсаалт.
/// Бүх өгөгдөл local. Google Calendar-ийг дараа нь ICalendarSource болгон OAuth-оор нэмнэ.
/// </summary>
public sealed class RemindersPanel : UserControl, IFeaturePanel
{
    private readonly AppServices _svc;
    private DateOnly _month = DateOnly.FromDateTime(DateTime.Today);
    private DateOnly _selected = DateOnly.FromDateTime(DateTime.Today);

    private readonly TextBlock _monthLabel = Ui.Text("", 13, FontWeights.SemiBold);
    private readonly UniformGrid _days = new() { Columns = 7, Rows = 6 };
    private readonly TextBox _title = new() { Margin = new Thickness(0, 0, 0, 8) };
    private readonly TextBox _time = new() { Width = 70, Margin = new Thickness(0, 0, 8, 0), Text = "" };
    private readonly TextBlock _selectedLabel = Ui.Caption("");
    private readonly TextBlock _error = new() { Foreground = Ui.Res<Brush>("DangerBrush"), FontSize = 11, TextWrapping = TextWrapping.Wrap };
    private readonly StackPanel _list = new();
    private readonly TextBlock _listTitle = Ui.Section("");

    public RemindersPanel(AppServices svc)
    {
        _svc = svc;

        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(250) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // ── Calendar ──
        var header = new Grid { Margin = new Thickness(0, 0, 0, 6) };
        header.Children.Add(_monthLabel);
        _monthLabel.VerticalAlignment = VerticalAlignment.Center;
        var nav = Ui.Row(
            Ui.IconButton("", () => { _month = _month.AddMonths(-1); RenderCalendar(); }, "Өмнөх сар", 26),
            Ui.IconButton("", () => { _month = _month.AddMonths(1); RenderCalendar(); }, "Дараагийн сар", 26));
        nav.HorizontalAlignment = HorizontalAlignment.Right;
        header.Children.Add(nav);

        var dow = new UniformGrid { Columns = 7, Margin = new Thickness(0, 0, 0, 2) };
        foreach (var d in new[] { "Да", "Мя", "Лх", "Пү", "Ба", "Бя", "Ня" })
            dow.Children.Add(new TextBlock { Text = d, Style = Ui.Res<Style>("Caption"), HorizontalAlignment = HorizontalAlignment.Center });

        var cal = Ui.Card(Ui.Stack(header, dow, _days), new Thickness(0));
        cal.VerticalAlignment = VerticalAlignment.Top;
        root.Children.Add(cal);

        // ── Add form + list ──
        var quick = Ui.Wrap();
        quick.Children.Add(Ui.Button("+15 мин", () => Quick(TimeSpan.FromMinutes(15))));
        quick.Children.Add(Ui.Button("+1 цаг", () => Quick(TimeSpan.FromHours(1))));
        quick.Children.Add(Ui.Button("Маргааш 09:00", () =>
        {
            _selected = DateOnly.FromDateTime(DateTime.Today.AddDays(1));
            _time.Text = "09:00";
            RenderAll();
        }));

        _title.KeyDown += (_, e) => { if (e.Key == Key.Enter) Add(); };
        _time.KeyDown += (_, e) => { if (e.Key == Key.Enter) Add(); };

        var timeRow = Ui.Row(_time, _selectedLabel, new FrameworkElement { Width = 10 }, Ui.Button("Нэмэх", Add, accent: true));
        _selectedLabel.VerticalAlignment = VerticalAlignment.Center;
        _selectedLabel.Margin = new Thickness(0, 0, 0, 6);
        _time.Margin = new Thickness(0, 0, 8, 6);
        _time.ToolTip = "Цаг (HH:mm)";

        var form = Ui.Card(Ui.Stack(Ui.Caption("Шинэ reminder"), new FrameworkElement { Height = 6 }, _title, timeRow, quick, _error));
        var listScroll = new ScrollViewer { Content = _list };

        var right = new Grid();
        right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        right.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        right.Children.Add(form);
        _listTitle.Margin = new Thickness(2, 0, 0, 6);
        Grid.SetRow(_listTitle, 1);
        right.Children.Add(_listTitle);
        Grid.SetRow(listScroll, 2);
        right.Children.Add(listScroll);
        Grid.SetColumn(right, 2);
        root.Children.Add(right);

        Content = root;
        _time.Text = DateTime.Now.AddMinutes(30).ToString("HH:mm");
    }

    public void OnShown()
    {
        _svc.Reminders.ListChanged += RenderAll;
        RenderAll();
    }

    public void OnHidden() => _svc.Reminders.ListChanged -= RenderAll;

    private void RenderAll()
    {
        RenderCalendar();
        RenderList();
        _selectedLabel.Text = _selected == DateOnly.FromDateTime(DateTime.Today) ? "Өнөөдөр" : _selected.ToString("MMM d, ddd", CultureInfo.CurrentCulture);
    }

    private void RenderCalendar()
    {
        _monthLabel.Text = new DateTime(_month.Year, _month.Month, 1).ToString("MMMM yyyy", CultureInfo.CurrentCulture);
        _days.Children.Clear();
        var first = new DateOnly(_month.Year, _month.Month, 1);
        var offset = ((int)first.DayOfWeek + 6) % 7; // Даваа = 0
        var start = first.AddDays(-offset);
        var today = DateOnly.FromDateTime(DateTime.Today);
        var tz = TimeZoneInfo.Local;

        for (var i = 0; i < 42; i++)
        {
            var day = start.AddDays(i);
            var inMonth = day.Month == _month.Month;
            var hasItems = _svc.Reminders.Book.OnDate(day, tz).Any(r => !r.Done);
            var isSel = day == _selected;
            var isToday = day == today;

            var g = new Grid { Height = 30 };
            var bg = new Border
            {
                CornerRadius = new CornerRadius(8),
                Margin = new Thickness(1),
                Background = isSel ? new SolidColorBrush(Color.FromArgb(0x40, 0x33, 0xE1, 0xFF)) : Brushes.Transparent,
                BorderBrush = isToday ? Ui.Res<Brush>("AccentBrush") : Brushes.Transparent,
                BorderThickness = new Thickness(1),
            };
            g.Children.Add(bg);
            g.Children.Add(new TextBlock
            {
                Text = day.Day.ToString(),
                FontSize = 11.5,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = inMonth ? Ui.Res<Brush>("TextPrimary") : Ui.Res<Brush>("TextMuted"),
            });
            if (hasItems)
                g.Children.Add(new Ellipse { Width = 4, Height = 4, Fill = new SolidColorBrush(Color.FromRgb(0xFF, 0xB0, 0x20)), VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 3) });

            g.Cursor = Cursors.Hand;
            g.Background = Brushes.Transparent;
            g.MouseLeftButtonUp += (_, _) =>
            {
                _selected = day;
                if (day.Month != _month.Month) _month = new DateOnly(day.Year, day.Month, 1);
                RenderAll();
            };
            _days.Children.Add(g);
        }
    }

    private void RenderList()
    {
        _list.Children.Clear();
        var tz = TimeZoneInfo.Local;
        var items = _svc.Reminders.Book.OnDate(_selected, tz).ToList();
        _listTitle.Text = (_selected == DateOnly.FromDateTime(DateTime.Today) ? "ӨНӨӨДӨР" : _selected.ToString("MMM d", CultureInfo.CurrentCulture).ToUpperInvariant()) + $" · {items.Count}";

        if (items.Count == 0)
        {
            var upcoming = _svc.Reminders.Book.Active.Where(r => r.DueAt > DateTimeOffset.Now).Take(3).ToList();
            _list.Children.Add(Ui.Caption(upcoming.Count == 0 ? "Энэ өдөр reminder алга." : "Энэ өдөр reminder алга. Удахгүй:"));
            foreach (var r in upcoming) _list.Children.Add(ItemRow(r, showDate: true));
            return;
        }
        foreach (var r in items) _list.Children.Add(ItemRow(r, showDate: false));
    }

    private FrameworkElement ItemRow(Reminder r, bool showDate)
    {
        var g = new Grid { Margin = new Thickness(0, 6, 0, 0) };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var local = r.DueAt.ToLocalTime();
        var title = Ui.Text(r.Title, 12.5, FontWeights.SemiBold);
        if (r.Done) { title.TextDecorations = TextDecorations.Strikethrough; title.Opacity = 0.5; }
        var sub = Ui.Caption((showDate ? local.ToString("MMM d, ") : "") + local.ToString("HH:mm") + (r.Fired && !r.Done ? " · хугацаа болсон" : ""));
        g.Children.Add(Ui.Stack(title, sub));
        var actions = Ui.Row();
        if (!r.Done) actions.Children.Add(Ui.IconButton("", () => _svc.Reminders.Complete(r.Id), "Done"));
        actions.Children.Add(Ui.IconButton("", () => _svc.Reminders.Remove(r.Id), "Устгах"));
        Grid.SetColumn(actions, 1);
        g.Children.Add(actions);
        return new Border { Child = g, Background = Ui.Res<Brush>("CardBrush"), CornerRadius = new CornerRadius(10), Padding = new Thickness(10, 6, 6, 6), Margin = new Thickness(0, 0, 4, 0) };
    }

    private void Quick(TimeSpan delta)
    {
        var due = DateTime.Now + delta;
        _selected = DateOnly.FromDateTime(due);
        _time.Text = due.ToString("HH:mm");
        RenderAll();
        _title.Focus();
    }

    private void Add()
    {
        _error.Text = "";
        if (!TimeOnly.TryParseExact(_time.Text.Trim(), new[] { "HH:mm", "H:mm" }, CultureInfo.InvariantCulture, DateTimeStyles.None, out var t))
        {
            _error.Text = "Цагийг HH:mm хэлбэрээр оруулна уу (ж: 14:30).";
            return;
        }
        var localDt = _selected.ToDateTime(t);
        var due = new DateTimeOffset(localDt, TimeZoneInfo.Local.GetUtcOffset(localDt));
        try
        {
            _svc.Reminders.Add(_title.Text, due);
            _title.Text = "";
        }
        catch (ArgumentException ex)
        {
            _error.Text = ex.Message.Split(" (")[0];
        }
    }
}
