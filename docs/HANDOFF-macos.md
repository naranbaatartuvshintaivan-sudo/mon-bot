# HANDOFF → Claude Code (Mac): DeskBot macOS native app

> Энэ файлыг бүтнээр нь уншаад ажлаа эхэл. Асуулт бага асууж, шийдвэрээ өөрөө гаргаж, assumption-уудаа тэмдэглэ.
> Хариултаа монголоор бич (техник нэр томьёо англиар). Preamble хэрэггүй, шууд барь.

---

## 1. Бүтээгдэхүүн юу вэ (ЗААВАЛ дагах)

**DeskBot (repo нэр: MON BOT) бол JARVIS БИШ.** Voice assistant, chatbot, cinematic command center биш.

Identity: **LOOI-ийн амьд, илэрхийлэлтэй robot нүүр + NotchPixel-ийн Dynamic Island + desktop utility.**
"Дэлгэц дээр амьдардаг жижиг дижитал амьтан — чиний оролцоонд хариу үйлдэл үзүүлж, компьютерийг илүү таатай болгодог."

Зарчмууд:
1. Robot нь нүд хөдөлгөх, анивчих, сэтгэл хөдлөл, cursor дагах, жижиг spontaneous animation-аар амьд мэдрэмж төрүүлнэ.
2. Default нь чимээгүй, өхөөрдөм, саад болохгүй. Ярихгүй, motivational мессеж шидэхгүй.
3. JARVIS branding / mode / holographic UI байхгүй. Giant dashboard үндсэн UI биш.
4. Dynamic Island = compact utility menu.
5. AI (Claude Code г.м.) нь optional tool — identity биш. Бүх AI унтраалттай байсан ч robot сонирхолтой байх ёстой.
6. Feature-ийн UI байгаа нь "дууссан" гэсэн үг биш — бодит функц ажиллаж байж л дууссан. Хуурамч өгөгдөл (жишээ нь тоглоогүй дуу) хэзээ ч харуулахгүй; боломжгүй бол "unavailable" гэж тодорхой харуул.

## 2. Одоогийн байдал (2026-11-18)

Repo: `github.com/naranbaatartuvshintaivan-sudo/mon-bot` (private), branch `main`.

**Windows хувилбар v0.1 — дууссан, build + 23 unit test pass, гэхдээ Windows дээр хараахан ажиллуулж туршаагүй.**
- Stack: C# / .NET 10 / WPF / CommunityToolkit.Mvvm / P/Invoke / WinRT GSMTC / JSON / xUnit
- `src/DeskBot.Core/` — платформоос хамааралгүй логик (**macOS port-ын эх сурвалж энэ**)
- `src/DeskBot.App/` — WPF app (RobotFace, IslandWindow, services, panels)
- `README.md` — feature статус, privacy; `docs/ROADMAP.md` — v0.2 болон advanced module-ууд
- Release exe: `dotnet publish` (README-д заасан)

Одоо хэрэглэгч **Mac дээр** байгаа тул **macOS native хувилбар** хийх шийдвэр гарсан. Port биш — Swift-ээр шинээр бичнэ, гэхдээ Core-ийн логик, тоон утгуудыг ЯГ хуулна (хоёр платформ дээр robot ижил зан төлөвтэй байх ёстой).

## 3. Эхлээд шалга (Phase 0)

```bash
sw_vers                      # macOS хувилбар → minimum target шийднэ
uname -m                     # arm64 гэж хүлээж байна
xcode-select -p              # Command Line Tools / Xcode байгаа эсэх
swift --version
git --version; gh --version
```
- Swift toolchain байхгүй бол: `xcode-select --install` (admin эрх хэрэгтэй байж магадгүй — энэ сургуулийн Mac байж болзошгүй; эрхгүй бол хэрэглэгчид хэл, өөр шийдэл бүү зохио).
- macOS ≥ 14 бол `@Observable` ашигла; 13 бол `ObservableObject`.
- Repo-г clone хий, `macos/` фолдерт ажилла. Windows кодыг (`src/`) бүү өөрчил.

## 4. Архитектур (macOS)

```
macos/
  Package.swift                 # SwiftPM: DeskBotCore (library) + DeskBot (executable) + DeskBotCoreTests
  Sources/DeskBotCore/          # C# Core-оос шууд порт — AppKit импортлохгүй
    Expression.swift            # Expression, ExpressionSource (priority тоо), FaceTheme, EyeShape, ExpressionRules
    ExpressionStateMachine.swift
    FaceParameters.swift        # FaceOverlay OptionSet, FaceLibrary — ТОО БҮРИЙГ C#-аас хуул
    EyeMath.swift
    AppSettings.swift           # Codable + clamp/sanitize
    ReminderBook.swift
    JSONFileStore.swift         # atomic write (write tmp → replaceItemAt), corrupt → backup + default
  Sources/DeskBot/
    App.swift                   # NSApplication, LSUIElement (Dock icon-гүй)
    Island/IslandPanel.swift    # NSPanel
    Island/IslandController.swift   # Collapsed/Hover/Alert/Expanded state
    Face/RobotFaceView.swift    # SwiftUI Canvas + TimelineView
    Services/ CursorService, MediaService, SystemMonitorService, ReminderService, CompanionBrain, HotkeyService, LoginItemService
    Features/ ControlCenter, Home, Music, Reminders, Face, Settings
    MenuBar/StatusItemController.swift
  Tests/DeskBotCoreTests/       # C# xUnit test-үүдийг бүгдийг нь порт хий (23)
  scripts/bundle.sh             # swift build -c release → DeskBot.app (Info.plist, LSUIElement=1) → codesign -s - (ad-hoc)
```

### Windows → macOS mapping

| Windows (одоо байгаа) | macOS (хийх) |
|---|---|
| WPF transparent topmost `Window` + `WS_EX_NOACTIVATE` | `NSPanel` styleMask `[.borderless, .nonactivatingPanel]`, `isOpaque=false`, `backgroundColor=.clear`, `hasShadow=false`, level `.statusBar` (menu bar-аас дээш гарах бол `.mainMenu + 1`), `collectionBehavior [.canJoinAllSpaces, .stationary, .ignoresCycle]` |
| Click-through тунгалаг хэсэг | Панелын хэмжээг island-тай тэнцүү барь + global mouse monitor-оор `ignoresMouseEvents`-ийг toggle хий (island-аас гадуур → true) |
| Дэлгэцийн дээд төв | `NSScreen.safeAreaInsets.top > 0` бол notch бий. `auxiliaryTopLeftArea/RightArea`-аас notch өргөнийг тооцоод collapsed island-ийг notch-ийг тойруулан байрлуул (нүд нь notch-ийн 2 талд эсвэл доор) |
| `GetCursorPos` 33ms timer | `NSEvent.addGlobalMonitorForEvents([.mouseMoved, .leftMouseDown, .rightMouseDown])` + local monitor. Координат: Cocoa нь доороос дээш — хөрвүүлэлтэд анхаар |
| Low-level mouse hook (click glance) | Дээрх global monitor (`.leftMouseDown`) |
| `RegisterHotKey` | Carbon `RegisterEventHotKey` (Accessibility permission шаардахгүй) — default `⌃⌥Space` |
| GSMTC media | **Анхаар:** macOS-д нийтийн now-playing API байхгүй; MediaRemote private бөгөөд macOS 15.4+ дээр 3rd-party-д хаагдсан. → Spotify болон Music.app-ийг AppleScript / ScriptingBridge-ээр (Automation permission хүснэ) уншиж, удирд. Browser media-г дэмжихгүй бол UI дээр тодорхой бич. Эхлээд одоогийн байдлыг web search-ээр verify хий. |
| CPU/RAM/Battery | `host_processor_info` (CPU delta), `host_statistics64` (RAM), IOKit `IOPSCopyPowerSourcesInfo` (battery) |
| Idle (`GetLastInputInfo`) | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null/anyInput)` |
| Fullscreen game mode | `CGWindowListCopyWindowInfo` — layer 0 цонх дэлгэцийг бүтэн хучиж байвал + `NSWorkspace.activeSpaceDidChangeNotification`. `.fullScreenAuxiliary` collectionBehavior-ийг БҮҮ нэм (fullscreen space-д харагдахгүй байх нь game mode) |
| Startup with Windows (HKCU Run) | `SMAppService.mainApp.register()` (macOS 13+) |
| Tray icon | `NSStatusItem` (2 cyan нүдтэй pill icon-ийг code-оор зур) |
| `%AppData%\DeskBot` | `~/Library/Application Support/DeskBot/` (settings.json, reminders.json), logs: `~/Library/Logs/DeskBot/` |
| Per-monitor DPI | `backingScaleFactor` — SwiftUI өөрөө зохицуулна; олон дэлгэц `NSScreen.screens` |

## 5. Robot Face Engine — хамгийн чухал (Windows-ийн `RobotFace.cs`-ийг лавлагаа болго)

SwiftUI `Canvas` + `TimelineView(.animation(paused: isHidden))`. Static зураг ХОРИОТОЙ.
- Нүд = rounded rect − дээд lid (эргэдэг тэгш өнцөгт, `LidTop`, `LidAngle`: + = дотор тал доош/уурласан, − = гадна тал доош/гунигтай; баруун нүдэнд эргэлтийг толин тусгал) − доороос эллипс (`BottomCut` → ∩ баярласан нүд). `Path` + `.subtracting()` (macOS 13+) эсвэл even-odd fill.
- Expression шилжилт: `FaceParameters.lerp` 0.24с, easeOutCubic, **шилжилтийн дундаас эхэлнэ** (үсрэлтгүй).
- Анивчилт: 0.16с, openness = 1 − sin(π·phase)·0.92; дараагийнх 2.4–6с / BlinkFrequency, 12% давхар (0.18с). Processing/Error/Listening үед анивчихгүй, Sleepy үед ×1.8 удаан.
- Харц: `LookVector(dx, dy, range 420)` easeOut; smoothing `1−exp(−7.5·dt)` (reduced motion: 14, далайц ×0.6). Cursor 8с хөдлөхгүй бол 4–12с тутам санамсаргүй тийш 1–2.2с харна (35% нь анивчина). NewMessage → (0.85,−0.6), Sleepy → (0,0.35). Click glance 0.7с.
- Notice: cursor face төвөөс < 170pt → нүд +8%, glow +30%, ирэхдээ нэг анивчина. Click pulse +22%, 2.8/с-ээр буурна. Breathing 1 + 0.022·sin(1.7t).
- Overlays: Sparkles, Ring (эргэдэг нум), Wave (4 bar), PixelX (5×5), Bubble (3 цэг), Clock, Battery, Notes ♪♫, ?, zzz, Warning ⚠.
- Theme-ийн өнгө: Classic #33E1FF, Aurora (HSV hue 190±45 / 275±35 gradient), Matrix #39FF6A + "бороо", Glitch #7CF7FF + RGB split burst 2–6с тутам, Cyberpunk #FF2E88, Minimal #F2F5F7, Custom hex. Semantic: Angry/Error #FF3B4A, LowBattery #FFB020.
- Eye shape (aspect, roundness): Rounded (0.8, 0.36), Pill (0.58, 0.5), Circle (1, 0.5), Square (0.92, 0.16).
- Glow = `.shadow(color:radius:)`, Performance mode-д унтраа.

## 6. Island behavior (Windows-тай ижил)

- Collapsed (190×34) → hover delay 120ms → Hover (360×42, цаг + now playing mini) → click → Expanded (640×420, control center). Reminder → Alert (Snooze 5м / Done).
- Mouse гарахад 700ms (Expanded: ≥900ms) дараа collapse; Pinned эсвэл TextField focus-тэй бол үгүй. Esc хаана.
- Чирж зөөх, төв/дээд ирмэгт snap, monitor сонгох, top offset, auto-hide (2.5с дараа дээш нуугдана).
- Spring animation (Windows дээр BackEase 0.22, 360ms / collapse 240ms). Reduced motion → instant.
- Control center tabs: Home, Music, Reminders, Face, Settings (`IFeaturePanel` шиг protocol — харагдах үедээ л ажиллана).

## 7. CompanionBrain rules (priority-тэй)

`Error(70) > Reminder(60) > NewMessage(50) > Preview(45) > UserClick(40) > SystemStatus(35) > ActiveTask(30) > Music(20) > Cursor(10) > Ambient(5) > BaseMood`. Доош буухад MinHold 250ms. ANGRY хэзээ ч BaseMood болохгүй.
- Media тоглож байна → Music; reminder 5 мин дутуу → Reminder 3с; цаг болсон → Reminder (Done/Snooze хүртэл); battery ≤15% & цэнэглээгүй → LowBattery; 5 мин idle → Sleepy; click → Surprised 450ms; app алдаа → Error 4с.

## 8. Privacy / аюулгүй байдал

Бүх өгөгдөл local. Keyboard уншихгүй. Дэлгэц бичихгүй. Сервер рүү юу ч илгээхгүй. Permission (Automation for Spotify/Music) зөвхөн тухайн feature-ийг асаахад хүс, юунд хэрэгтэйг тайлбарла. API key hardcode хийхгүй.

## 9. Milestone-ууд (milestone бүрийн дараа build хийгдэх ёстой, commit + push)

1. **M0** — Phase 0 шалгалт, `macos/` SwiftPM skeleton, Core порт + бүх test pass.
2. **M1** — NSPanel island дээд төвд (notch-ийг тооцсон), menu bar status item, Quit цэвэр ажиллана, settings persist.
3. **M2** — RobotFaceView: бүх expression, анивчилт, cursor tracking, click reaction, theme. (Хамгийн өндөр visual priority.)
4. **M3** — Hover/Expanded/Pin/Auto-hide/drag/multi-monitor.
5. **M4** — Home, Reminders + calendar, Face, Settings, CPU/RAM/Battery, hotkey, login item, game mode.
6. **M5** — Music (Spotify/Music.app), `scripts/bundle.sh` → `DeskBot.app`, README-д macOS хэсэг нэм.

Commit message-ийн төгсгөлд Co-Authored-By мөр нэм. `main` дээр шууд push хийх нь OK (хэрэглэгч push хийгээд явахыг хүссэн).

## 10. Definition of Done (macOS v0.1)

App асна → robot дээд төвд гарна → нүд жинхэнэ cursor-ыг дагана → өөрөө анивчина → click → animation + panel → hover томорно, гарахад жижгэрнэ → expression, theme солигдоно → чирж зөөнө → restart хийхэд settings хадгалагдана → Spotify тоглоход мэдээлэл гарна (permission өгсөн бол) → reminder жинхэнэ хадгалагдана → тунгалаг хэсэг бусад app-ийн click-ийг хаахгүй → menu bar-аас цэвэр хаагдана.
