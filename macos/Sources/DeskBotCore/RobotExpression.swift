// C# порт: src/DeskBot.Core/Expressions/Expression.cs

/// Robot-ийн сэтгэл хөдлөл болон үйл ажиллагааны төлөв. Visual theme-ээс тусдаа.
/// C# `Expression` — Swift-д `Foundation.Expression` (macOS 15+)-тэй давхцахаас сэргийлж нэрийг өөрчилсөн.
public enum RobotExpression: String, CaseIterable, Codable, Sendable {
    // Core emotions
    case idle = "Idle"
    case happy = "Happy"
    case excited = "Excited"
    case sad = "Sad"
    case confused = "Confused"
    case angry = "Angry"
    case sleepy = "Sleepy"
    case surprised = "Surprised"

    // Activity states
    case processing = "Processing"
    case listening = "Listening"
    case error = "Error"
    case newMessage = "NewMessage"
    case reminder = "Reminder"
    case lowBattery = "LowBattery"
    case music = "Music"
}

/// Expression-ийг хэн хүсэж байгаа вэ. Тоо их байх тусам priority өндөр.
/// ERROR > URGENT REMINDER > NEW MESSAGE > USER CLICK > ACTIVE TASK > MUSIC > CURSOR > IDLE
public enum ExpressionSource: Int, CaseIterable, Sendable {
    case ambient = 5        // sleepy / spontaneous
    case cursor = 10
    case music = 20
    case activeTask = 30
    case systemStatus = 35  // low battery
    case userClick = 40
    case preview = 45       // Face tab дээр хэрэглэгч туршиж үзэх
    case newMessage = 50
    case reminder = 60
    case error = 70

    public var priority: Int { rawValue }
}

/// Visual theme — expression-оос хамааралгүй хослуулж болно (HAPPY + AURORA гэх мэт).
public enum FaceTheme: String, CaseIterable, Codable, Sendable {
    case classic = "Classic"
    case aurora = "Aurora"
    case matrix = "Matrix"
    case glitch = "Glitch"
    case cyberpunk = "Cyberpunk"
    case minimal = "Minimal"
    case custom = "Custom"
}

public enum EyeShape: String, CaseIterable, Codable, Sendable {
    case rounded = "Rounded"
    case pill = "Pill"
    case circle = "Circle"
    case square = "Square"
}

public enum ExpressionRules {
    /// Хэрэглэгч байнгын default mood болгож болох expression-ууд. ANGRY хэзээ ч default биш.
    public static func canBeBaseMood(_ e: RobotExpression) -> Bool {
        switch e {
        case .idle, .happy, .excited, .sad, .confused, .sleepy: true
        default: false
        }
    }

    public static func sanitizeBaseMood(_ e: RobotExpression) -> RobotExpression {
        canBeBaseMood(e) ? e : .idle
    }
}
