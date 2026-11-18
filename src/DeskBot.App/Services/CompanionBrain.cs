using System;
using System.ComponentModel;
using System.Windows.Threading;
using DeskBot.App.Infrastructure.Windows;
using DeskBot.Core.Expressions;
using DeskBot.Core.Reminders;
using DeskBot.Core.Settings;

namespace DeskBot.App.Services;

/// <summary>
/// Automation rules — system event-уудыг expression болгон хөрвүүлнэ. Ярихгүй, текст шидэхгүй:
/// зөвхөн нүдээр л хариу үйлдэл үзүүлнэ.
///  • Spotify/media тоглоход → Music
///  • Reminder ойртоход → Reminder (богино), хугацаа болоход → Reminder (Done/Snooze хүртэл)
///  • Battery ≤ 15% → LowBattery
///  • 5 мин хөдөлгөөнгүй → Sleepy
///  • Robot дээр click → Surprised
/// </summary>
public sealed class CompanionBrain : IDisposable
{
    private readonly AppSettings _settings;
    private readonly MediaService _media;
    private readonly ReminderService _reminders;
    private readonly SystemMonitorService _system;
    private readonly DispatcherTimer _tick = new(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(150) };
    private int _idleCounter;

    public ExpressionStateMachine Machine { get; } = new();

    public event Action<Expression>? ExpressionChanged;

    public CompanionBrain(AppSettings settings, MediaService media, ReminderService reminders, SystemMonitorService system)
    {
        _settings = settings;
        _media = media;
        _reminders = reminders;
        _system = system;

        Machine.Changed += e => ExpressionChanged?.Invoke(e);
        Machine.SetBaseMood(settings.BaseMood, Now);

        _settings.PropertyChanged += OnSettingsChanged;
        _media.Changed += OnMediaChanged;
        _reminders.Fired += OnReminderFired;
        _reminders.Approaching += _ => Machine.Set(ExpressionSource.ActiveTask, Expression.Reminder, Now, TimeSpan.FromSeconds(3));
        _reminders.ListChanged += SyncReminderLayer;
        _system.Updated += OnSystemUpdated;
        _tick.Tick += (_, _) => OnTick();
    }

    private static DateTimeOffset Now => DateTimeOffset.Now;

    public void Start() => _tick.Start();

    public void Click() => Machine.Set(ExpressionSource.UserClick, Expression.Surprised, Now, TimeSpan.FromMilliseconds(450));

    public void Preview(Expression e) => Machine.Set(ExpressionSource.Preview, e, Now, TimeSpan.FromSeconds(3));

    public void ReportError(TimeSpan? duration = null) =>
        Machine.Set(ExpressionSource.Error, Expression.Error, Now, duration ?? TimeSpan.FromSeconds(4));

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppSettings.BaseMood))
            Machine.SetBaseMood(_settings.BaseMood, Now);
    }

    private void OnMediaChanged()
    {
        if (_media.Current is { IsPlaying: true })
            Machine.Set(ExpressionSource.Music, Expression.Music, Now);
        else
            Machine.Clear(ExpressionSource.Music, Now);
    }

    private void OnReminderFired(Reminder r) => Machine.Set(ExpressionSource.Reminder, Expression.Reminder, Now);

    private void SyncReminderLayer()
    {
        if (!_reminders.Book.HasFiredPending)
            Machine.Clear(ExpressionSource.Reminder, Now);
    }

    private void OnSystemUpdated()
    {
        if (_system.HasBattery && !_system.OnAcPower && _system.BatteryPercent is >= 0 and <= 15)
            Machine.Set(ExpressionSource.SystemStatus, Expression.LowBattery, Now);
        else
            Machine.Clear(ExpressionSource.SystemStatus, Now);
    }

    private void OnTick()
    {
        Machine.Tick(Now);

        // Idle шалгалт ~3с тутам
        if (++_idleCounter < 20) return;
        _idleCounter = 0;
        if (_settings.SleepWhenIdle && NativeMethods.IdleTime() > TimeSpan.FromMinutes(5))
            Machine.Set(ExpressionSource.Ambient, Expression.Sleepy, Now);
        else
            Machine.Clear(ExpressionSource.Ambient, Now);
    }

    public void Dispose()
    {
        _tick.Stop();
        _settings.PropertyChanged -= OnSettingsChanged;
    }
}
