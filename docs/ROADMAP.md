# DeskBot Roadmap

Зарчим: **core тогтвортой байдлыг хэзээ ч эрсдэлд оруулахгүй.** Module бүр тусдаа, opt-in, асаагаагүй бол CPU/RAM огт зарцуулахгүй.

## ✅ v0.1 — Core MVP (энэ release)
Robot face engine, Dynamic Island, tray, music, reminders + calendar, face customization, settings, game mode (auto-hide), hotkey, persistence.

## v0.2 — Үлдсэн үндсэн module-ууд (priority дарааллаар)

| # | Module | Тэмдэглэл |
|---|---|---|
| 1 | **Widgets** | `IWidget` registry (Clock, Date, To-do, CPU/RAM/GPU, Battery, Network, Focus timer, Stopwatch, Countdown, Notes). Desktop-д pin хийх = тусдаа жижиг transparent window. Weather → бодит provider (Open-Meteo, key шаардлагагүй), байхгүй бол "unavailable" |
| 2 | **Clipboard** | `AddClipboardFormatListener`. **Default OFF**. Password manager-ууд (`ExcludeClipboardContentFromMonitorProcessing`, `CanIncludeInClipboardHistory` формат) автоматаар алгасна. Retention limit, exclusion list |
| 3 | **Apps + Quick actions** | Start Menu `.lnk` + `shell:AppsFolder` scan, хайлт. Hardcoded path байхгүй |
| 4 | **Focus** | Pomodoro → robot Processing/Happy |
| 5 | **File Shelf** | Drag-in/drag-out, path хуулах. Түр хадгалалт |
| 6 | **Quick Code** | Snippet manager (Claude-гүйгээр ажиллана). Claude CLI илрүүлэх, visible process, destructive command-д approval |
| 7 | **Notifications** | `UserNotificationListener` — Windows permission хүснэ → robot NewMessage |
| 8 | Light mode, theme editor | |

## v0.3 — Advanced modules (тус бүр independent, opt-in)

| Priority | Module | Аюулгүй байдлын шаардлага |
|---|---|---|
| P1 | **Game Mode+** | Одоо: fullscreen үед нуугдана ✅. Нэмэх: жижиг FPS-гүй perf strip (CPU/GPU/RAM), process whitelist |
| P1 | **Automation** | Одоо hard-coded 6 rule (`CompanionBrain`) ✅. Нэмэх: хэрэглэгчийн trigger → action editor (When *Spotify starts* → *show music panel*, When *Claude Code needs input* → *attention animation*) |
| P1 | **AI Agent Monitor** | Хэрэглэгч зөвшөөрсөн Claude Code / Codex process-ийг л харна. Working / Waiting / Completed / Needs Attention. Terminal output-ийг **permission-гүйгээр харуулахгүй** |
| P2 | **Advanced Controls** | Brightness (WMI / DDC-CI), audio output сонгох (Core Audio), mic mute. Дэмжихгүй бол "unavailable" |
| P2 | **Desktop Workspace** | Олон layout (widget байрлал, theme, robot байрлал) хадгалах/солих |
| P2 | **Web Tabs** | WebView2 drawer, pinned сайтууд, quick search |
| P3 | **Send to Phone** | **Default OFF.** Local Wi-Fi HTTP, QR + түр token (5 мин), зөвхөн нэг удаагийн transfer |
| P3 | **PC Deck** | **Default OFF.** Утаснаас trackpad/media control. Pairing QR + token, LAN-only, explicit enable |
| P3 | **Stream Mode** | Overlay, status indicator-ууд |
| P4 | **Custom Taskbar** | Original Explorer taskbar-ийг **хэрэглэгчийн зөвшөөрөлгүйгээр хэзээ ч унтраахгүй**, нэг товчоор сэргээх боломжтой |
