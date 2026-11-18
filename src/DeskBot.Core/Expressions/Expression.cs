namespace DeskBot.Core.Expressions;

/// <summary>Robot-ийн сэтгэл хөдлөл болон үйл ажиллагааны төлөв. Visual theme-ээс тусдаа.</summary>
public enum Expression
{
    // Core emotions
    Idle,
    Happy,
    Excited,
    Sad,
    Confused,
    Angry,
    Sleepy,
    Surprised,

    // Activity states
    Processing,
    Listening,
    Error,
    NewMessage,
    Reminder,
    LowBattery,
    Music,
}

/// <summary>
/// Expression-ийг хэн хүсэж байгаа вэ. Тоо их байх тусам priority өндөр.
/// ERROR > URGENT REMINDER > NEW MESSAGE > USER CLICK > ACTIVE TASK > MUSIC > CURSOR > IDLE
/// </summary>
public enum ExpressionSource
{
    Ambient = 5,      // sleepy / spontaneous
    Cursor = 10,
    Music = 20,
    ActiveTask = 30,
    SystemStatus = 35, // low battery
    UserClick = 40,
    Preview = 45,     // Face tab дээр хэрэглэгч туршиж үзэх
    NewMessage = 50,
    Reminder = 60,
    Error = 70,
}

/// <summary>Visual theme — expression-оос хамааралгүй хослуулж болно (HAPPY + AURORA гэх мэт).</summary>
public enum FaceTheme
{
    Classic,
    Aurora,
    Matrix,
    Glitch,
    Cyberpunk,
    Minimal,
    Custom,
}

public enum EyeShape
{
    Rounded,
    Pill,
    Circle,
    Square,
}

public static class ExpressionRules
{
    /// <summary>Хэрэглэгч байнгын default mood болгож болох expression-ууд. ANGRY хэзээ ч default биш.</summary>
    public static bool CanBeBaseMood(Expression e) =>
        e is Expression.Idle or Expression.Happy or Expression.Excited
          or Expression.Sad or Expression.Confused or Expression.Sleepy;

    public static Expression SanitizeBaseMood(Expression e) => CanBeBaseMood(e) ? e : Expression.Idle;
}
