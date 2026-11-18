using DeskBot.Core.Settings;

namespace DeskBot.App.Services;

/// <summary>Feature module-уудад дамжуулах service-үүдийн багц (DI container-оос үүснэ).</summary>
public sealed record AppServices(
    AppSettings Settings,
    SettingsService SettingsStore,
    CompanionBrain Brain,
    MediaService Media,
    ReminderService Reminders,
    SystemMonitorService System);
