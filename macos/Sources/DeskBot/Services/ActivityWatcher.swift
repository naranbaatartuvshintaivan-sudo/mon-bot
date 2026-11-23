import AppKit
import DeskBotCore

/// Хэрэглэгчийн үйлдэлд robot хариу үзүүлэх эх үүсвэрүүд (macOS-only):
/// - Copy: `NSPasteboard.changeCount`-ийг 0.5с тутам шалгана. Агуулгыг УНШИХГҮЙ (privacy alert ч гарахгүй),
///   зөвхөн type-ийн нэрээр password manager-ийн хуулалтыг алгасна.
/// - App launch: NSWorkspace will/didLaunch — эрх шаардахгүй.
/// - Downloads: ~/Downloads folder-ийн өөрчлөлтийг (kqueue) сонсож, дуусаагүй файл байгаа эсэхийг шалгана.
///   macOS энэ folder-т хандахад нэг удаа зөвшөөрөл асууна — тиймээс Settings-ээс асаадаг.
@MainActor
final class ActivityWatcher {
    var onCopy: (() -> Void)?
    /// App нээгдэж эсвэл файл татагдаж байна уу (нийлбэр).
    var onBusyChange: ((Bool) -> Void)?

    private var copyEnabled = false
    private var launchEnabled = false
    private var downloadsEnabled = false

    private var pasteTimer: Timer?
    private var lastChangeCount = 0
    private var copyThrottle = ReactionThrottle(minInterval: 0.8)

    private var launches = PendingLaunches()
    private var launchObservers: [NSObjectProtocol] = []
    private var launchTimer: Timer?

    private var downloadsSource: DispatchSourceFileSystemObject?
    private var downloadsBusy = false
    private var lastBusy = false

    // MARK: - Configuration

    func configure(copy: Bool, appLaunch: Bool, downloads: Bool) {
        if copy != copyEnabled { copyEnabled = copy; copy ? startCopy() : stopCopy() }
        if appLaunch != launchEnabled { launchEnabled = appLaunch; appLaunch ? startLaunches() : stopLaunches() }
        if downloads != downloadsEnabled { downloadsEnabled = downloads; downloads ? startDownloads() : stopDownloads() }
        publishBusy()
    }

    // MARK: - Copy

    private func startCopy() {
        lastChangeCount = NSPasteboard.general.changeCount // асах үеийн clipboard-д хариу өгөхгүй
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPasteboard() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        pasteTimer = t
    }

    private func stopCopy() {
        pasteTimer?.invalidate()
        pasteTimer = nil
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let types = (pb.types ?? []).map(\.rawValue)
        guard ClipboardPolicy.shouldReact(types: types), copyThrottle.allow(now: .now) else { return }
        onCopy?()
    }

    // MARK: - App launch

    private func startLaunches() {
        let nc = NSWorkspace.shared.notificationCenter
        let me = ProcessInfo.processInfo.processIdentifier
        launchObservers = [
            nc.addObserver(forName: NSWorkspace.willLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
                let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    guard let self, let app, app.processIdentifier != me, app.activationPolicy == .regular else { return }
                    self.launches.begin(pid: app.processIdentifier, now: .now)
                    self.ensureLaunchTimer()
                    self.publishBusy()
                }
            },
            nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
                let pid = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard let self, let pid else { return }
                    self.launches.end(pid: pid)
                    self.publishBusy()
                }
            },
        ]
    }

    private func stopLaunches() {
        launchObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        launchObservers = []
        launchTimer?.invalidate()
        launchTimer = nil
        launches = PendingLaunches()
    }

    /// didLaunch ирэхгүй (crash, sandbox) тохиолдлын хамгаалалт — хоосон болтол 1с тутам.
    private func ensureLaunchTimer() {
        guard launchTimer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.launches.prune(now: .now) {
                    self.launchTimer?.invalidate()
                    self.launchTimer = nil
                }
                self.publishBusy()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        launchTimer = t
    }

    // MARK: - Downloads

    static var downloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    private func startDownloads() {
        let fd = open(Self.downloadsURL.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.error("Downloads watch: open failed (errno \(errno)) — permission denied?")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                            queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scanDownloads() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        downloadsSource = src
        scanDownloads()
        Log.info("Downloads watch on")
    }

    private func stopDownloads() {
        downloadsSource?.cancel()
        downloadsSource = nil
        downloadsBusy = false
    }

    private func scanDownloads() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.downloadsURL.path)) ?? []
        downloadsBusy = DownloadFiles.anyInProgress(names)
        publishBusy()
    }

    // MARK: -

    private func publishBusy() {
        let busy = (launchEnabled && !launches.isEmpty) || (downloadsEnabled && downloadsBusy)
        guard busy != lastBusy else { return }
        lastBusy = busy
        onBusyChange?(busy)
    }
}
