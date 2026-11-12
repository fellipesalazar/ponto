import Foundation

// Regras da jornada. Só lógica, sem interface.

enum PunchKind: String, Codable, CaseIterable {
    case entrada, saidaAlmoco, voltaAlmoco, saida

    var nome: String {
        switch self {
        case .entrada: return "Entrada"
        case .saidaAlmoco: return "Saída pro almoço"
        case .voltaAlmoco: return "Volta do almoço"
        case .saida: return "Saída"
        }
    }

    var nomeCurto: String {
        switch self {
        case .entrada: return "Entrada"
        case .saidaAlmoco: return "Almoço"
        case .voltaAlmoco: return "Volta"
        case .saida: return "Saída"
        }
    }

    /// Como aparece em "Bater ___".
    var objeto: String {
        switch self {
        case .entrada: return "a entrada"
        case .saidaAlmoco: return "a saída pro almoço"
        case .voltaAlmoco: return "a volta do almoço"
        case .saida: return "a saída"
        }
    }

    var chamada: String {
        switch self {
        case .entrada: return "Hora de bater a entrada"
        case .saidaAlmoco: return "Hora do almoço"
        case .voltaAlmoco: return "Hora de voltar do almoço"
        case .saida: return "Hora de encerrar o dia"
        }
    }

    var simbolo: String {
        switch self {
        case .entrada: return "sunrise.fill"
        case .saidaAlmoco: return "fork.knife"
        case .voltaAlmoco: return "arrow.uturn.backward.circle.fill"
        case .saida: return "moon.stars.fill"
        }
    }
}

struct Punch: Codable, Equatable {
    var kind: PunchKind
    var time: Date
}

enum Phase {
    case antes, trabalhando, almoco, encerrado
}

struct Rules {
    var entryMinutes: Int
    var lunchStartMinutes: Int
    var lunchDurationMinutes: Int
    var workMinutes: Int
    /// Ligado: almoço mais longo ou mais curto muda a hora da saída.
    /// Desligado: a saída é sempre entrada + jornada + almoço padrão.
    var lunchAdjustsExit: Bool = true
}

struct DayRecord: Codable, Equatable {
    var day: String
    var punches: [Punch] = []
    var snoozeUntil: Date? = nil
    var dayOff: Bool = false
    var noLunch: Bool = false
    /// O "sem almoço" veio do ajuste da jornada, não de uma escolha só de hoje.
    var noLunchAuto: Bool? = nil

    func time(of kind: PunchKind) -> Date? {
        punches.first(where: { $0.kind == kind })?.time
    }

    var phase: Phase {
        guard let last = punches.last else { return .antes }
        switch last.kind {
        case .entrada, .voltaAlmoco: return .trabalhando
        case .saidaAlmoco: return .almoco
        case .saida: return .encerrado
        }
    }

    /// Próxima marcação esperada.
    var nextKind: PunchKind? {
        guard let last = punches.last else { return .entrada }
        switch last.kind {
        case .entrada: return noLunch ? .saida : .saidaAlmoco
        case .saidaAlmoco: return .voltaAlmoco
        case .voltaAlmoco: return .saida
        case .saida: return nil
        }
    }

    /// Tempo trabalhado até `now`, somando os períodos entre as marcações.
    func worked(until now: Date) -> TimeInterval {
        var total: TimeInterval = 0
        var start: Date? = nil
        for p in punches {
            switch p.kind {
            case .entrada, .voltaAlmoco:
                start = p.time
            case .saidaAlmoco, .saida:
                if let s = start { total += max(0, p.time.timeIntervalSince(s)) }
                start = nil
            }
        }
        if let s = start { total += max(0, now.timeIntervalSince(s)) }
        return total
    }

    func lunchElapsed(until now: Date) -> TimeInterval? {
        guard let out = time(of: .saidaAlmoco) else { return nil }
        let end = time(of: .voltaAlmoco) ?? now
        return max(0, end.timeIntervalSince(out))
    }

    /// Hora em que a próxima marcação passa a ser cobrada.
    func dueDate(rules: Rules, dayStart: Date) -> Date? {
        guard let kind = nextKind else { return nil }
        switch kind {
        case .entrada:
            return dayStart.addingTimeInterval(TimeInterval(rules.entryMinutes * 60))
        case .saidaAlmoco:
            guard let e = time(of: .entrada) else { return nil }
            let janela = dayStart.addingTimeInterval(TimeInterval(rules.lunchStartMinutes * 60))
            // Quem entrou tarde não é cobrado do almoço logo em seguida.
            return max(janela, e.addingTimeInterval(3600))
        case .voltaAlmoco:
            guard let s = time(of: .saidaAlmoco) else { return nil }
            return s.addingTimeInterval(TimeInterval(rules.lunchDurationMinutes * 60))
        case .saida:
            if !rules.lunchAdjustsExit, let e = time(of: .entrada), time(of: .saidaAlmoco) != nil {
                // Saída fixa: não importa quanto o almoço durou de verdade.
                return e.addingTimeInterval(TimeInterval((rules.workMinutes + rules.lunchDurationMinutes) * 60))
            }
            guard let inicio = punches.last?.time else { return nil }
            let feito = worked(until: inicio)
            let falta = max(0, TimeInterval(rules.workMinutes * 60) - feito)
            return inicio.addingTimeInterval(falta)
        }
    }

    /// Marcação que deve travar a tela agora, se houver.
    func pendingKind(now: Date, rules: Rules, dayStart: Date, isWorkday: Bool) -> PunchKind? {
        if dayOff { return nil }
        guard let kind = nextKind, let due = dueDate(rules: rules, dayStart: dayStart) else { return nil }
        if kind == .entrada && !isWorkday { return nil }
        if now < due { return nil }
        if let s = snoozeUntil, now < s { return nil }
        return kind
    }
}

// MARK: - Texto

enum Fmt {
    /// "3h02"
    static func duracao(_ s: TimeInterval) -> String {
        let total = max(0, Int(s)) / 60
        return "\(total / 60)h" + String(format: "%02d", total % 60)
    }

    /// "8h00" a partir de minutos.
    static func minutos(_ m: Int) -> String {
        duracao(TimeInterval(m * 60))
    }

    /// "3:02" ou "3:02:15"
    static func contador(_ s: TimeInterval, segundos: Bool) -> String {
        let t = max(0, Int(s))
        let h = t / 3600
        let m = (t % 3600) / 60
        if segundos {
            return "\(h):" + String(format: "%02d:%02d", m, t % 60)
        }
        return "\(h):" + String(format: "%02d", m)
    }

    /// "1:42" (minutos e segundos)
    static func regressiva(_ s: TimeInterval) -> String {
        let t = max(0, Int(s.rounded(.up)))
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    private static let relogio: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "12:40"
    static func hora(_ d: Date) -> String {
        relogio.string(from: d)
    }
}

// MARK: - Datas

/// Dias guardados como "2026-11-20".
enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEEE, d 'de' MMMM"
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }

    /// "sexta-feira, 20 de novembro"
    static func label(_ key: String) -> String {
        guard let d = date(from: key) else { return key }
        return labelFormatter.string(from: d)
    }

    /// Todos os dias entre duas datas, incluindo as duas.
    static func range(from start: Date, to end: Date, limit: Int = 90) -> [String] {
        let cal = Calendar.current
        var day = cal.startOfDay(for: min(start, end))
        let last = cal.startOfDay(for: max(start, end))
        var keys: [String] = []
        while day <= last && keys.count < limit {
            keys.append(string(from: day))
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return keys
    }
}

// MARK: - Versões

enum Versao {
    /// Compara "1.2" com "1.10". Devolve -1, 0 ou 1.
    static func compare(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l < r { return -1 }
            if l > r { return 1 }
        }
        return 0
    }
}
