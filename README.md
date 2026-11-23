# DeskBot (MON BOT)

> Windows desktop-ийн дээд хэсэгт амьдардаг жижигхэн дижитал амьтан. Cursor-ыг чинь нүдээрээ дагаж, анивчиж, сэтгэл хөдлөлөө илэрхийлнэ. Түүн дээр дарахад хөгжим, reminder, тохиргоо зэрэг хэрэгслүүд Dynamic Island хэлбэрээр нээгдэнэ.

**DeskBot бол JARVIS биш.** Voice assistant ч биш, chatbot ч биш. Чимээгүй, өхөөрдөм, хэрэглэгчид саад болдоггүй. AI feature бүгд унтраалттай байсан ч robot өөрөө сонирхол татахуйц байх ёстой.

## Ажиллуулах

### Бэлэн exe (хамгийн хялбар)
1. [Releases](../../releases)-ээс эсвэл build хийгээд `DeskBot.exe`-г ажиллуулна (.NET суулгах шаардлагагүй, self-contained).
2. SmartScreen "Windows protected your PC" гэвэл → **More info → Run anyway** (код sign хийгээгүй учир).
3. Robot дэлгэцийн дээд төвд гарч ирнэ. Tray icon (хар pill, 2 cyan нүд) → баруун товч → бүх тохиргоо, **Exit**.

### Source-оос
```powershell
# .NET 10 SDK шаардлагатай
dotnet build -c Release
dotnet run --project src/DeskBot.App
dotnet test                                   # 23 unit test

# Release exe (Windows x64, self-contained, нэг файл)
dotnet publish src/DeskBot.App -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish/win-x64
```

### macOS (Swift, native)
macOS 14+ (Apple Silicon), Command Line Tools хангалттай (Xcode шаардлагагүй).
```bash
cd macos
swift build && scripts/test.sh               # 108 test
scripts/bundle.sh                            # → build/DeskBot.app (ad-hoc sign)
open build/DeskBot.app
```
- Menu bar icon → тохиргоо, **Quit**. Control center: `⌃⌥Space`.
- Хөгжим: Spotify / Apple Music тоглож байхад анх удаа **Automation** зөвшөөрөл асууна (System Settings → Privacy & Security → Automation). Browser-ийн audio дэмжигдэхгүй.
- Notarize хийгээгүй тул өөр Mac руу хуулбал: баруун товч → **Open**.
- Дэлгэрэнгүй: [`macos/README.md`](macos/README.md).

## Хэрэглэх

| Үйлдэл | Үр дүн |
|---|---|
| Mouse-аа хөдөлгөх | Нүд cursor дагана. Ойртоход нүд томорч, гэрэлтэж, нэг анивчина |
| Island дээр hover | Өргөсөж цаг + now playing харуулна |
| Robot дээр click | Гайхсан reaction + control center нээгдэнэ |
| Чирэх | Байрлал солих (дэлгэц хооронд ч болно). Төв/дээд ирмэгт соронзон мэт наалдана |
| Баруун click | Pin, байрлал түгжих/reset, нуух, хаах |
| `Ctrl+Alt+Space` | Control center нээх/хаах (Settings-ээс солино) |
| `Esc` | Panel хаах |
| Хаа нэгтээ click | Robot тийшээ хальт харна |

## Robot-ийн зан төлөв (automation rules)

| Нөхцөл | Expression |
|---|---|
| Spotify / browser-т дуу тоглоход | Music (∩ нүд + ноот) |
| Reminder 5 мин дутуу | Reminder (3 сек) |
| Reminder-ийн цаг болоход | Reminder + Alert bar (Snooze/Done) |
| Battery ≤ 15%, цэнэглээгүй | LowBattery (amber) |
| 5 мин хөдөлгөөнгүй | Sleepy (zzz) |
| Fullscreen тоглоом/видео | Robot нуугдана, animation зогсоно |
| App-д алдаа гарахад | Error (4 сек) |

Priority: `Error > Reminder > NewMessage > Preview > UserClick > Battery > ActiveTask > Music > Cursor > Ambient > Mood`. Бага priority руу буухдаа 250ms hold хийж анивчилтаас сэргийлнэ.

## Feature статус (бодитоор ажилладаг эсэх)

| Feature | Статус |
|---|---|
| Transparent, click-through, always-on-top island | ✅ |
| Robot face engine — 15 expression, 7 theme, 4 eye shape | ✅ vector, static зураг байхгүй |
| Global cursor tracking (GetCursorPos), multi-monitor + per-monitor DPI | ✅ |
| Санамсаргүй анивчилт, давхар анивчилт, idle эргэн тойрноо харах | ✅ |
| Collapsed / Hover / Expanded / Pinned / Auto-hide / Alert | ✅ |
| Drag + snap, monitor сонголт, top offset | ✅ |
| Music — GSMTC (Spotify, Chrome, Edge…), art, seek, prev/next | ✅ session байхгүй бол "Nothing playing" (хуурамч дуу харуулахгүй) |
| Reminders + сарын calendar (local JSON, timezone зөв) | ✅ |
| CPU / RAM / Battery | ✅ |
| Game mode (fullscreen илрүүлэх) | ✅ |
| Global hotkey, Startup with Windows, Tray | ✅ |
| Settings persistence (atomic write, эвдэрвэл backup + default) | ✅ |
| Reduced motion, Performance mode | ✅ |
| Listening expression | ⚠️ Animation л, mic-д холбогдоогүй (mic feature нэмэгдэхэд audio-reactive болно) |
| Widgets, Clipboard, Focus, File Shelf, Apps, Quick Code, Notifications tab | ⏳ [ROADMAP](docs/ROADMAP.md) |
| Google Calendar OAuth | ⏳ ROADMAP — local reminder ажиллаж байна |
| Light mode | ⏳ |

## Privacy

- Бүх өгөгдөл local: `%AppData%\DeskBot\settings.json`, `reminders.json`. Log: `%LocalAppData%\DeskBot\logs`.
- Keyboard input **уншихгүй** (hotkey нь `RegisterHotKey` — зөвхөн тэр хослолыг Windows мэдэгдэнэ).
- Mouse hook нь зөвхөн click-ийн **байрлалыг** robot тийш харахад ашиглана; тусдаа thread дээр ажиллаж, Windows-ийн mouse-ийг хэзээ ч блоклохгүй. Settings → "Хаана ч click хийхэд тийш харах"-аар унтраана.
- Дэлгэц бичихгүй, сервер рүү юу ч илгээхгүй. Driver суулгахгүй, admin эрх шаардахгүй.

## Архитектур

```
src/
  DeskBot.Core/                 # Платформоос хамааралгүй, бүрэн test-тэй
    Expressions/                # Expression, ExpressionStateMachine, FaceLibrary, EyeMath
    Settings/AppSettings.cs     # ObservableObject → real-time preview
    Reminders/ReminderBook.cs   # Цэвэр логик
    Storage/JsonFileStore.cs    # Atomic save, corruption fallback
  DeskBot.App/                  # WPF, .NET 10, net10.0-windows10.0.19041
    Infrastructure/Windows/     # P/Invoke, Monitors, MouseHook, Hotkey, Fullscreen, Startup
    Services/                   # Media(GSMTC), SystemMonitor, Reminder, Settings, CompanionBrain, Tray
    UI/Controls/RobotFace.cs    # RobotFaceEngine — control center-оос бүрэн тусдаа
    UI/Windows/IslandWindow     # Dynamic Island
    Features/                   # ControlCenter + Home, Music, Reminders, Face, Settings
tests/DeskBot.Core.Tests/       # xUnit
```

Шинэ module нэмэх: `Features/<Name>/` дотор `IFeaturePanel` хэрэгжүүлсэн UserControl бичээд `ControlCenterView`-ийн registry-д нэг мөр нэмнэ.
