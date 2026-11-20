import Foundation
import Observation

// C# порт: src/DeskBot.Core/Settings/AppSettings.cs
// Ялгаа: StartWithWindows → startAtLogin (SMAppService). JSON key-үүд camelCase.

public enum IslandBackground: String, CaseIterable, Codable, Sendable {
    case oled = "Oled"
    case translucent = "Translucent"
}

/// Бүх хэрэглэгчийн тохиргоо. `@Observable` тул UI real-time preview хийж,
/// debounce-тэй хадгалагдана. JSON: ~/Library/Application Support/DeskBot/settings.json
@Observable
public final class AppSettings: Codable {
    public static let defaultHotkey = "Ctrl+Alt+Space"
    public static let defaultColor = "#33E1FF"

    public var schemaVersion = 1

    // ── Robot ──────────────────────────────
    public var theme: FaceTheme = .classic
    public var baseMood: RobotExpression = .idle
    public var eyeShape: EyeShape = .rounded
    public var eyeSize = 1.0
    public var eyeSpacing = 1.0
    public var glowIntensity = 0.7
    public var animationSpeed = 1.0
    public var blinkFrequency = 1.0
    public var customColor = AppSettings.defaultColor

    // ── Dynamic Island ─────────────────────
    public var islandWidth = 190.0
    public var islandHeight = 34.0
    public var hoverWidth = 360.0
    public var panelWidth = 640.0
    public var panelHeight = 420.0
    public var cornerRadius = 18.0
    public var backgroundOpacity = 0.96
    public var background: IslandBackground = .oled
    public var topOffset = 0.0
    public var offsetX = 0.0
    public var dockScreen = ""         // C#: MonitorDeviceName. macOS: "<localizedName>#<displayID>", "" = үндсэн дэлгэц
    public var autoCollapseMs = 700
    public var hoverDelayMs = 120

    // ── Behavior ───────────────────────────
    public var pinned = false
    public var autoHide = false
    public var lockPosition = false
    public var followCursor = true
    public var reactToGlobalClicks = true
    public var reducedMotion = false
    public var performanceMode = false
    public var gameModeAutoHide = true
    public var startAtLogin = false
    public var sleepWhenIdle = true
    public var hotkey = AppSettings.defaultHotkey

    public init() {}

    /// Гараар засагдсан эсвэл эвдэрсэн утгуудыг аюулгүй хүрээнд оруулна.
    @discardableResult
    public func sanitize() -> AppSettings {
        eyeSize = clamp(eyeSize, 0.5, 1.6)
        eyeSpacing = clamp(eyeSpacing, 0.6, 1.8)
        glowIntensity = clamp(glowIntensity, 0, 1)
        animationSpeed = clamp(animationSpeed, 0.25, 2.5)
        blinkFrequency = clamp(blinkFrequency, 0.2, 3)
        islandWidth = clamp(islandWidth, 120, 400)
        islandHeight = clamp(islandHeight, 26, 60)
        hoverWidth = clamp(hoverWidth, islandWidth, 600)
        panelWidth = clamp(panelWidth, 480, 1000)
        panelHeight = clamp(panelHeight, 320, 800)
        cornerRadius = clamp(cornerRadius, 0, 30)
        backgroundOpacity = clamp(backgroundOpacity, 0.4, 1)
        topOffset = clamp(topOffset, 0, 400)
        offsetX = clamp(offsetX, -4000, 4000)
        autoCollapseMs = min(max(autoCollapseMs, 0), 10_000)
        hoverDelayMs = min(max(hoverDelayMs, 0), 2000)
        baseMood = ExpressionRules.sanitizeBaseMood(baseMood)
        if hotkey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hotkey = Self.defaultHotkey }
        if !Self.isHexColor(customColor) { customColor = Self.defaultColor }
        return self
    }

    public static func isHexColor(_ s: String?) -> Bool {
        guard let s, s.count == 7, s.first == "#" else { return false }
        return s.dropFirst().allSatisfy { $0.isHexDigit && $0.isASCII }
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        v.isNaN ? lo : min(max(v, lo), hi)
    }

    // MARK: - Codable
    // @Observable нь property-г `_name` backing болгодог тул CodingKeys-ийг гараар бичнэ.
    // Дутуу key → default (хуучин/гар засварласан файл эвдрэхгүй).

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, theme, baseMood, eyeShape, eyeSize, eyeSpacing, glowIntensity,
             animationSpeed, blinkFrequency, customColor,
             islandWidth, islandHeight, hoverWidth, panelWidth, panelHeight, cornerRadius,
             backgroundOpacity, background, topOffset, offsetX, dockScreen, autoCollapseMs, hoverDelayMs,
             pinned, autoHide, lockPosition, followCursor, reactToGlobalClicks, reducedMotion,
             performanceMode, gameModeAutoHide, startAtLogin, sleepWhenIdle, hotkey
    }

    /// M0–M2 хувилбарын key (уншихад л).
    private enum LegacyKeys: String, CodingKey { case monitorID }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        func d<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        schemaVersion = try d(.schemaVersion, schemaVersion)
        theme = try d(.theme, theme)
        baseMood = try d(.baseMood, baseMood)
        eyeShape = try d(.eyeShape, eyeShape)
        eyeSize = try d(.eyeSize, eyeSize)
        eyeSpacing = try d(.eyeSpacing, eyeSpacing)
        glowIntensity = try d(.glowIntensity, glowIntensity)
        animationSpeed = try d(.animationSpeed, animationSpeed)
        blinkFrequency = try d(.blinkFrequency, blinkFrequency)
        customColor = try d(.customColor, customColor)
        islandWidth = try d(.islandWidth, islandWidth)
        islandHeight = try d(.islandHeight, islandHeight)
        hoverWidth = try d(.hoverWidth, hoverWidth)
        panelWidth = try d(.panelWidth, panelWidth)
        panelHeight = try d(.panelHeight, panelHeight)
        cornerRadius = try d(.cornerRadius, cornerRadius)
        backgroundOpacity = try d(.backgroundOpacity, backgroundOpacity)
        background = try d(.background, background)
        topOffset = try d(.topOffset, topOffset)
        offsetX = try d(.offsetX, offsetX)
        dockScreen = try c.decodeIfPresent(String.self, forKey: .dockScreen)
            ?? legacy.decodeIfPresent(String.self, forKey: .monitorID) ?? dockScreen
        autoCollapseMs = try d(.autoCollapseMs, autoCollapseMs)
        hoverDelayMs = try d(.hoverDelayMs, hoverDelayMs)
        pinned = try d(.pinned, pinned)
        autoHide = try d(.autoHide, autoHide)
        lockPosition = try d(.lockPosition, lockPosition)
        followCursor = try d(.followCursor, followCursor)
        reactToGlobalClicks = try d(.reactToGlobalClicks, reactToGlobalClicks)
        reducedMotion = try d(.reducedMotion, reducedMotion)
        performanceMode = try d(.performanceMode, performanceMode)
        gameModeAutoHide = try d(.gameModeAutoHide, gameModeAutoHide)
        startAtLogin = try d(.startAtLogin, startAtLogin)
        sleepWhenIdle = try d(.sleepWhenIdle, sleepWhenIdle)
        hotkey = try d(.hotkey, hotkey)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(theme, forKey: .theme)
        try c.encode(baseMood, forKey: .baseMood)
        try c.encode(eyeShape, forKey: .eyeShape)
        try c.encode(eyeSize, forKey: .eyeSize)
        try c.encode(eyeSpacing, forKey: .eyeSpacing)
        try c.encode(glowIntensity, forKey: .glowIntensity)
        try c.encode(animationSpeed, forKey: .animationSpeed)
        try c.encode(blinkFrequency, forKey: .blinkFrequency)
        try c.encode(customColor, forKey: .customColor)
        try c.encode(islandWidth, forKey: .islandWidth)
        try c.encode(islandHeight, forKey: .islandHeight)
        try c.encode(hoverWidth, forKey: .hoverWidth)
        try c.encode(panelWidth, forKey: .panelWidth)
        try c.encode(panelHeight, forKey: .panelHeight)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try c.encode(background, forKey: .background)
        try c.encode(topOffset, forKey: .topOffset)
        try c.encode(offsetX, forKey: .offsetX)
        try c.encode(dockScreen, forKey: .dockScreen)
        try c.encode(autoCollapseMs, forKey: .autoCollapseMs)
        try c.encode(hoverDelayMs, forKey: .hoverDelayMs)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(autoHide, forKey: .autoHide)
        try c.encode(lockPosition, forKey: .lockPosition)
        try c.encode(followCursor, forKey: .followCursor)
        try c.encode(reactToGlobalClicks, forKey: .reactToGlobalClicks)
        try c.encode(reducedMotion, forKey: .reducedMotion)
        try c.encode(performanceMode, forKey: .performanceMode)
        try c.encode(gameModeAutoHide, forKey: .gameModeAutoHide)
        try c.encode(startAtLogin, forKey: .startAtLogin)
        try c.encode(sleepWhenIdle, forKey: .sleepWhenIdle)
        try c.encode(hotkey, forKey: .hotkey)
    }
}
