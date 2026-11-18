using System;
using System.ComponentModel;
using System.Windows.Threading;
using DeskBot.App.Infrastructure;
using DeskBot.Core.Settings;
using DeskBot.Core.Storage;

namespace DeskBot.App.Services;

/// <summary>Settings load + 500ms debounce-тэй atomic save. Slider чирэх үед диск рүү бөөнөөр бичихгүй.</summary>
public sealed class SettingsService : IDisposable
{
    private readonly DispatcherTimer _debounce = new() { Interval = TimeSpan.FromMilliseconds(500) };

    public AppSettings Settings { get; }

    public SettingsService()
    {
        Settings = JsonFileStore.LoadOrDefault(AppPaths.Settings, () => new AppSettings()).Sanitize();
        Settings.PropertyChanged += OnChanged;
        _debounce.Tick += (_, _) => Flush();
    }

    private void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        _debounce.Stop();
        _debounce.Start();
    }

    public void Flush()
    {
        _debounce.Stop();
        try { JsonFileStore.SaveAtomic(AppPaths.Settings, Settings); }
        catch (Exception ex) { CrashLog.Write("Settings хадгалах алдаа", ex); }
    }

    public void Dispose() => Flush();
}
