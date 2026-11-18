using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using DeskBot.App.Infrastructure;
using Windows.Media.Control;
using Windows.Storage.Streams;

namespace DeskBot.App.Services;

public sealed record MediaSnapshot(
    string Title,
    string Artist,
    string SourceApp,
    bool IsPlaying,
    TimeSpan Position,
    TimeSpan Duration,
    DateTimeOffset PositionUpdatedAt,
    bool CanPlayPause,
    bool CanNext,
    bool CanPrevious,
    bool CanSeek,
    BitmapSource? Art)
{
    /// <summary>Тоглож байвал сүүлийн update-ээс хойших хугацааг нэмж бодит байрлалыг тооцоолно.</summary>
    public TimeSpan LivePosition(DateTimeOffset now)
    {
        var pos = IsPlaying ? Position + (now - PositionUpdatedAt) : Position;
        if (pos < TimeSpan.Zero) pos = TimeSpan.Zero;
        return Duration > TimeSpan.Zero && pos > Duration ? Duration : pos;
    }

    public bool HasTimeline => Duration > TimeSpan.Zero;
}

/// <summary>
/// Windows Global System Media Transport Controls (GSMTC). Spotify, browser зэрэг
/// media session publish хийдэг бүх app-тай ажиллана. Session байхгүй бол Current = null —
/// хуурамч дуу ХЭЗЭЭ Ч харуулахгүй.
/// </summary>
public sealed class MediaService : IDisposable
{
    private readonly Dispatcher _ui;
    private GlobalSystemMediaTransportControlsSessionManager? _manager;
    private GlobalSystemMediaTransportControlsSession? _session;
    private int _refreshQueued;
    private string _artKey = "";
    private BitmapSource? _art;

    public MediaService(Dispatcher ui) => _ui = ui;

    public bool Available { get; private set; }
    public string? UnavailableReason { get; private set; }
    public MediaSnapshot? Current { get; private set; }

    /// <summary>UI thread дээр raise болно.</summary>
    public event Action? Changed;

    public async Task InitAsync()
    {
        try
        {
            _manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            _manager.CurrentSessionChanged += (_, _) => Attach(_manager.GetCurrentSession());
            Available = true;
            Attach(_manager.GetCurrentSession());
        }
        catch (Exception ex)
        {
            Available = false;
            UnavailableReason = "Windows media session API энэ системд ажиллахгүй байна.";
            CrashLog.Write("GSMTC init алдаа", ex);
            Publish(null);
        }
    }

    private void Attach(GlobalSystemMediaTransportControlsSession? session)
    {
        if (_session is not null)
        {
            _session.MediaPropertiesChanged -= OnSessionEvent;
            _session.PlaybackInfoChanged -= OnSessionEvent;
            _session.TimelinePropertiesChanged -= OnSessionEvent;
        }
        _session = session;
        if (_session is null)
        {
            Publish(null);
            return;
        }
        _session.MediaPropertiesChanged += OnSessionEvent;
        _session.PlaybackInfoChanged += OnSessionEvent;
        _session.TimelinePropertiesChanged += OnSessionEvent;
        QueueRefresh();
    }

    private void OnSessionEvent(GlobalSystemMediaTransportControlsSession sender, object args) => QueueRefresh();

    /// <summary>Олон event зэрэг ирэхэд нэг refresh болгож нэгтгэнэ.</summary>
    private void QueueRefresh()
    {
        if (Interlocked.Exchange(ref _refreshQueued, 1) == 1) return;
        _ = Task.Run(async () =>
        {
            await Task.Delay(60);
            Interlocked.Exchange(ref _refreshQueued, 0);
            await RefreshAsync();
        });
    }

    private async Task RefreshAsync()
    {
        var s = _session;
        if (s is null) { Publish(null); return; }
        try
        {
            var props = await s.TryGetMediaPropertiesAsync();
            var pb = s.GetPlaybackInfo();
            var tl = s.GetTimelineProperties();

            var title = props?.Title ?? "";
            var artist = props?.Artist ?? "";
            var key = $"{s.SourceAppUserModelId}|{title}|{artist}|{props?.AlbumTitle}";
            if (key != _artKey)
            {
                _artKey = key;
                _art = await LoadArtAsync(props?.Thumbnail);
            }

            var snap = new MediaSnapshot(
                Title: string.IsNullOrWhiteSpace(title) ? "Unknown title" : title,
                Artist: artist,
                SourceApp: FriendlyApp(s.SourceAppUserModelId),
                IsPlaying: pb?.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing,
                Position: tl?.Position ?? TimeSpan.Zero,
                Duration: tl is null ? TimeSpan.Zero : tl.EndTime - tl.StartTime,
                PositionUpdatedAt: tl?.LastUpdatedTime ?? DateTimeOffset.Now,
                CanPlayPause: pb?.Controls.IsPlayPauseToggleEnabled ?? false,
                CanNext: pb?.Controls.IsNextEnabled ?? false,
                CanPrevious: pb?.Controls.IsPreviousEnabled ?? false,
                CanSeek: pb?.Controls.IsPlaybackPositionEnabled ?? false,
                Art: _art);
            Publish(snap);
        }
        catch (Exception ex)
        {
            CrashLog.Write("Media refresh алдаа", ex);
        }
    }

    private static async Task<BitmapSource?> LoadArtAsync(IRandomAccessStreamReference? reference)
    {
        if (reference is null) return null;
        try
        {
            using var ras = await reference.OpenReadAsync();
            using var stream = ras.AsStreamForRead();
            var ms = new MemoryStream();
            await stream.CopyToAsync(ms);
            ms.Position = 0;
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.DecodePixelWidth = 200;
            bmp.StreamSource = ms;
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
        catch
        {
            return null; // Зарим app thumbnail өгдөггүй — алдаа биш
        }
    }

    private static string FriendlyApp(string aumid)
    {
        if (string.IsNullOrEmpty(aumid)) return "";
        var a = aumid.ToLowerInvariant();
        if (a.Contains("spotify")) return "Spotify";
        if (a.Contains("chrome")) return "Chrome";
        if (a.Contains("msedge")) return "Edge";
        if (a.Contains("firefox")) return "Firefox";
        if (a.Contains("zunemusic") || a.Contains("media.player")) return "Media Player";
        var name = aumid.Split('!')[0];
        name = name.Split('_')[0];
        return Path.GetFileNameWithoutExtension(name);
    }

    private void Publish(MediaSnapshot? snap) => _ui.BeginInvoke(() =>
    {
        Current = snap;
        Changed?.Invoke();
    });

    // ── Controls ──
    public async Task PlayPauseAsync() { if (_session is { } s) await Safe(s.TryTogglePlayPauseAsync()); }
    public async Task NextAsync() { if (_session is { } s) await Safe(s.TrySkipNextAsync()); }
    public async Task PreviousAsync() { if (_session is { } s) await Safe(s.TrySkipPreviousAsync()); }

    public async Task SeekAsync(TimeSpan position)
    {
        if (_session is { } s && Current is { CanSeek: true })
            await Safe(s.TryChangePlaybackPositionAsync(position.Ticks));
    }

    private static async Task Safe(Windows.Foundation.IAsyncOperation<bool> op)
    {
        try { await op; }
        catch (Exception ex) { CrashLog.Write("Media control алдаа", ex); }
    }

    public void Dispose() => Attach(null);
}
