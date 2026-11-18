using System;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using static DeskBot.App.Infrastructure.Windows.NativeMethods;

namespace DeskBot.App.Services;

/// <summary>
/// CPU (GetSystemTimes), RAM (GlobalMemoryStatusEx), Battery (GetSystemPowerStatus).
/// Panel нээлттэй үед 2с, хаалттай үед 30с interval — шаардлагагүй polling хийхгүй.
/// </summary>
public sealed class SystemMonitorService : IDisposable
{
    private readonly DispatcherTimer _timer;
    private ulong _lastIdle, _lastTotal;

    public double CpuPercent { get; private set; }
    public double RamPercent { get; private set; }
    public double RamUsedGb { get; private set; }
    public double RamTotalGb { get; private set; }
    public bool HasBattery { get; private set; }
    public int BatteryPercent { get; private set; } = -1;
    public bool OnAcPower { get; private set; } = true;

    public event Action? Updated;

    public SystemMonitorService()
    {
        _timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromSeconds(30) };
        _timer.Tick += (_, _) => Sample();
    }

    public void Start()
    {
        Sample();
        _timer.Start();
    }

    public void SetFastMode(bool fast)
    {
        _timer.Interval = TimeSpan.FromSeconds(fast ? 2 : 30);
        if (fast) Sample();
    }

    public void Sample()
    {
        if (GetSystemTimes(out var idle, out var kernel, out var user))
        {
            var total = kernel.Value + user.Value; // kernel нь idle-ийг агуулдаг
            if (_lastTotal != 0 && total > _lastTotal)
            {
                var dTotal = total - _lastTotal;
                var dIdle = idle.Value - _lastIdle;
                CpuPercent = Math.Clamp(100.0 * (dTotal - dIdle) / dTotal, 0, 100);
            }
            _lastIdle = idle.Value;
            _lastTotal = total;
        }

        var mem = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
        if (GlobalMemoryStatusEx(ref mem))
        {
            RamPercent = mem.dwMemoryLoad;
            RamTotalGb = mem.ullTotalPhys / 1073741824.0;
            RamUsedGb = (mem.ullTotalPhys - mem.ullAvailPhys) / 1073741824.0;
        }

        if (GetSystemPowerStatus(out var ps))
        {
            HasBattery = ps.BatteryFlag != 128 && ps.BatteryFlag != 255 && ps.BatteryLifePercent != 255;
            BatteryPercent = HasBattery ? ps.BatteryLifePercent : -1;
            OnAcPower = ps.ACLineStatus != 0;
        }

        Updated?.Invoke();
    }

    public void Dispose() => _timer.Stop();
}
