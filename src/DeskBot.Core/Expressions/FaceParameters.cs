namespace DeskBot.Core.Expressions;

[Flags]
public enum FaceOverlay
{
    None = 0,
    Sparkles = 1 << 0,
    Ring = 1 << 1,
    Wave = 1 << 2,
    PixelX = 1 << 3,
    Bubble = 1 << 4,
    Clock = 1 << 5,
    Battery = 1 << 6,
    Notes = 1 << 7,
    Question = 1 << 8,
    Zzz = 1 << 9,
    Warning = 1 << 10,
}

/// <summary>
/// Нүдний хэлбэрийг тодорхойлох цэвэр тоон параметрүүд. Renderer эдгээрийг lerp хийж
/// expression хооронд зөөлөн шилжинэ. Бүх хэмжээ нь base eye size-тай харьцангуй.
/// </summary>
public readonly record struct FaceParameters(
    double EyeWidth,        // 1 = default
    double EyeHeight,
    double LidTop,          // 0..1 — дээрээс хучих хэсэг
    double LidAngle,        // градус. + = дотор тал доош (уурласан), − = гадна тал доош (гунигтай)
    double BottomCut,       // 0..1 — доороос эллипсээр тайрах (∩ баярласан нүд)
    double OffsetY,         // face өндөртэй харьцангуй
    double Bounce,          // face өндөртэй харьцангуй далайц
    double BounceSpeed,     // rad/s
    double RightEyeScale,   // confused-д тэгш бус
    double RightEyeLift,
    double Glow,            // glow multiplier
    double Brightness,      // 1 = normal
    uint? SemanticColor,    // ARGB. null бол theme өнгө
    FaceOverlay Overlay)
{
    public static FaceParameters Lerp(in FaceParameters a, in FaceParameters b, double t)
    {
        t = Math.Clamp(t, 0, 1);
        static double L(double x, double y, double k) => x + (y - x) * k;
        return new FaceParameters(
            L(a.EyeWidth, b.EyeWidth, t),
            L(a.EyeHeight, b.EyeHeight, t),
            L(a.LidTop, b.LidTop, t),
            L(a.LidAngle, b.LidAngle, t),
            L(a.BottomCut, b.BottomCut, t),
            L(a.OffsetY, b.OffsetY, t),
            L(a.Bounce, b.Bounce, t),
            L(a.BounceSpeed, b.BounceSpeed, t),
            L(a.RightEyeScale, b.RightEyeScale, t),
            L(a.RightEyeLift, b.RightEyeLift, t),
            L(a.Glow, b.Glow, t),
            L(a.Brightness, b.Brightness, t),
            t < 0.5 ? a.SemanticColor : b.SemanticColor,
            t < 0.5 ? a.Overlay : b.Overlay);
    }
}

public static class FaceLibrary
{
    public const uint Red = 0xFFFF3B4A;
    public const uint Amber = 0xFFFFB020;

    private static readonly FaceParameters Neutral = new(
        EyeWidth: 1, EyeHeight: 1, LidTop: 0, LidAngle: 0, BottomCut: 0,
        OffsetY: 0, Bounce: 0, BounceSpeed: 0, RightEyeScale: 1, RightEyeLift: 0,
        Glow: 1, Brightness: 1, SemanticColor: null, Overlay: FaceOverlay.None);

    public static FaceParameters For(Expression e) => e switch
    {
        Expression.Idle => Neutral,
        Expression.Happy => Neutral with { EyeWidth = 1.05, EyeHeight = 0.95, BottomCut = 0.55, OffsetY = -0.04, Bounce = 0.035, BounceSpeed = 3, Glow = 1.2, Brightness = 1.12 },
        Expression.Excited => Neutral with { EyeWidth = 1.18, EyeHeight = 1.15, BottomCut = 0.35, OffsetY = -0.05, Bounce = 0.09, BounceSpeed = 8, Glow = 1.45, Brightness = 1.25, Overlay = FaceOverlay.Sparkles },
        Expression.Sad => Neutral with { EyeWidth = 0.95, EyeHeight = 0.82, LidTop = 0.32, LidAngle = -18, OffsetY = 0.1, Glow = 0.55, Brightness = 0.62 },
        Expression.Confused => Neutral with { LidTop = 0.08, RightEyeScale = 0.7, RightEyeLift = -0.1, Overlay = FaceOverlay.Question },
        Expression.Angry => Neutral with { EyeHeight = 0.88, LidTop = 0.4, LidAngle = 24, Glow = 1.35, SemanticColor = Red },
        Expression.Sleepy => Neutral with { EyeWidth = 1.05, EyeHeight = 0.9, LidTop = 0.62, LidAngle = -4, OffsetY = 0.06, Glow = 0.45, Brightness = 0.55, Overlay = FaceOverlay.Zzz },
        Expression.Surprised => Neutral with { EyeWidth = 1.22, EyeHeight = 1.25, Glow = 1.6, Brightness = 1.3 },
        Expression.Processing => Neutral with { EyeWidth = 0.95, EyeHeight = 1, Overlay = FaceOverlay.Ring },
        Expression.Listening => Neutral with { Overlay = FaceOverlay.Wave, Glow = 1.15 },
        Expression.Error => Neutral with { Glow = 1.25, SemanticColor = Red, Overlay = FaceOverlay.PixelX | FaceOverlay.Warning },
        Expression.NewMessage => Neutral with { EyeWidth = 1.05, EyeHeight = 1.05, Bounce = 0.03, BounceSpeed = 6, Glow = 1.2, Overlay = FaceOverlay.Bubble },
        Expression.Reminder => Neutral with { EyeWidth = 1.05, OffsetY = -0.03, Bounce = 0.03, BounceSpeed = 4, Glow = 1.2, Overlay = FaceOverlay.Clock },
        Expression.LowBattery => Neutral with { LidTop = 0.25, LidAngle = -6, Glow = 0.8, Brightness = 0.85, SemanticColor = Amber, Overlay = FaceOverlay.Battery },
        Expression.Music => Neutral with { BottomCut = 0.42, Bounce = 0.045, BounceSpeed = 8.5, Glow = 1.2, Brightness = 1.1, Overlay = FaceOverlay.Notes },
        _ => Neutral,
    };
}
