using CommunityToolkit.Mvvm.ComponentModel;
using DeskBot.Core.Expressions;

namespace DeskBot.Core.Settings;

public enum IslandBackground
{
    Oled,
    Translucent,
}

/// <summary>
/// Бүх хэрэглэгчийн тохиргоо. PropertyChanged-ээр UI real-time preview хийж,
/// debounce-тэй хадгалагдана. JSON-оор %AppData%\DeskBot\settings.json-д.
/// </summary>
public sealed partial class AppSettings : ObservableObject
{
    public int SchemaVersion { get; set; } = 1;

    // ── Robot ──────────────────────────────
    [ObservableProperty] private FaceTheme _theme = FaceTheme.Classic;
    [ObservableProperty] private Expression _baseMood = Expression.Idle;
    [ObservableProperty] private EyeShape _eyeShape = EyeShape.Rounded;
    [ObservableProperty] private double _eyeSize = 1.0;
    [ObservableProperty] private double _eyeSpacing = 1.0;
    [ObservableProperty] private double _glowIntensity = 0.7;
    [ObservableProperty] private double _animationSpeed = 1.0;
    [ObservableProperty] private double _blinkFrequency = 1.0;
    [ObservableProperty] private string _customColor = "#33E1FF";

    // ── Dynamic Island ─────────────────────
    [ObservableProperty] private double _islandWidth = 190;
    [ObservableProperty] private double _islandHeight = 34;
    [ObservableProperty] private double _hoverWidth = 360;
    [ObservableProperty] private double _panelWidth = 640;
    [ObservableProperty] private double _panelHeight = 420;
    [ObservableProperty] private double _cornerRadius = 18;
    [ObservableProperty] private double _backgroundOpacity = 0.96;
    [ObservableProperty] private IslandBackground _background = IslandBackground.Oled;
    [ObservableProperty] private double _topOffset = 0;
    [ObservableProperty] private double _offsetX = 0;
    [ObservableProperty] private string _monitorDeviceName = "";
    [ObservableProperty] private int _autoCollapseMs = 700;
    [ObservableProperty] private int _hoverDelayMs = 120;

    // ── Behavior ───────────────────────────
    [ObservableProperty] private bool _pinned;
    [ObservableProperty] private bool _autoHide;
    [ObservableProperty] private bool _lockPosition;
    [ObservableProperty] private bool _followCursor = true;
    [ObservableProperty] private bool _reactToGlobalClicks = true;
    [ObservableProperty] private bool _reducedMotion;
    [ObservableProperty] private bool _performanceMode;
    [ObservableProperty] private bool _gameModeAutoHide = true;
    [ObservableProperty] private bool _startWithWindows;
    [ObservableProperty] private bool _sleepWhenIdle = true;
    [ObservableProperty] private string _hotkey = "Ctrl+Alt+Space";

    /// <summary>Гараар засагдсан эсвэл эвдэрсэн утгуудыг аюулгүй хүрээнд оруулна.</summary>
    public AppSettings Sanitize()
    {
        EyeSize = Math.Clamp(EyeSize, 0.5, 1.6);
        EyeSpacing = Math.Clamp(EyeSpacing, 0.6, 1.8);
        GlowIntensity = Math.Clamp(GlowIntensity, 0, 1);
        AnimationSpeed = Math.Clamp(AnimationSpeed, 0.25, 2.5);
        BlinkFrequency = Math.Clamp(BlinkFrequency, 0.2, 3);
        IslandWidth = Math.Clamp(IslandWidth, 120, 400);
        IslandHeight = Math.Clamp(IslandHeight, 26, 60);
        HoverWidth = Math.Clamp(HoverWidth, IslandWidth, 600);
        PanelWidth = Math.Clamp(PanelWidth, 480, 1000);
        PanelHeight = Math.Clamp(PanelHeight, 320, 800);
        CornerRadius = Math.Clamp(CornerRadius, 0, 30);
        BackgroundOpacity = Math.Clamp(BackgroundOpacity, 0.4, 1);
        TopOffset = Math.Clamp(TopOffset, 0, 400);
        OffsetX = Math.Clamp(OffsetX, -4000, 4000);
        AutoCollapseMs = Math.Clamp(AutoCollapseMs, 0, 10_000);
        HoverDelayMs = Math.Clamp(HoverDelayMs, 0, 2000);
        BaseMood = ExpressionRules.SanitizeBaseMood(BaseMood);
        if (string.IsNullOrWhiteSpace(Hotkey)) Hotkey = "Ctrl+Alt+Space";
        if (!IsHexColor(CustomColor)) CustomColor = "#33E1FF";
        return this;
    }

    public static bool IsHexColor(string? s) =>
        s is { Length: 7 } && s[0] == '#' && s.AsSpan(1).IndexOfAnyExcept("0123456789abcdefABCDEF") < 0;
}
