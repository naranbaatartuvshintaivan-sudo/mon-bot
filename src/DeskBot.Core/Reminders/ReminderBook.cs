namespace DeskBot.Core.Reminders;

public sealed class Reminder
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "";
    public DateTimeOffset DueAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public bool Done { get; set; }
    /// <summary>Notification аль хэдийн гарсан эсэх (snooze хийвэл false болно).</summary>
    public bool Fired { get; set; }
    /// <summary>"Ойртож байна" анхааруулга гарсан эсэх.</summary>
    public bool Previewed { get; set; }
}

/// <summary>Reminder-уудын цэвэр логик — UI, timer, файлаас хамааралгүй (test хийхэд амар).</summary>
public sealed class ReminderBook
{
    public List<Reminder> Items { get; set; } = new();

    public Reminder Add(string title, DateTimeOffset dueAt, DateTimeOffset now)
    {
        title = title?.Trim() ?? "";
        if (title.Length == 0) throw new ArgumentException("Title хоосон байна.", nameof(title));
        if (dueAt <= now) throw new ArgumentException("Хугацаа ирээдүйд байх ёстой.", nameof(dueAt));
        var r = new Reminder { Title = title, DueAt = dueAt, CreatedAt = now };
        Items.Add(r);
        return r;
    }

    /// <summary>Хугацаа нь болсон, хараахан мэдэгдээгүй reminder-уудыг буцааж Fired болгоно.</summary>
    public IReadOnlyList<Reminder> CollectDue(DateTimeOffset now)
    {
        var due = Items.Where(r => !r.Done && !r.Fired && r.DueAt <= now).OrderBy(r => r.DueAt).ToList();
        foreach (var r in due) r.Fired = true;
        return due;
    }

    /// <summary>window дотор ойртож буй, preview хараахан гараагүй reminder-ууд.</summary>
    public IReadOnlyList<Reminder> CollectApproaching(DateTimeOffset now, TimeSpan window)
    {
        var list = Items.Where(r => !r.Done && !r.Fired && !r.Previewed && r.DueAt > now && r.DueAt - now <= window).ToList();
        foreach (var r in list) r.Previewed = true;
        return list;
    }

    public Reminder? NextUpcoming(DateTimeOffset now) =>
        Items.Where(r => !r.Done && r.DueAt > now).OrderBy(r => r.DueAt).FirstOrDefault();

    public IEnumerable<Reminder> Active => Items.Where(r => !r.Done).OrderBy(r => r.DueAt);

    public bool HasFiredPending => Items.Any(r => r.Fired && !r.Done);

    public void Snooze(Guid id, DateTimeOffset now, TimeSpan by)
    {
        var r = Find(id);
        r.DueAt = now + by;
        r.Fired = false;
        r.Previewed = true;
    }

    public void Complete(Guid id) => Find(id).Done = true;

    public bool Remove(Guid id) => Items.RemoveAll(r => r.Id == id) > 0;

    /// <summary>Тухайн өдөр (local timezone) дээрх reminder-ууд — calendar-ийн цэгүүдэд.</summary>
    public IEnumerable<Reminder> OnDate(DateOnly date, TimeZoneInfo tz) =>
        Items.Where(r => DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(r.DueAt, tz).DateTime) == date)
             .OrderBy(r => r.DueAt);

    /// <summary>Хуучин дууссан item-уудыг retention-оос хэтэрвэл устгана.</summary>
    public int Prune(DateTimeOffset now, TimeSpan keepDone) =>
        Items.RemoveAll(r => r.Done && now - r.DueAt > keepDone);

    private Reminder Find(Guid id) =>
        Items.FirstOrDefault(r => r.Id == id) ?? throw new KeyNotFoundException($"Reminder {id} олдсонгүй.");
}
