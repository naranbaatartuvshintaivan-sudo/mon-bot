import Foundation
import ServiceManagement

/// "Login үед асах" — SMAppService.mainApp (macOS 13+). Зөвхөн bundle хийсэн DeskBot.app-аас ажиллана
/// (`swift run`-ийн unbundled binary-д боломжгүй — UI дээр тодорхой бичнэ).
@MainActor
enum LoginItemService {
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Хэрэглэгчид харуулах төлөв.
    static var statusText: String {
        guard isBundled else { return "Unavailable — DeskBot.app (scripts/bundle.sh)-аас ажиллуулна уу" }
        switch SMAppService.mainApp.status {
        case .enabled: return "Enabled"
        case .notRegistered: return "Off"
        case .requiresApproval: return "System Settings → General → Login Items дээр зөвшөөрөл хүлээж байна"
        case .notFound: return "Unavailable — app бүртгэгдээгүй"
        @unknown default: return "Unknown"
        }
    }

    static var isEnabled: Bool { isBundled && SMAppService.mainApp.status == .enabled }

    /// Амжилттай бол nil, эс бөгөөс алдааны мессеж.
    static func set(_ on: Bool) -> String? {
        guard isBundled else { return statusText }
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            Log.error("SMAppService \(on ? "register" : "unregister") failed: \(error)")
            return error.localizedDescription
        }
    }
}
