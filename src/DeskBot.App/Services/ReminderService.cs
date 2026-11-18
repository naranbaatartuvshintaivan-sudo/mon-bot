using System;
using System.Collections.Generic;
using System.Windows.Threading;
using DeskBot.App.Infrastructure;
using DeskBot.Core.Reminders;
using DeskBot.Core.Storage;

namespace DeskBot.App.Services;

/// <summary>Local reminder-ууд (%AppData%\DeskBot\reminders.json). Cloud рүү юу ч илгээхгүй.</summary>
public sealed class ReminderService : IDisposable
{
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(10) };

    public ReminderBook Book { get; }

    /// <summary>Хугацаа нь болсон reminder.</summary>
    public event Action<Reminder>? Fired;
    /// <summary>5 минутын дотор ойртож буй reminder.</summary>
    public event Action<Reminder>? Approaching;
    public event Action? ListChanged;

    public static readonly TimeSpan ApproachWindow = TimeSpan.FromMinutes(5);

    public ReminderService()
    {
        Book = JsonFileStore.LoadOrDefault(AppPaths.Reminders, () => new ReminderBook());
        Book.Prune(DateTimeOffset.Now, TimeSpan.FromDays(30));
        _timer.Tick += (_, _) => Check();
    }

    public void Start()
    {
        _timer.Start();
        // App унтарч байх хооронд хугацаа нь өнгөрсөн reminder-ууд асаахад шууд мэдэгдэнэ
        Dispatcher.CurrentDispatcher.BeginInvoke(Check, DispatcherPriority.ApplicationIdle);
    }

    public Reminder Add(string title, DateTimeOffset due)
    {
        var r = Book.Add(title, due, DateTimeOffset.Now);
        Save();
        return r;
    }

    public void Snooze(Guid id, TimeSpan by) { Book.Snooze(id, DateTimeOffset.Now, by); Save(); }
    public void Complete(Guid id) { Book.Complete(id); Save(); }
    public void Remove(Guid id) { Book.Remove(id); Save(); }

    private void Check()
    {
        var now = DateTimeOffset.Now;
        IReadOnlyList<Reminder> due = Book.CollectDue(now);
        var soon = Book.CollectApproaching(now, ApproachWindow);
        if (due.Count > 0 || soon.Count > 0) Save();
        foreach (var r in soon) Approaching?.Invoke(r);
        foreach (var r in due) Fired?.Invoke(r);
    }

    private void Save()
    {
        try { JsonFileStore.SaveAtomic(AppPaths.Reminders, Book); }
        catch (Exception ex) { CrashLog.Write("Reminder хадгалах алдаа", ex); }
        ListChanged?.Invoke();
    }

    public void Dispose() => _timer.Stop();
}
