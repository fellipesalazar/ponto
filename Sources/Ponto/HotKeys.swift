import AppKit
import Carbon.HIToolbox

// Atalhos globais (funcionam com qualquer app na frente).
// Você escolhe as teclas em Ajustes > Atalhos. Não pedem permissão de acessibilidade.

/// Um atalho: a tecla, os modificadores e como ele aparece escrito.
struct HotKey: Equatable {
    var keyCode: Int
    /// Modificadores no formato do sistema de atalhos (⌘, ⌥, ⌃, ⇧ somados).
    var modifiers: Int
    /// Como aparece na tela, por exemplo "⌃⌥P".
    var label: String
    /// A letra, pra mostrar o atalho ao lado do item no menu. Vazio se não for letra.
    var char: String

    static let punchDefault = HotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey, label: "⌃⌥P", char: "p")
    static let menuDefault = HotKey(keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey, label: "⌃⌥M", char: "m")

    /// Modificadores no formato que os menus usam.
    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        return flags
    }

    /// Monta um atalho a partir de uma tecla apertada. Devolve nil se não servir:
    /// precisa ter ⌘, ⌥ ou ⌃, senão ele dispararia enquanto você digita.
    static func from(_ event: NSEvent) -> HotKey? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
            return nil
        }

        var mods = 0
        var symbols = ""
        if flags.contains(.control) { mods |= controlKey; symbols += "⌃" }
        if flags.contains(.option) { mods |= optionKey; symbols += "⌥" }
        if flags.contains(.shift) { mods |= shiftKey; symbols += "⇧" }
        if flags.contains(.command) { mods |= cmdKey; symbols += "⌘" }

        let code = Int(event.keyCode)
        var name = ""
        var char = ""
        if let special = specialKeys[code] {
            name = special
        } else {
            let typed = (event.charactersIgnoringModifiers ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard typed.count == 1, let scalar = typed.unicodeScalars.first, scalar.value > 32, scalar.value < 0xF700 else {
                return nil
            }
            name = typed.uppercased()
            char = typed.lowercased()
        }
        return HotKey(keyCode: code, modifiers: mods, label: symbols + name, char: char)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Espaço", kVK_Return: "↩", kVK_Tab: "⇥",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    enum Slot: UInt32 {
        case punch = 1
        case menu = 2
    }

    private static let signature = OSType(0x504E_544F) // "PNTO"

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var registered: [UInt32: HotKey] = [:]
    private var wanted: [UInt32: HotKey] = [:]
    private var handlerInstalled = false

    /// Desliga os atalhos por um instante, enquanto você grava um novo.
    var suspended = false {
        didSet { apply() }
    }

    private init() {}

    func setHandler(_ slot: Slot, _ handler: @escaping () -> Void) {
        handlers[slot.rawValue] = handler
    }

    /// Diz quais atalhos devem valer agora. Só mexe se algo mudou.
    func configure(enabled: Bool, punch: HotKey, menu: HotKey) {
        wanted = enabled ? [Slot.punch.rawValue: punch, Slot.menu.rawValue: menu] : [:]
        apply()
    }

    private func apply() {
        let target = suspended ? [:] : wanted
        guard target != registered else { return }

        for ref in refs.values {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        registered = target

        guard !target.isEmpty else { return }
        installHandler()
        for (id, key) in target {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: HotKeyCenter.signature, id: id)
            let status = RegisterEventHotKey(UInt32(key.keyCode), UInt32(key.modifiers), hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let r = ref {
                refs[id] = r
            }
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
        handlers[id]?()
    }
}

// MARK: - Onde os atalhos ficam guardados

extension Prefs {
    static var hotkeyPunch: HotKey {
        get { readHotKey("hkPunch", HotKey.punchDefault) }
        set { writeHotKey("hkPunch", newValue) }
    }

    static var hotkeyMenu: HotKey {
        get { readHotKey("hkMenu", HotKey.menuDefault) }
        set { writeHotKey("hkMenu", newValue) }
    }

    /// Texto do atalho de bater, pra mostrar nos botões. Vazio se os atalhos estiverem desligados.
    static var punchKeyLabel: String {
        hotkeysOn ? hotkeyPunch.label : ""
    }

    private static func readHotKey(_ prefix: String, _ fallback: HotKey) -> HotKey {
        guard d.object(forKey: prefix + "Code") != nil,
              let label = d.string(forKey: prefix + "Label"), !label.isEmpty else {
            return fallback
        }
        return HotKey(keyCode: d.integer(forKey: prefix + "Code"),
                      modifiers: d.integer(forKey: prefix + "Mods"),
                      label: label,
                      char: d.string(forKey: prefix + "Char") ?? "")
    }

    private static func writeHotKey(_ prefix: String, _ key: HotKey) {
        d.set(key.keyCode, forKey: prefix + "Code")
        d.set(key.modifiers, forKey: prefix + "Mods")
        d.set(key.label, forKey: prefix + "Label")
        d.set(key.char, forKey: prefix + "Char")
    }
}
