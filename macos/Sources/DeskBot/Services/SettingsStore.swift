import Foundation
import Observation
import DeskBotCore

/// settings.json-ийг ачаалж, `@Observable` өөрчлөлт бүрд 500ms debounce-тэй atomic хадгална.
@MainActor
final class SettingsStore {
    static let directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DeskBot", isDirectory: true)

    let url: URL
    let settings: AppSettings
    private var pendingSave: Task<Void, Never>?
    private var dirty = false

    init(url: URL = SettingsStore.directory.appendingPathComponent("settings.json")) {
        self.url = url
        settings = JSONFileStore.loadOrDefault(url) { AppSettings() }.sanitize()
        observe()
    }

    /// Бүх property-г encode хийж уншина → аль нэг нь өөрчлөгдөхөд onChange дуудагдана.
    private func observe() {
        withObservationTracking {
            _ = try? JSONFileStore.makeEncoder().encode(settings)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleSave()
                self.observe() // withObservationTracking нэг удаагийн — дахин бүртгэнэ
            }
        }
    }

    private func scheduleSave() {
        dirty = true
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Хүлээгдэж буй өөрчлөлтийг шууд бичнэ (Quit үед).
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard dirty else { return }
        do {
            try JSONFileStore.saveAtomic(url, settings)
            dirty = false
        } catch {
            Log.error("Settings save failed: \(error)")
        }
    }
}
