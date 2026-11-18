using DeskBot.Core.Expressions;
using DeskBot.Core.Reminders;
using DeskBot.Core.Settings;
using DeskBot.Core.Storage;

namespace DeskBot.Core.Tests;

public class ReminderBookTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 18, 9, 0, 0, TimeSpan.FromHours(8));

    [Fact]
    public void Rejects_past_and_empty()
    {
        var book = new ReminderBook();
        Assert.Throws<ArgumentException>(() => book.Add("x", Now.AddMinutes(-1), Now));
        Assert.Throws<ArgumentException>(() => book.Add("  ", Now.AddMinutes(5), Now));
    }

    [Fact]
    public void Due_fires_exactly_once()
    {
        var book = new ReminderBook();
        book.Add("Pull-ups", Now.AddMinutes(10), Now);
        Assert.Empty(book.CollectDue(Now.AddMinutes(5)));
        Assert.Single(book.CollectDue(Now.AddMinutes(10)));
        Assert.Empty(book.CollectDue(Now.AddMinutes(11)));
    }

    [Fact]
    public void Snooze_reschedules_and_refires()
    {
        var book = new ReminderBook();
        var r = book.Add("Call", Now.AddMinutes(1), Now);
        book.CollectDue(Now.AddMinutes(1));
        book.Snooze(r.Id, Now.AddMinutes(1), TimeSpan.FromMinutes(10));
        Assert.Empty(book.CollectDue(Now.AddMinutes(5)));
        Assert.Single(book.CollectDue(Now.AddMinutes(11)));
    }

    [Fact]
    public void Approaching_reports_once()
    {
        var book = new ReminderBook();
        book.Add("Meeting", Now.AddMinutes(4), Now);
        Assert.Single(book.CollectApproaching(Now, TimeSpan.FromMinutes(5)));
        Assert.Empty(book.CollectApproaching(Now.AddMinutes(1), TimeSpan.FromMinutes(5)));
    }

    [Fact]
    public void Completed_not_upcoming()
    {
        var book = new ReminderBook();
        var r = book.Add("A", Now.AddHours(1), Now);
        book.Complete(r.Id);
        Assert.Null(book.NextUpcoming(Now));
    }

    [Fact]
    public void On_date_uses_timezone()
    {
        var book = new ReminderBook();
        // 23:30 UB time = 15:30 UTC same day
        book.Add("Late", new DateTimeOffset(2026, 11, 18, 23, 30, 0, TimeSpan.FromHours(8)), Now);
        var ub = TimeZoneInfo.CreateCustomTimeZone("UB", TimeSpan.FromHours(8), "UB", "UB");
        Assert.Single(book.OnDate(new DateOnly(2026, 11, 18), ub));
        Assert.Empty(book.OnDate(new DateOnly(2026, 11, 19), ub));
    }
}

public class SettingsTests
{
    [Fact]
    public void Sanitize_clamps_bad_values()
    {
        var s = new AppSettings { EyeSize = 50, BaseMood = Expression.Angry, CustomColor = "red", Hotkey = "" }.Sanitize();
        Assert.Equal(1.6, s.EyeSize);
        Assert.Equal(Expression.Idle, s.BaseMood);
        Assert.Equal("#33E1FF", s.CustomColor);
        Assert.Equal("Ctrl+Alt+Space", s.Hotkey);
    }

    [Fact]
    public void Roundtrip_and_corruption_fallback()
    {
        var dir = Path.Combine(Path.GetTempPath(), "deskbot-test-" + Guid.NewGuid());
        var path = Path.Combine(dir, "settings.json");
        try
        {
            JsonFileStore.SaveAtomic(path, new AppSettings { Theme = FaceTheme.Matrix, EyeSize = 1.3 });
            var loaded = JsonFileStore.LoadOrDefault(path, () => new AppSettings());
            Assert.Equal(FaceTheme.Matrix, loaded.Theme);
            Assert.Equal(1.3, loaded.EyeSize);
            Assert.Contains("\"Matrix\"", File.ReadAllText(path)); // enum string-ээр

            File.WriteAllText(path, "{ not json");
            var fallback = JsonFileStore.LoadOrDefault(path, () => new AppSettings());
            Assert.Equal(FaceTheme.Classic, fallback.Theme);
            Assert.Single(Directory.GetFiles(dir, "settings.json.corrupt-*"));
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void Property_changed_raised_for_live_preview()
    {
        var s = new AppSettings();
        string? name = null;
        s.PropertyChanged += (_, e) => name = e.PropertyName;
        s.Theme = FaceTheme.Aurora;
        Assert.Equal(nameof(AppSettings.Theme), name);
    }
}
