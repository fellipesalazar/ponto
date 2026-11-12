import AppKit
import Combine

// O motor: guarda o dia, decide quando travar e executa as ações.

enum Alarm {
    static func play(_ name: String? = nil) {
        let n = name ?? Prefs.soundName
        guard let s = NSSound(named: NSSound.Name(n)) else {
            NSSound.beep()
            return
        }
        s.stop()
        s.volume = Float(Prefs.soundVolume)
        s.play()
    }

    /// Sons do sistema disponíveis neste Mac.
    static var available: [String] {
        let dir = "/System/Library/Sounds"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let names = files
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted()
        return names.isEmpty ? ["Glass"] : names
    }
}

final class Engine: ObservableObject {
    static let shared = Engine()

    /// Segundos sem resposta até o painel "Bateu?" desistir.
    static let confirmTimeout: TimeInterval = 120
    /// O dia do app vira às 4h, pra quem passa da meia-noite trabalhando.
    static let virada: TimeInterval = 4 * 3600
    /// Tempo em que a trava ignora teclas e cliques depois de aparecer.
    static let carencia: TimeInterval = 2

    @Published var record: DayRecord {
        didSet { if record != oldValue { save() } }
    }
    @Published var now = Date()
    /// Marcação que está travando a tela agora.
    @Published var lockKind: PunchKind? = nil
    /// Marcação que está sendo cobrada só com o aviso no canto.
    @Published var noticeKind: PunchKind? = nil
    /// A marcação venceu, mas o alerta está esperando uma chamada acabar.
    @Published var waitingForCall = false
    @Published var awaitingConfirm: PunchKind? = nil
    @Published var confirmDeadline: Date? = nil
    @Published var preview: PunchKind? = nil
    /// A confirmação na tela faz parte de um teste: nada é registrado.
    @Published var previewConfirm = false
    @Published var notice: String? = nil

    private(set) var lockShownAt: Date? = nil
    private var timer: Timer?
    private var lastSound = Date.distantPast
    private var lastPrimary = Date.distantPast
    private var lastCallSeen = Date.distantPast
    private var previewAsNotice = false
    private var observers: [NSObjectProtocol] = []
    private var history: [String: DayRecord] = [:]
    private static let calendar = Calendar.current

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEEE, d/M"
        return f
    }()

    private static func logicalDayStart(_ date: Date) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-virada))
    }

    private static func dayKey(_ date: Date) -> String {
        DayKey.string(from: logicalDayStart(date))
    }

    private init() {
        let key = Engine.dayKey(Date())
        var loaded: DayRecord? = nil
        if let data = Prefs.d.data(forKey: Prefs.Key.record) {
            loaded = try? Engine.decoder.decode(DayRecord.self, from: data)
        }
        if let r = loaded, r.day == key {
            record = r
        } else {
            record = DayRecord(day: key)
        }
        notice = Prefs.d.string(forKey: Prefs.Key.notice)
        loadHistory()
        if let old = loaded, old.day != key {
            noteIfIncomplete(old)
            save()
        }
    }

    // MARK: - Relógio

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Modo .common pra continuar contando com o menu aberto.
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Mudou algum ajuste: avisa a interface na hora.
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        })
        // O Mac acordou: confere o relógio sem esperar o próximo segundo.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.tick()
        })

        tick()
    }

    func tick() {
        let n = Date()
        now = n
        rollDayIfNeeded(n)

        if let deadline = confirmDeadline, n >= deadline {
            awaitingConfirm = nil
            confirmDeadline = nil
            previewConfirm = false
        }

        var kind: PunchKind? = preview
        if kind == nil && awaitingConfirm == nil {
            kind = record.pendingKind(now: n, rules: Prefs.rules, dayStart: dayStart, isWorkday: isWorkday)
        }

        // Decide como cobrar: trava, aviso no canto ou espera.
        var asLock = false
        var asNotice = false
        var waiting = false
        var quiet = false
        if kind != nil {
            if preview != nil {
                asNotice = previewAsNotice
                asLock = !previewAsNotice
            } else if Prefs.alertStyle == "notice" {
                asNotice = true
                quiet = inCall(n)
            } else if lockKind == kind || Prefs.callMode == "lock" {
                // Já travou (ou você pediu pra travar sempre): não rebaixa.
                asLock = true
            } else if inCall(n) {
                if Prefs.callMode == "wait" {
                    waiting = true
                } else {
                    asNotice = true
                    quiet = true
                }
            } else {
                asLock = true
            }
        }

        let newLock: PunchKind? = asLock ? kind : nil
        let newNotice: PunchKind? = asNotice ? kind : nil
        let appeared = (newLock != nil && lockKind == nil) || (newNotice != nil && noticeKind == nil)

        if newLock != lockKind {
            lockShownAt = newLock != nil ? n : nil
            lockKind = newLock
        }
        if newNotice != noticeKind { noticeKind = newNotice }
        if waiting != waitingForCall { waitingForCall = waiting }

        // Som: toca quando o alerta aparece e, se você quiser, insiste.
        // Em chamada fica mudo. Só insiste se tiver alguém no Mac.
        if (newLock != nil || newNotice != nil) && !quiet {
            if appeared {
                ring(at: n)
            } else if Prefs.soundRepeat,
                      n.timeIntervalSince(lastSound) >= TimeInterval(Prefs.soundRepeatSeconds),
                      idleSeconds < 120 {
                ring(at: n)
            }
        }
    }

    /// Em chamada = microfone em uso. Espera uns segundos depois que ele
    /// desliga, pra não travar numa troca rápida de microfone.
    private func inCall(_ n: Date) -> Bool {
        if CallDetector.micInUse { lastCallSeen = n }
        return n.timeIntervalSince(lastCallSeen) < 8
    }

    private func ring(at n: Date) {
        lastSound = n
        if Prefs.soundOn { Alarm.play() }
    }

    private var idleSeconds: TimeInterval {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    // MARK: - Dia

    var dayStart: Date { Engine.logicalDayStart(now) }

    /// Hoje está na lista de folgas e feriados.
    var isScheduledOff: Bool {
        Prefs.daysOff.contains(record.day)
    }

    var isWorkday: Bool {
        if isScheduledOff { return false }
        return Prefs.workdays.contains(Engine.calendar.component(.weekday, from: dayStart))
    }

    private func rollDayIfNeeded(_ n: Date) {
        let key = Engine.dayKey(n)
        guard record.day != key else { return }
        noteIfIncomplete(record)
        awaitingConfirm = nil
        confirmDeadline = nil
        preview = nil
        previewConfirm = false
        record = DayRecord(day: key)
    }

    private func noteIfIncomplete(_ old: DayRecord) {
        guard !old.punches.isEmpty, let missing = old.nextKind else { return }
        var label = old.day
        if let date = DayKey.date(from: old.day) {
            label = Engine.dayFormatter.string(from: date)
        }
        let msg = "Faltou bater \(missing.objeto) em \(label)"
        notice = msg
        Prefs.d.set(msg, forKey: Prefs.Key.notice)
    }

    func dismissNotice() {
        notice = nil
        Prefs.d.removeObject(forKey: Prefs.Key.notice)
    }

    // MARK: - Números

    var worked: TimeInterval { record.worked(until: now) }
    var target: TimeInterval { TimeInterval(Prefs.rules.workMinutes * 60) }
    var remaining: TimeInterval { max(0, target - worked) }
    var progress: Double { target > 0 ? min(1, worked / target) : 0 }

    var due: Date? { record.dueDate(rules: Prefs.rules, dayStart: dayStart) }

    /// A próxima marcação já passou da hora (travando ou adiada).
    var isOverdue: Bool {
        if record.dayOff { return false }
        guard let kind = record.nextKind, let d = due else { return false }
        if kind == .entrada && !isWorkday { return false }
        return now >= d
    }

    var predictedExit: Date? {
        switch record.phase {
        case .antes, .encerrado:
            return nil
        case .trabalhando:
            let base = now.addingTimeInterval(remaining)
            if record.nextKind == .saidaAlmoco {
                return base.addingTimeInterval(TimeInterval(Prefs.rules.lunchDurationMinutes * 60))
            }
            return base
        case .almoco:
            guard let volta = due else { return nil }
            return max(volta, now).addingTimeInterval(remaining)
        }
    }

    var statusLine: String {
        if record.dayOff { return "Folga hoje" }
        switch record.phase {
        case .antes:
            if isScheduledOff { return "Folga marcada" }
            return isWorkday ? "Antes da entrada" : "Hoje não é dia de trabalho"
        case .trabalhando: return "Trabalhando"
        case .almoco: return "No almoço"
        case .encerrado: return "Dia encerrado"
        }
    }

    var nextLine: String {
        if record.dayOff { return "Sem lembretes hoje" }
        guard let kind = record.nextKind, let d = due else { return "Tudo batido por hoje" }
        if kind == .entrada && !isWorkday { return "Sem lembretes hoje" }
        if d <= now {
            if let s = record.snoozeUntil, s > now {
                return "\(kind.nome) adiada até \(Fmt.hora(s))"
            }
            if waitingForCall {
                return "\(kind.nome) pendente, esperando a chamada acabar"
            }
            return "\(kind.nome) pendente"
        }
        return "Próxima: \(kind.nome.lowercased()) às \(Fmt.hora(d))"
    }

    var barTitle: String {
        let seg = Prefs.barSeconds
        switch record.phase {
        case .antes:
            if record.dayOff || !isWorkday { return "" }
            return due.map { Fmt.hora($0) } ?? ""
        case .almoco:
            return Fmt.contador(record.lunchElapsed(until: now) ?? 0, segundos: seg)
        case .encerrado:
            return Fmt.contador(worked, segundos: false)
        case .trabalhando:
            switch Prefs.barMode {
            case "remaining":
                if worked >= target {
                    return "+" + Fmt.contador(worked - target, segundos: seg)
                }
                return Fmt.contador(target - worked, segundos: seg)
            case "next":
                return due.map { "→ " + Fmt.hora($0) } ?? ""
            default:
                return Fmt.contador(worked, segundos: seg)
            }
        }
    }

    var barSymbol: String {
        if isOverdue { return "bell.badge.fill" }
        if record.dayOff { return "clock" }
        switch record.phase {
        case .antes: return "clock"
        case .trabalhando: return "clock.fill"
        case .almoco: return "fork.knife"
        case .encerrado: return "checkmark.circle.fill"
        }
    }

    // MARK: - Trava

    /// A trava só aceita teclas e cliques depois de uma pequena carência,
    /// pra não registrar nada por causa de algo que você já estava digitando.
    var lockArmed: Bool {
        guard let shown = lockShownAt else { return false }
        return Date().timeIntervalSince(shown) >= Engine.carencia
    }

    func lockSubtitle(_ kind: PunchKind) -> String {
        switch kind {
        case .entrada:
            return "São \(Fmt.hora(now)). Seu dia começa agora?"
        case .saidaAlmoco:
            return "Você já trabalhou \(Fmt.duracao(worked)) hoje."
        case .voltaAlmoco:
            if let out = record.time(of: .saidaAlmoco), let e = record.lunchElapsed(until: now) {
                return "Você saiu às \(Fmt.hora(out)). Já são \(Fmt.duracao(e)) de almoço."
            }
            return "Seu almoço terminou."
        case .saida:
            return "Você fechou \(Fmt.duracao(worked)) hoje."
        }
    }

    /// Saída extra da trava: folga na entrada, dia sem almoço na hora do almoço.
    func lockExtraTitle(_ kind: PunchKind) -> String? {
        switch kind {
        case .entrada: return "Hoje não trabalho"
        case .saidaAlmoco: return "Hoje sem almoço"
        default: return nil
        }
    }

    func lockExtra() {
        if endPreview() { return }
        guard let kind = lockKind ?? noticeKind else { return }
        switch kind {
        case .entrada: setDayOff(true)
        case .saidaAlmoco: setNoLunch(true)
        default: break
        }
    }

    func testLock() {
        previewAsNotice = false
        preview = record.nextKind ?? .entrada
        tick()
    }

    func testNotice() {
        previewAsNotice = true
        preview = record.nextKind ?? .entrada
        tick()
    }

    private func endPreview() -> Bool {
        guard preview != nil else { return false }
        preview = nil
        tick()
        return true
    }

    // MARK: - Ações

    /// Abre o ponto e fica esperando você confirmar que bateu.
    func startPunch(_ kind: PunchKind? = nil) {
        if let tested = preview {
            // No teste, faz tudo igual ao de verdade, só não registra.
            preview = nil
            previewConfirm = true
            awaitingConfirm = tested
            confirmDeadline = Date().addingTimeInterval(Engine.confirmTimeout)
            openPonto()
            tick()
            return
        }
        guard let k = kind ?? record.nextKind else { return }
        awaitingConfirm = k
        confirmDeadline = Date().addingTimeInterval(Engine.confirmTimeout)
        openPonto()
        tick()
    }

    func confirmPunch() {
        guard let k = awaitingConfirm else { return }
        awaitingConfirm = nil
        confirmDeadline = nil
        if previewConfirm {
            previewConfirm = false
            tick()
            return
        }
        register(k)
    }

    func cancelConfirm() {
        awaitingConfirm = nil
        confirmDeadline = nil
        previewConfirm = false
        tick()
    }

    /// "Já bati": registra sem abrir o ponto.
    func markDone() {
        if endPreview() { return }
        guard let k = record.nextKind else { return }
        register(k)
    }

    private func register(_ kind: PunchKind) {
        var r = record
        r.punches.append(Punch(kind: kind, time: Date()))
        r.snoozeUntil = nil
        r.dayOff = false
        record = r
        if Prefs.soundOn { Alarm.play("Pop") }
        tick()
    }

    func snooze(minutes: Int) {
        if endPreview() { return }
        record.snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        tick()
    }

    /// Atalho global: confirma se estiver esperando, senão começa a bater.
    func primaryAction() {
        // Ignora disparo duplo (tecla presa, ou atalho e menu ao mesmo tempo),
        // pra não confirmar uma batida no mesmo gesto que abriu o ponto.
        let n = Date()
        guard n.timeIntervalSince(lastPrimary) >= 1 else { return }
        lastPrimary = n

        if awaitingConfirm != nil {
            confirmPunch()
        } else {
            startPunch()
        }
    }

    func setDayOff(_ on: Bool) {
        record.dayOff = on
        if on { record.snoozeUntil = nil }
        tick()
    }

    func setNoLunch(_ on: Bool) {
        record.noLunch = on
        record.snoozeUntil = nil
        tick()
    }

    func undoLast() {
        guard !record.punches.isEmpty else { return }
        record.punches.removeLast()
        record.snoozeUntil = nil
        tick()
    }

    func resetDay() {
        record = DayRecord(day: record.day)
        tick()
    }

    func setTime(at index: Int, to date: Date) {
        guard record.punches.indices.contains(index) else { return }
        record.punches[index].time = date
        tick()
    }

    /// Inclui a próxima marcação com a hora de agora, pra você acertar depois.
    func addNext() {
        guard let k = record.nextKind else { return }
        var r = record
        r.punches.append(Punch(kind: k, time: Date()))
        r.snoozeUntil = nil
        record = r
        tick()
    }

    private func openPonto() {
        let s = Prefs.pontoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        let full = s.contains("://") ? s : "https://" + s
        if let url = URL(string: full) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Arquivo

    private var historyURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Ponto", isDirectory: true).appendingPathComponent("historico.json")
    }

    private func loadHistory() {
        guard let url = historyURL, let data = try? Data(contentsOf: url) else { return }
        history = (try? Engine.decoder.decode([String: DayRecord].self, from: data)) ?? [:]
    }

    private func save() {
        if let data = try? Engine.encoder.encode(record) {
            Prefs.d.set(data, forKey: Prefs.Key.record)
        }
        guard let url = historyURL else { return }
        if record.punches.isEmpty {
            history.removeValue(forKey: record.day)
        } else {
            history[record.day] = record
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Engine.encoder.encode(history)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Ponto: não consegui salvar o histórico: \(error.localizedDescription)")
        }
    }
}
