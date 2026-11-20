import Carbon.HIToolbox
import Foundation
import DeskBotCore

/// Global hotkey — Carbon `RegisterEventHotKey`. Accessibility / Input Monitoring эрх ШААРДАХГҮЙ:
/// систем зөвхөн бүртгэсэн тэр хослол дарагдсаныг мэдэгдэнэ, бусад гарын товчийг уншихгүй.
@MainActor
final class HotkeyService {
    var onPressed: (() -> Void)?
    private(set) var current: HotkeySpec?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4442_4B54 // 'DBKT'

    /// Бүртгэнэ. Амжилттай бол nil, эс бөгөөс хэрэглэгчид харуулах алдаа.
    @discardableResult
    func register(_ text: String) -> String? {
        let spec: HotkeySpec
        do { spec = try HotkeySpec.parse(text) } catch {
            return Self.message(for: error)
        }
        installHandlerIfNeeded()
        unregister()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers.carbonMask,
                                         EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Log.error("RegisterEventHotKey(\(spec.description)) failed: \(status)")
            return status == OSStatus(eventHotKeyExistsErr)
                ? "\(spec.symbols) өөр app-д бүртгэлтэй байна — өөр хослол сонгоно уу."
                : "\(spec.symbols) бүртгэж чадсангүй (OSStatus \(status))."
        }
        hotKeyRef = ref
        current = spec
        Log.info("Hotkey registered: \(spec.description)")
        return nil
    }

    func unregister() {
        if let r = hotKeyRef { UnregisterEventHotKey(r) }
        hotKeyRef = nil
        current = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, user in
            // Carbon event нь main run loop дээр ирнэ.
            guard let user else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<HotkeyService>.fromOpaque(user).takeUnretainedValue().onPressed?()
            }
            return noErr
        }, 1, &type, me, &handlerRef)
    }

    static func message(for error: Error) -> String {
        switch error as? HotkeySpec.ParseError {
        case .empty: "Хослол хоосон байна."
        case .needsModifier: "⌃ ⌥ ⇧ ⌘-ийн аль нэгийг нэмнэ үү (F-key-ээс бусад)."
        case .typesCharacter: "⌥/⇧ + товч нь тэмдэгт бичдэг (⌥Space = nbsp) — ⌃ эсвэл ⌘ нэмнэ үү."
        case .unknownModifier(let m): "Үл мэдэгдэх modifier: \(m)"
        case .unknownKey(let k): "Үл мэдэгдэх товч: \(k)"
        case nil: error.localizedDescription
        }
    }
}
