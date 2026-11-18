using System;
using System.ComponentModel;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using DeskBot.App.Infrastructure;
using DeskBot.App.Infrastructure.Windows;
using DeskBot.App.Services;
using DeskBot.App.UI.Windows;
using DeskBot.Core.Settings;
using Microsoft.Extensions.DependencyInjection;

namespace DeskBot.App;

public partial class App : Application
{
    private Mutex? _mutex;
    private ServiceProvider? _services;
    private bool _exiting;

    protected override void OnStartup(StartupEventArgs e)
    {
        // Давхар process ажиллуулахгүй
        _mutex = new Mutex(true, @"Local\DeskBot.SingleInstance", out var created);
        if (!created)
        {
            _mutex.Dispose();
            _mutex = null;
            Shutdown();
            return;
        }

        DispatcherUnhandledException += (_, a) =>
        {
            CrashLog.Write("UI exception", a.Exception);
            a.Handled = true; // Desktop companion нэг алдаанаас болж унтрахгүй
            _services?.GetService<CompanionBrain>()?.ReportError();
        };
        AppDomain.CurrentDomain.UnhandledException += (_, a) => CrashLog.Write("Fatal exception", a.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, a) => { CrashLog.Write("Task exception", a.Exception); a.SetObserved(); };

        base.OnStartup(e);

        var sc = new ServiceCollection();
        sc.AddSingleton<SettingsService>();
        sc.AddSingleton(sp => sp.GetRequiredService<SettingsService>().Settings);
        sc.AddSingleton(_ => new MediaService(Dispatcher));
        sc.AddSingleton<SystemMonitorService>();
        sc.AddSingleton<ReminderService>();
        sc.AddSingleton<CompanionBrain>();
        sc.AddSingleton<AppServices>();
        sc.AddSingleton<IslandWindow>();
        sc.AddSingleton<TrayService>();
        _services = sc.BuildServiceProvider();

        var settings = _services.GetRequiredService<AppSettings>();
        settings.PropertyChanged += OnSettingsChanged;
        if (settings.StartWithWindows) StartupRegistration.Apply(true);

        var island = _services.GetRequiredService<IslandWindow>();
        var tray = _services.GetRequiredService<TrayService>();
        island.ExitRequested += ExitApp;
        tray.ExitRequested += ExitApp;

        island.Show();
        tray.Show();

        _services.GetRequiredService<SystemMonitorService>().Start();
        _services.GetRequiredService<ReminderService>().Start();
        _services.GetRequiredService<CompanionBrain>().Start();
        _ = _services.GetRequiredService<MediaService>().InitAsync();

        CrashLog.Write("DeskBot started");
    }

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(AppSettings.StartWithWindows) && sender is AppSettings s)
            StartupRegistration.Apply(s.StartWithWindows);
    }

    private void ExitApp()
    {
        if (_exiting) return;
        _exiting = true;
        try
        {
            _services?.GetService<SettingsService>()?.Flush();
            _services?.GetService<IslandWindow>()?.Close(); // hook, hotkey, timer-уудыг чөлөөлнө
        }
        catch (Exception ex) { CrashLog.Write("Exit алдаа", ex); }
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        try { _services?.Dispose(); } // Tray icon, media, timer-уудыг dispose
        catch (Exception ex) { CrashLog.Write("Dispose алдаа", ex); }
        if (_mutex is not null)
        {
            _mutex.ReleaseMutex();
            _mutex.Dispose();
        }
        base.OnExit(e);
    }
}
