import AppKit
import Carbon.HIToolbox

// Atalhos globais (funcionam com qualquer app na frente).
// Todos usam ⌃⌥⌘ + uma letra e não pedem permissão de acessibilidade.

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Entry {
        let keyCode: UInt32
        let handler: () -> Void
    }

    private static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    private static let signature = OSType(0x504E_544F) // "PNTO"

    private var entries: [UInt32: Entry] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    private var nextID: UInt32 = 1
    private(set) var enabled = false

    private init() {}

    func add(keyCode: Int, handler: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        entries[id] = Entry(keyCode: UInt32(keyCode), handler: handler)
        if enabled { register(id) }
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            installHandler()
            for id in entries.keys { register(id) }
        } else {
            for ref in refs.values { UnregisterEventHotKey(ref) }
            refs.removeAll()
        }
    }

    private func register(_ id: UInt32) {
        guard let entry = entries[id], refs[id] == nil else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotKeyCenter.signature, id: id)
        let status = RegisterEventHotKey(entry.keyCode, HotKeyCenter.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let r = ref {
            refs[id] = r
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        _ = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            if status == noErr {
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    HotKeyCenter.shared.fire(id)
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func fire(_ id: UInt32) {
        entries[id]?.handler()
    }
}
