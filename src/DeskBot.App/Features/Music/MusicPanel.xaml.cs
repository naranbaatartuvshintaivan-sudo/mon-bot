using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using DeskBot.App.Features.ControlCenter;
using DeskBot.App.Services;

namespace DeskBot.App.Features.Music;

public partial class MusicPanel : UserControl, IFeaturePanel
{
    private readonly AppServices _svc;
    private readonly DispatcherTimer _tick = new() { Interval = TimeSpan.FromMilliseconds(500) };
    private bool _seeking;

    public MusicPanel(AppServices svc)
    {
        _svc = svc;
        InitializeComponent();
        _tick.Tick += (_, _) => UpdatePosition();
        Progress.PreviewMouseLeftButtonDown += (_, _) => _seeking = true;
        Progress.PreviewMouseLeftButtonUp += async (_, _) =>
        {
            if (_svc.Media.Current is { CanSeek: true, HasTimeline: true } m)
                await _svc.Media.SeekAsync(TimeSpan.FromSeconds(Progress.Value * m.Duration.TotalSeconds));
            _seeking = false;
        };
        Progress.LostMouseCapture += (_, _) => _seeking = false;
    }

    public void OnShown()
    {
        _svc.Media.Changed += Update;
        Update();
        _tick.Start();
    }

    public void OnHidden()
    {
        _tick.Stop();
        _svc.Media.Changed -= Update;
    }

    private void Update()
    {
        var m = _svc.Media.Current;
        var has = m is not null;
        PlayerView.Visibility = has ? Visibility.Visible : Visibility.Collapsed;
        EmptyView.Visibility = has ? Visibility.Collapsed : Visibility.Visible;
        if (!_svc.Media.Available)
        {
            EmptyTitle.Text = "Media control боломжгүй";
            EmptyHint.Text = _svc.Media.UnavailableReason ?? "";
        }
        if (m is null) return;

        SourceText.Text = string.IsNullOrEmpty(m.SourceApp) ? "NOW PLAYING" : $"NOW PLAYING · {m.SourceApp.ToUpperInvariant()}";
        TitleText.Text = m.Title;
        ArtistText.Text = m.Artist;
        ArtBrush.ImageSource = m.Art;
        PlayBtn.Content = m.IsPlaying ? "" : "";
        PlayBtn.IsEnabled = m.CanPlayPause;
        PrevBtn.IsEnabled = m.CanPrevious;
        NextBtn.IsEnabled = m.CanNext;
        Progress.IsEnabled = m.CanSeek && m.HasTimeline;

        LimitText.Text = (m.HasTimeline, m.CanSeek) switch
        {
            (false, _) => $"{m.SourceApp} playback хугацааны мэдээлэл өгөхгүй байна.",
            (true, false) => $"{m.SourceApp} seek хийхийг зөвшөөрөхгүй байна.",
            _ => "",
        };
        UpdatePosition();
    }

    private void UpdatePosition()
    {
        if (_svc.Media.Current is not { } m) return;
        var pos = m.LivePosition(DateTimeOffset.Now);
        PosText.Text = Fmt(pos);
        DurText.Text = m.HasTimeline ? Fmt(m.Duration) : "—";
        if (!_seeking && m.HasTimeline)
            Progress.Value = Math.Clamp(pos.TotalSeconds / m.Duration.TotalSeconds, 0, 1);
    }

    private static string Fmt(TimeSpan t) => t.TotalHours >= 1 ? t.ToString(@"h\:mm\:ss") : t.ToString(@"m\:ss");

    private async void Play_Click(object sender, RoutedEventArgs e) => await _svc.Media.PlayPauseAsync();
    private async void Prev_Click(object sender, RoutedEventArgs e) => await _svc.Media.PreviousAsync();
    private async void Next_Click(object sender, RoutedEventArgs e) => await _svc.Media.NextAsync();
}
