import AppKit
import SwiftUI
import ServiceManagement

// Janela de Ajustes, no formato padrão do macOS (abas na barra de ferramentas).

enum LoginItem {
    static var isOn: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Ponto: não consegui mudar a abertura automática: \(error.localizedDescription)")
        }
    }
}

final class SettingsWindowController {
    private let engine: Engine
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    /// Avisam quando a janela abre e fecha, pro ícone aparecer e sumir do Dock.
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?

    init(engine: Engine) {
        self.engine = engine
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsRoot().environmentObject(engine))
            #if compiler(>=5.9)
            if #available(macOS 14.0, *) {
                // Deixa o SwiftUI cuidar do título e da barra da janela.
                controller.sceneBridgingOptions = [.title, .toolbars]
            }
            #endif

            let w = NSWindow(contentViewController: controller)
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.title = "Ajustes do Ponto"
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 760, height: 540))
            w.contentMinSize = NSSize(width: 680, height: 440)
            w.center()
            window = w

            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main
            ) { [weak self] _ in
                self?.onClose?()
            }
        }
        onOpen?()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Estrutura (barra lateral + conteúdo, como nos Ajustes do Sistema)

enum SettingsPane: String, CaseIterable, Identifiable {
    case jornada, folgas, hoje, alertas, geral, atalhos

    var id: SettingsPane { self }

    var title: String {
        switch self {
        case .jornada: return "Jornada"
        case .folgas: return "Folgas"
        case .hoje: return "Hoje"
        case .alertas: return "Alertas"
        case .geral: return "Geral"
        case .atalhos: return "Atalhos"
        }
    }

    var symbol: String {
        switch self {
        case .jornada: return "clock.fill"
        case .folgas: return "calendar"
        case .hoje: return "list.bullet"
        case .alertas: return "bell.fill"
        case .geral: return "gearshape.fill"
        case .atalhos: return "keyboard"
        }
    }

    var color: Color {
        switch self {
        case .jornada: return .blue
        case .folgas: return .orange
        case .hoje: return .green
        case .alertas: return .red
        case .geral: return .gray
        case .atalhos: return .purple
        }
    }
}

struct SettingsRoot: View {
    @State private var selection: SettingsPane? = .jornada

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label {
                    Text(verbatim: pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(pane.color)
                        )
                }
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail(selection ?? .jornada)
                .navigationTitle((selection ?? .jornada).title)
        }
    }

    @ViewBuilder
    private func detail(_ pane: SettingsPane) -> some View {
        switch pane {
        case .jornada: JornadaPane()
        case .folgas: FolgasPane()
        case .hoje: HojePane()
        case .alertas: AlertasPane()
        case .geral: GeralPane()
        case .atalhos: AtalhosPane()
        }
    }
}

// MARK: - Jornada

struct Weekday: Identifiable {
    let label: String
    let number: Int
    var id: Int { number }
}

struct JornadaPane: View {
    @AppStorage(Prefs.Key.entry) private var entry = 540
    @AppStorage(Prefs.Key.lunchStart) private var lunchStart = 720
    @AppStorage(Prefs.Key.lunchDuration) private var lunchDuration = 60
    @AppStorage(Prefs.Key.work) private var work = 480
    @AppStorage(Prefs.Key.workdays) private var workdays = "2,3,4,5,6"

    // Segunda a domingo, com o número de cada dia no calendário (1 = domingo).
    private let days: [Weekday] = [
        Weekday(label: "Seg", number: 2), Weekday(label: "Ter", number: 3),
        Weekday(label: "Qua", number: 4), Weekday(label: "Qui", number: 5),
        Weekday(label: "Sex", number: 6), Weekday(label: "Sáb", number: 7),
        Weekday(label: "Dom", number: 1),
    ]

    var body: some View {
        Form {
            Section {
                DatePicker("Entrada", selection: minutesBinding($entry), displayedComponents: .hourAndMinute)
                DatePicker("Almoço a partir de", selection: minutesBinding($lunchStart), displayedComponents: .hourAndMinute)
                Stepper(value: $lunchDuration, in: 15...180, step: 15) {
                    LabeledContent("Duração do almoço", value: Fmt.minutos(lunchDuration))
                }
                Stepper(value: $work, in: 60...720, step: 15) {
                    LabeledContent("Trabalho por dia", value: Fmt.minutos(work))
                }
            } header: {
                Text("Horário padrão")
            } footer: {
                Text("Com esses horários, a saída fica às \(saidaPadrao). Nos dias em que você entrar ou almoçar em outro horário, a saída acompanha.")
            }

            Section("Dias de trabalho") {
                HStack(spacing: 6) {
                    ForEach(days) { day in
                        Toggle(day.label, isOn: dayBinding(day.number))
                            .toggleStyle(.button)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var saidaPadrao: String {
        let total = entry + work + lunchDuration
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }

    private func dayBinding(_ number: Int) -> Binding<Bool> {
        Binding<Bool>(
            get: { Prefs.parseWorkdays(workdays).contains(number) },
            set: { on in
                var set = Prefs.parseWorkdays(workdays)
                if on {
                    set.insert(number)
                } else {
                    set.remove(number)
                }
                workdays = Prefs.joinWorkdays(set)
            }
        )
    }
}

// MARK: - Folgas

struct FolgasPane: View {
    @AppStorage(Prefs.Key.daysOff) private var stored = ""
    @State private var from = Date()
    @State private var to = Date()

    var body: some View {
        Form {
            Section {
                DatePicker("De", selection: $from, displayedComponents: .date)
                DatePicker("Até", selection: $to, displayedComponents: .date)
                HStack {
                    Spacer()
                    Button("Adicionar") {
                        add()
                    }
                }
            } header: {
                Text("Nova folga ou feriado")
            } footer: {
                Text("Pra um dia só, deixe as duas datas iguais. Nesses dias o Ponto não cobra a entrada. Se você trabalhar mesmo assim, é só bater pelo menu.")
            }

            Section("Folgas marcadas") {
                if upcoming.isEmpty {
                    Text("Nenhuma folga marcada.")
                        .foregroundColor(.secondary)
                }
                ForEach(upcoming, id: \.self) { key in
                    HStack {
                        Text(verbatim: DayKey.label(key))
                        Spacer()
                        Button {
                            remove(key)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// De hoje em diante, em ordem.
    private var upcoming: [String] {
        let today = DayKey.string(from: Date())
        return Prefs.parseDaysOff(stored).filter { $0 >= today }.sorted()
    }

    private func add() {
        var set = Set(upcoming) // aproveita pra descartar as que já passaram
        for key in DayKey.range(from: from, to: to) {
            set.insert(key)
        }
        stored = Prefs.joinDaysOff(set)
    }

    private func remove(_ key: String) {
        var set = Prefs.parseDaysOff(stored)
        set.remove(key)
        stored = Prefs.joinDaysOff(set)
    }
}

// MARK: - Hoje

struct HojePane: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        Form {
            Section {
                if engine.record.punches.isEmpty {
                    Text("Nenhuma marcação hoje.")
                        .foregroundColor(.secondary)
                }
                ForEach(Array(engine.record.punches.enumerated()), id: \.offset) { pair in
                    DatePicker(pair.element.kind.nome,
                               selection: timeBinding(pair.offset),
                               displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Marcações de hoje")
            } footer: {
                Text("Acerte o horário se você confirmou atrasado. A hora da volta e da saída é calculada a partir daqui.")
            }

            Section {
                HStack {
                    if let next = engine.record.nextKind {
                        Button("Incluir \(next.nome.lowercased())") {
                            engine.addNext()
                        }
                    }
                    Button("Desfazer última") {
                        engine.undoLast()
                    }
                    .disabled(engine.record.punches.isEmpty)
                    Spacer()
                    Button("Zerar o dia", role: .destructive) {
                        engine.resetDay()
                    }
                }
            }

            Section {
                Toggle("Hoje não trabalho", isOn: Binding(
                    get: { engine.record.dayOff },
                    set: { engine.setDayOff($0) }
                ))
                Toggle("Hoje sem almoço", isOn: Binding(
                    get: { engine.record.noLunch },
                    set: { engine.setNoLunch($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding<Date>(
            get: {
                let punches = engine.record.punches
                return punches.indices.contains(index) ? punches[index].time : Date()
            },
            set: { engine.setTime(at: index, to: $0) }
        )
    }
}

// MARK: - Alertas

struct AlertasPane: View {
    @EnvironmentObject var engine: Engine
    @AppStorage(Prefs.Key.alertStyle) private var alertStyle = "lock"
    @AppStorage(Prefs.Key.callMode) private var callMode = "notice"
    @AppStorage(Prefs.Key.confirmSeconds) private var confirmSeconds = 120
    @AppStorage(Prefs.Key.soundOn) private var soundOn = true
    @AppStorage(Prefs.Key.soundName) private var soundName = "Glass"
    @AppStorage(Prefs.Key.soundVolume) private var volume = 0.8
    @AppStorage(Prefs.Key.soundRepeat) private var soundRepeat = true
    @AppStorage(Prefs.Key.soundRepeatSeconds) private var repeatSeconds = 30

    private let sounds = Alarm.available

    var body: some View {
        Form {
            Section {
                Picker("Na hora da marcação", selection: $alertStyle) {
                    Text("Travar a tela").tag("lock")
                    Text("Aviso no canto da tela").tag("notice")
                }
                Picker("Durante chamadas", selection: $callMode) {
                    Text("Mostrar só o aviso no canto").tag("notice")
                    Text("Esperar a chamada acabar").tag("wait")
                    Text("Travar mesmo assim").tag("lock")
                }
                .disabled(alertStyle != "lock")
                Picker("Tempo pra confirmar que bateu", selection: $confirmSeconds) {
                    Text("30 segundos").tag(30)
                    Text("1 minuto").tag(60)
                    Text("2 minutos").tag(120)
                    Text("5 minutos").tag(300)
                    Text("10 minutos").tag(600)
                }
                HStack {
                    Button("Testar a trava") {
                        engine.testLock()
                    }
                    Button("Testar o aviso") {
                        engine.testNotice()
                    }
                }
            } footer: {
                Text("O aviso no canto não some até você responder, mas deixa você continuar usando o Mac. Depois de Bater agora, se você não confirmar dentro do tempo escolhido, o alerta volta. O Ponto entende que você está em chamada quando o microfone está em uso. Quando a chamada acaba, a trava aparece.")
            }

            Section("Som") {
                Toggle("Tocar som quando o alerta aparecer", isOn: $soundOn)

                Picker("Som", selection: $soundName) {
                    ForEach(sounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .onChange(of: soundName) { name in
                    Alarm.play(name)
                }
                .disabled(!soundOn)

                HStack {
                    Slider(value: $volume, in: 0.1...1) {
                        Text("Volume")
                    }
                    Button("Ouvir") {
                        Alarm.play()
                    }
                }
                .disabled(!soundOn)

                Toggle("Repetir enquanto você não responder", isOn: $soundRepeat)
                    .disabled(!soundOn)

                Picker("Repetir a cada", selection: $repeatSeconds) {
                    Text("15 segundos").tag(15)
                    Text("30 segundos").tag(30)
                    Text("1 minuto").tag(60)
                    Text("2 minutos").tag(120)
                }
                .disabled(!soundOn || !soundRepeat)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Geral

struct GeralPane: View {
    @AppStorage(Prefs.Key.pontoURL) private var url = ""
    @AppStorage(Prefs.Key.barMode) private var barMode = "worked"
    @AppStorage(Prefs.Key.barSeconds) private var barSeconds = false
    @AppStorage(Prefs.Key.floatingMode) private var floatingMode = "auto"
    @AppStorage(Prefs.Key.autoUpdate) private var autoUpdate = true
    @State private var loginOn = LoginItem.isOn

    var body: some View {
        Form {
            Section {
                TextField("Link do ponto", text: $url, prompt: Text("https://…"))
            } footer: {
                Text("Abre no navegador quando você escolhe Bater agora. Se ficar vazio, o Ponto só espera você confirmar.")
            }

            Section {
                Picker("Contador mostra", selection: $barMode) {
                    Text("Trabalhado hoje").tag("worked")
                    Text("Quanto falta pra sair").tag("remaining")
                    Text("Hora da próxima marcação").tag("next")
                }
                Toggle("Mostrar segundos", isOn: $barSeconds)
                Picker("Contador flutuante", selection: $floatingMode) {
                    Text("Quando o ícone não estiver visível").tag("auto")
                    Text("Sempre").tag("always")
                    Text("Nunca").tag("never")
                }
            } header: {
                Text("Barra de menus")
            } footer: {
                Text("Segure ⌘ e arraste o ícone pra direita da barra pra ele ser o último a sumir quando faltar espaço. O contador flutuante cobre o resto dos casos.")
            }

            Section {
                Toggle("Abrir o Ponto ao ligar o Mac", isOn: $loginOn)
                    .onChange(of: loginOn) { on in
                        LoginItem.set(on)
                    }
            }

            Section("Atualizações") {
                LabeledContent("Versão instalada", value: Updater.currentVersion)
                Toggle("Avisar quando tiver versão nova", isOn: $autoUpdate)
                Button("Procurar agora") {
                    Updater.shared.promptAvailable()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Atalhos

struct AtalhosPane: View {
    @AppStorage(Prefs.Key.hotkeysOn) private var hotkeysOn = true

    var body: some View {
        Form {
            Section {
                Toggle("Usar atalhos globais", isOn: $hotkeysOn)
                LabeledContent("Bater a próxima marcação, ou confirmar que bateu") {
                    ShortcutRecorder(slot: .punch)
                }
                .disabled(!hotkeysOn)
                LabeledContent("Abrir o painel do Ponto") {
                    ShortcutRecorder(slot: .menu)
                }
                .disabled(!hotkeysOn)
            } header: {
                Text("Em qualquer lugar")
            } footer: {
                Text("Pra trocar, clique no atalho e aperte a combinação nova. Ela precisa ter ⌘, ⌥ ou ⌃, senão dispararia enquanto você digita. Esc cancela.")
            }

            Section("Com a tela travada") {
                row("Bater agora", "↩")
                row("Já bati", "J")
                row("Lembrar em 5, 10, 15 ou 30 min", "1  2  3  4")
                row("Hoje não trabalho, ou hoje sem almoço", "N")
                row("Fechar o Ponto, em emergência", "⌃⌥⌘Q")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) {
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

/// Botão que mostra o atalho atual. Clicou, ele espera você apertar o novo.
struct ShortcutRecorder: View {
    let slot: HotKeyCenter.Slot

    @State private var label = ""
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if recording {
                    stop()
                } else {
                    start()
                }
            } label: {
                Text(verbatim: recording ? "Aperte o atalho…" : label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 110)
            }

            Button {
                save(slot == .punch ? HotKey.punchDefault : HotKey.menuDefault)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .onAppear {
            label = current.label
        }
        .onDisappear {
            stop()
        }
    }

    private var current: HotKey {
        slot == .punch ? Prefs.hotkeyPunch : Prefs.hotkeyMenu
    }

    private func start() {
        recording = true
        // Solta os atalhos atuais pra eles não dispararem durante a gravação.
        HotKeyCenter.shared.suspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            if let key = HotKey.from(event) {
                save(key)
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        if recording {
            recording = false
            HotKeyCenter.shared.suspended = false
        }
    }

    private func save(_ key: HotKey) {
        if slot == .punch {
            Prefs.hotkeyPunch = key
        } else {
            Prefs.hotkeyMenu = key
        }
        label = key.label
    }
}
