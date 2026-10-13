import Carbon.HIToolbox
import Foundation

/// Global kısayollar (Carbon RegisterEventHotKey — Erişilebilirlik izni gerektirmez).
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    func register(keyCode: Int, modifiers: Int, handler: @escaping @MainActor () -> Void) {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x454C_5641), id: id) // 'ELVA'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            handlers[id] = handler
            refs.append(ref)
        } else {
            NSLog("Elva: kısayol kaydedilemedi (keyCode \(keyCode), status \(status))")
        }
    }

    fileprivate func fire(_ id: UInt32) {
        guard let handler = handlers[id] else { return }
        Task { @MainActor in handler() }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if status == noErr {
                HotKeyManager.shared.fire(hotKeyID.id)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
