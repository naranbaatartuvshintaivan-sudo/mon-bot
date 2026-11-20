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
| M1 — Island NSPanel, menu bar, settings persist | ✅ |
| M2 — RobotFaceView (15 expression, анивчилт, cursor харц, click reaction, theme) | ✅ |
| M3 — Hover/Expanded/Alert, Pin, Auto-hide, drag + snap, олон дэлгэц (control center нь placeholder) | ✅ |
| M4 — Home, Reminders (+ Alert), Face, Settings, CPU/RAM/Battery, ⌥Space hotkey, login item, game mode | ✅ |
| M5 — Music, `scripts/bundle.sh` → DeskBot.app | ⏳ |

## C#-аас ялгаатай шийдвэрүүд
- `Expression` → `RobotExpression` (`Foundation.Expression`-тэй давхцдаг). Raw value нь C#-ийн нэртэй ижил (`"Happy"` г.м.).
- `ReminderBook` value type (struct); алдааг exception биш `ReminderError`-оор throw хийнэ.
- `DateOnly` → `CalendarDay`, `TimeZoneInfo` → `TimeZone`.
- `AppSettings` нь `@Observable` class; `StartWithWindows` → `startAtLogin`, `MonitorDeviceName` → `dockScreen`. JSON key camelCase, дутуу key → default.
- `JSONFileStore.saveAtomic` нь tmp → `replaceItemAt`; эвдэрсэн файл → `*.corrupt-yyyyMMddHHmmss` + default.
- Тоон утгууд (FaceLibrary, priority, clamp хязгаар) C#-тай яг ижил.

## Debug
- `.build/debug/DeskBot --render-faces faces.png` — бүх expression-ийг offscreen PNG болгоно (эрх шаардахгүй).
- `.build/debug/DeskBot --render-island island.png` — island-ийн 4 mode (+ notch хувилбар).
- `DESKBOT_SIMULATE_NOTCH=1` — notch-гүй Mac дээр 185pt хуурамч notch.
- `DESKBOT_BENCH_STILL=1` — cursor event авахгүй (idle CPU хэмжих).
- Menu bar → Expression — expression бүрийг Preview layer-ээр 3с туршина.
- `DESKBOT_DEBUG_FACE=1 .build/debug/DeskBot` — 5с тутам face төлөвийг `~/Library/Logs/DeskBot/deskbot.log`-д бичнэ.
- Menu bar → Expression — expression бүрийг 3с туршина.

## CPU
Face нь layer-backed NSView + Core Graphics (SwiftUI Canvas биш). Frame хурд `FaceAnimator.frameDemand`-аар:
active (шилжилт, анивчилт, харц хөдөлж байна) → дэлгэцийн refresh (performance mode 30fps), удаан overlay (zzz, ♪) → 20Hz,
тайван → 10Hz (≥0.2pt өөрчлөлт гарвал л зурна), нуугдсан → зогсоно. Glow = CALayer shadow (GPU).
Хөдөлгөөнгүй mouse-тэй дундаж ~2% (өмнө нь ~15.7%).

## Permission
Шаардлагагүй: global hotkey (Carbon), mouse байрлал, CPU/RAM/Battery, game mode (CGWindowList — цонхны нэр уншихгүй).
Notification Center ашиглахгүй — reminder нь island-ийн Alert. Login item: System Settings-ээс зөвшөөрөл хүсч магадгүй.
