# DeskBot — macOS native (Swift)

Windows хувилбарын (`../src`) Swift дахин бичлэг. Төлөвлөгөө: [`../docs/HANDOFF-macos.md`](../docs/HANDOFF-macos.md).

## Шаардлага
- macOS 14+ (Apple Silicon), Swift 6 (Command Line Tools хангалттай — Xcode шаардлагагүй)

## Build / Test
```bash
cd macos
swift build
scripts/test.sh          # swift-testing; CLT дээр Testing.framework-ийн замыг автоматаар заана
```

## Статус
| Milestone | Статус |
|---|---|
| M0 — SwiftPM skeleton, Core порт, 23 test | ✅ |
| M1 — Island NSPanel, menu bar, settings persist | ⏳ |
| M2 — RobotFaceView | ⏳ |
| M3 — Hover/Expanded/Pin/Auto-hide/drag | ⏳ |
| M4 — Home, Reminders, Face, Settings, system monitor, hotkey, login item, game mode | ⏳ |
| M5 — Music, `scripts/bundle.sh` → DeskBot.app | ⏳ |

## C#-аас ялгаатай шийдвэрүүд
- `Expression` → `RobotExpression` (`Foundation.Expression`-тэй давхцдаг). Raw value нь C#-ийн нэртэй ижил (`"Happy"` г.м.).
- `ReminderBook` value type (struct); алдааг exception биш `ReminderError`-оор throw хийнэ.
- `DateOnly` → `CalendarDay`, `TimeZoneInfo` → `TimeZone`.
- `AppSettings` нь `@Observable` class; `StartWithWindows` → `startAtLogin`, `MonitorDeviceName` → `monitorID`. JSON key camelCase, дутуу key → default.
- `JSONFileStore.saveAtomic` нь tmp → `replaceItemAt`; эвдэрсэн файл → `*.corrupt-yyyyMMddHHmmss` + default.
- Тоон утгууд (FaceLibrary, priority, clamp хязгаар) C#-тай яг ижил.
