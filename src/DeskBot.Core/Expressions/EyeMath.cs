namespace DeskBot.Core.Expressions;

public static class EyeMath
{
    /// <summary>
    /// Face төвөөс cursor руу чиглэсэн, -1..1 хүрээнд хязгаарлагдсан харах вектор.
    /// range-ээс хол бол бүрэн хазайна, ойр бол бага хазайна (байгалийн).
    /// </summary>
    public static (double X, double Y) LookVector(double dx, double dy, double range)
    {
        var d = Math.Sqrt(dx * dx + dy * dy);
        if (d < 1e-6 || range <= 0) return (0, 0);
        var mag = Math.Min(1.0, d / range);
        // Ease — ойрхон үед мэдрэмж өндөр, хол үед аажмаар saturate
        mag = 1 - (1 - mag) * (1 - mag);
        return (dx / d * mag, dy / d * mag);
    }

    /// <summary>Frame-rate-аас хамааралгүй exponential smoothing коэффициент.</summary>
    public static double SmoothFactor(double dtSeconds, double rate) =>
        dtSeconds <= 0 ? 0 : 1 - Math.Exp(-rate * dtSeconds);

    public static double EaseOutCubic(double t)
    {
        t = Math.Clamp(t, 0, 1);
        var u = 1 - t;
        return 1 - u * u * u;
    }

    /// <summary>Нүд анивчих openness (1 = нээлттэй). phase 0..1.</summary>
    public static double BlinkOpenness(double phase)
    {
        if (phase <= 0 || phase >= 1) return 1;
        return 1 - Math.Sin(Math.PI * phase) * 0.92;
    }
}
