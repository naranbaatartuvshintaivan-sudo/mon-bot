using System;
using Microsoft.Win32;

namespace DeskBot.App.Infrastructure.Windows;

/// <summary>HKCU Run key — admin эрх шаардахгүй, хэрэглэгч өөрөө асаана.</summary>
internal static class StartupRegistration
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "DeskBot";

    public static bool Apply(bool enable)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
                            ?? Registry.CurrentUser.CreateSubKey(RunKey);
            if (enable)
            {
                var exe = Environment.ProcessPath;
                if (string.IsNullOrEmpty(exe)) return false;
                key.SetValue(Name, $"\"{exe}\"");
            }
            else if (key.GetValue(Name) is not null)
            {
                key.DeleteValue(Name, throwOnMissingValue: false);
            }
            return true;
        }
        catch (Exception ex)
        {
            CrashLog.Write("Startup registration алдаа: " + ex.Message);
            return false;
        }
    }
}
