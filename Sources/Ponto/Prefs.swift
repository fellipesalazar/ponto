import Foundation

// Ajustes guardados no UserDefaults. As telas de ajustes escrevem direto
// nessas chaves e o motor lê a cada segundo, então tudo vale na hora.

enum Prefs {
    enum Key {
        static let entry = "entryMinutes"
        static let lunchStart = "lunchStartMinutes"
        static let lunchDuration = "lunchDurationMinutes"
        static let work = "workMinutes"
        static let workdays = "workdays"
        static let lunchEnabled = "lunchEnabled"
        static let lunchAdjustsExit = "lunchAdjustsExit"
        static let daysOff = "daysOff"

        static let alertStyle = "alertStyle"
        static let confirmSeconds = "confirmSeconds"
        static let callMode = "callMode"

        static let soundOn = "soundOn"
        static let soundName = "soundName"
        static let soundFile = "soundFile"
        static let soundFileLabel = "soundFileLabel"
        static let soundVolume = "soundVolume"
        static let soundRepeat = "soundRepeat"
        static let soundRepeatSeconds = "soundRepeatSeconds"

        static let pontoURL = "pontoURL"
        static let barMode = "barMode"
        static let barSeconds = "barSeconds"
        static let floatingMode = "floatingMode"
        static let hotkeysOn = "hotkeysOn"
        static let autoUpdate = "autoUpdate"
        static let updatePromptedAt = "updatePromptedAt"
        static let updatePromptedVersion = "updatePromptedVersion"

        static let firstRunDone = "firstRunDone"
        static let record = "record"
        static let notice = "notice"
        static let floatingX = "floatingX"
        static let floatingY = "floatingY"
    }

    static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            Key.entry: 9 * 60,
            Key.lunchStart: 12 * 60,
            Key.lunchDuration: 60,
            Key.work: 8 * 60,
            Key.workdays: "2,3,4,5,6",
            Key.lunchEnabled: true,
            Key.lunchAdjustsExit: true,
            Key.daysOff: "",
            Key.alertStyle: "lock",
            Key.confirmSeconds: 120,
            Key.callMode: "notice",
            Key.soundOn: true,
            Key.soundName: "Glass",
            Key.soundVolume: 0.8,
            Key.soundRepeat: true,
            Key.soundRepeatSeconds: 30,
            Key.pontoURL: "",
            Key.barMode: "worked",
            Key.barSeconds: false,
            Key.floatingMode: "auto",
            Key.hotkeysOn: true,
            Key.autoUpdate: true,
        ])
    }

    static var rules: Rules {
        Rules(
            entryMinutes: d.integer(forKey: Key.entry),
            lunchStartMinutes: d.integer(forKey: Key.lunchStart),
            lunchDurationMinutes: d.integer(forKey: Key.lunchDuration),
            workMinutes: d.integer(forKey: Key.work),
            lunchAdjustsExit: d.bool(forKey: Key.lunchAdjustsExit)
        )
    }

    /// Dias de trabalho no padrão do calendário: 1 = domingo ... 7 = sábado.
    static func parseWorkdays(_ s: String) -> Set<Int> {
        Set(s.split(separator: ",").compactMap { Int($0) })
    }

    static func joinWorkdays(_ set: Set<Int>) -> String {
        set.sorted().map { String($0) }.joined(separator: ",")
    }

    static var workdays: Set<Int> {
        parseWorkdays(d.string(forKey: Key.workdays) ?? "")
    }

    /// A jornada tem intervalo de almoço.
    static var lunchEnabled: Bool { d.bool(forKey: Key.lunchEnabled) }

    /// Folgas e feriados marcados, como "2026-11-20".
    static func parseDaysOff(_ s: String) -> Set<String> {
        Set(s.split(separator: ",").map { String($0) })
    }

    static func joinDaysOff(_ set: Set<String>) -> String {
        set.sorted().joined(separator: ",")
    }

    static var daysOff: Set<String> {
        parseDaysOff(d.string(forKey: Key.daysOff) ?? "")
    }

    /// "lock" trava a tela, "notice" mostra só o aviso no canto.
    static var alertStyle: String { d.string(forKey: Key.alertStyle) ?? "lock" }
    /// Em chamada: "notice" mostra o aviso, "wait" espera, "lock" trava mesmo assim.
    static var callMode: String { d.string(forKey: Key.callMode) ?? "notice" }

    /// Quanto tempo o "Bateu?" espera antes de o alerta voltar.
    static var confirmSeconds: Int { max(15, d.integer(forKey: Key.confirmSeconds)) }

    static var soundOn: Bool { d.bool(forKey: Key.soundOn) }
    static var soundName: String { d.string(forKey: Key.soundName) ?? "Glass" }
    static var soundVolume: Double { d.double(forKey: Key.soundVolume) }
    static var soundRepeat: Bool { d.bool(forKey: Key.soundRepeat) }
    static var soundRepeatSeconds: Int { max(5, d.integer(forKey: Key.soundRepeatSeconds)) }

    static var pontoURL: String { d.string(forKey: Key.pontoURL) ?? "" }
    static var barMode: String { d.string(forKey: Key.barMode) ?? "worked" }
    static var barSeconds: Bool { d.bool(forKey: Key.barSeconds) }
    static var floatingMode: String { d.string(forKey: Key.floatingMode) ?? "auto" }
    static var hotkeysOn: Bool { d.bool(forKey: Key.hotkeysOn) }
    static var autoUpdate: Bool { d.bool(forKey: Key.autoUpdate) }
}
