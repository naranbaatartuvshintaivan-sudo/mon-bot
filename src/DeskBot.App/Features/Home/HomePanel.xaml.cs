using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using DeskBot.App.Features.ControlCenter;
using DeskBot.App.Services;

namespace DeskBot.App.Features.Home;

public partial class HomePanel : UserControl, IFeaturePanel
{
    private readonly AppServices _svc;
    private readonly DispatcherTimer _clock = new() { Interval = TimeSpan.FromSeconds(1) };

    public HomePanel(AppServices svc)
    {
        _svc = svc;
        InitializeComponent();
        _clock.Tick += (_, _) => UpdateClock();
    }

    public void OnShown()
    {
        _svc.Media.Changed += UpdateMedia;
        _svc.System.Updated += UpdateSystem;
        _svc.Reminders.ListChanged += UpdateNext;
        UpdateClock();
        UpdateMedia();
        UpdateSystem();
        UpdateNext();
        _clock.Start();
    }

    public void OnHidden()
    {
        _clock.Stop();
        _svc.Media.Changed -= UpdateMedia;
        _svc.System.Updated -= UpdateSystem;
        _svc.Reminders.ListChanged -= UpdateNext;
    }

    private void UpdateClock()
    {
        var now = DateTime.Now;
        BigClock.Text = now.ToString("HH:mm");
        BigDate.Text = now.ToString("dddd, MMMM d", CultureInfo.CurrentCulture);
        UpdateNext(); // "15 мин дараа" текстийг шинэчилнэ
    }

    private void UpdateNext()
    {
        var now = DateTimeOffset.Now;
        var next = _svc.Reminders.Book.NextUpcoming(now);
        if (next is null)
        {
            NextTitle.Text = "Reminder алга";
            NextTime.Text = "Нэмэхийн тулд энд дарна уу";
            return;
        }
        NextTitle.Text = next.Title;
        var left = next.DueAt - now;
        var rel = left.TotalMinutes < 60 ? $"{Math.Ceiling(left.TotalMinutes)} мин дараа"
                : left.TotalHours < 24 ? $"{Math.Floor(left.TotalHours)} цаг {left.Minutes} мин дараа"
                : $"{Math.Floor(left.TotalDays)} өдрийн дараа";
        NextTime.Text = $"{next.DueAt.ToLocalTime():MMM d, HH:mm} · {rel}";
    }

    private void UpdateMedia()
    {
        var m = _svc.Media.Current;
        if (m is null)
        {
            SongTitle.Text = "Юу ч тоглоогүй байна";
            SongArtist.Text = _svc.Media.Available ? "Spotify эсвэл browser-оос тоглуулна уу" : _svc.Media.UnavailableReason;
            ArtBrush.ImageSource = null;
            PlayBtn.IsEnabled = false;
            PlayBtn.Content = "";
            return;
        }
        SongTitle.Text = m.Title;
        SongArtist.Text = string.IsNullOrEmpty(m.SourceApp) ? m.Artist : $"{m.Artist} · {m.SourceApp}";
        ArtBrush.ImageSource = m.Art;
        PlayBtn.IsEnabled = m.CanPlayPause;
        PlayBtn.Content = m.IsPlaying ? "" : "";
    }

    private void UpdateSystem()
    {
        var s = _svc.System;
        CpuText.Text = $"{s.CpuPercent:0}%";
        RamText.Text = $"{s.RamPercent:0}%";
        BatText.Text = s.HasBattery ? $"{s.BatteryPercent}%{(s.OnAcPower ? "⚡" : "")}" : "AC";
        RamDetail.Text = $"RAM {s.RamUsedGb:0.0} / {s.RamTotalGb:0.0} GB";
    }

    private async void Play_Click(object sender, RoutedEventArgs e) => await _svc.Media.PlayPauseAsync();

    private void Next_Click(object sender, MouseButtonEventArgs e)
    {
        if (Window.GetWindow(this) is UI.Windows.IslandWindow w) w.OpenTab("Reminders");
    }
}
