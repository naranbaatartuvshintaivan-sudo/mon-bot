using System;
using System.IO;

namespace DeskBot.App.Infrastructure;

internal static class AppPaths
{
    public static string DataDir { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DeskBot");

    public static string LogDir { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeskBot", "logs");

    public static string Settings => Path.Combine(DataDir, "settings.json");
    public static string Reminders => Path.Combine(DataDir, "reminders.json");
}

internal static class CrashLog
{
    private static readonly object Gate = new();

    public static void Write(string message, Exception? ex = null)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(AppPaths.LogDir);
                var file = Path.Combine(AppPaths.LogDir, $"deskbot-{DateTime.Now:yyyyMMdd}.log");
                File.AppendAllText(file, $"[{DateTime.Now:HH:mm:ss.fff}] {message}{(ex is null ? "" : Environment.NewLine + ex)}{Environment.NewLine}");
            }
        }
        catch { /* log бичих нь хэзээ ч app-ийг унагахгүй */ }
    }
}
