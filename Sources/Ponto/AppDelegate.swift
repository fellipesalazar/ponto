import AppKit
import Combine
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = Engine.shared
    private var statusBar: StatusBarController!
    private var lock: LockController!
    private var confirm: ConfirmPanelController!
    private var noticePanel: NoticePanelController!
    private var floating: FloatingCounterController!
    private var settings: SettingsWindowController!
    private var bag = Set<AnyCancellable>()
    private var syncPending = false
    private var hiddenSince: Date? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        statusBar = StatusBarController(engine: engine)
        lock = LockController(engine: engine)
        confirm = ConfirmPanelController(engine: engine)
        noticePanel = NoticePanelController(engine: engine)
        floating = FloatingCounterController(engine: engine)
        settings = SettingsWindowController(engine: engine)
        statusBar.onOpenSettings = { [weak self] in
            self?.settings.show()
        }

        // Com os Ajustes abertos o Ponto aparece no Dock; fechou, some de novo.
        settings.onOpen = {
            NSApp.setActivationPolicy(.regular)
        }
        settings.onClose = {
            NSApp.setActivationPolicy(.accessory)
        }

        // Atalhos globais: um bate ou confirma, o outro abre o painel.
        HotKeyCenter.shared.setHandler(.punch) { [weak self] in
            self?.engine.primaryAction()
        }
        HotKeyCenter.shared.setHandler(.menu) { [weak self] in
            self?.statusBar.openMenu()
        }

        engine.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleSync()
            }
            .store(in: &bag)

        firstRunIfNeeded()
        engine.start()
        sync()

        // Atualizações: só pergunta quando não atrapalha.
        let engine = self.engine
        Updater.shared.canInterrupt = {
            engine.lockKind == nil && engine.noticeKind == nil
                && engine.awaitingConfirm == nil && !CallDetector.micInUse
        }
        Updater.shared.onChange = { [weak self] in
            self?.scheduleSync()
        }
        Updater.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clique no ícone do Dock: traz os Ajustes pra frente.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }

    // MARK: - Menu do Dock (botão direito no ícone)

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let record = engine.record

        let status = NSMenuItem(title: engine.statusLine + " · " + Fmt.duracao(engine.worked) + " hoje",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if let waiting = engine.awaitingConfirm {
            addDockItem(menu, "Confirmar: bati \(waiting.objeto)", #selector(dockPrimary))
            addDockItem(menu, "Ainda não bati", #selector(dockCancelConfirm))
        } else if let next = record.nextKind {
            addDockItem(menu, "Bater \(next.objeto)", #selector(dockPrimary))
            addDockItem(menu, "Já bati \(next.objeto)", #selector(dockMarkDone))
            if next == .saidaAlmoco {
                addDockItem(menu, "Encerrar o dia agora", #selector(dockEndDay))
            }
        }

        menu.addItem(.separator())

        if Prefs.lunchEnabled && record.time(of: .saidaAlmoco) == nil && record.phase != .encerrado {
            let lunch = addDockItem(menu, "Hoje sem almoço", #selector(dockToggleNoLunch))
            lunch.state = record.noLunch ? .on : .off
        }
        if record.punches.isEmpty {
            let off = addDockItem(menu, "Hoje não trabalho", #selector(dockToggleDayOff))
            off.state = record.dayOff ? .on : .off
        } else {
            addDockItem(menu, "Desfazer última marcação", #selector(dockUndoLast))
        }

        return menu
    }

    @discardableResult
    private func addDockItem(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func dockPrimary() { engine.primaryAction() }
    @objc private func dockMarkDone() { engine.markDone() }
    @objc private func dockCancelConfirm() { engine.cancelConfirm() }
    @objc private func dockEndDay() { engine.startPunch(.saida) }
    @objc private func dockToggleNoLunch() { engine.setNoLunch(!engine.record.noLunch) }
    @objc private func dockToggleDayOff() { engine.setDayOff(!engine.record.dayOff) }
    @objc private func dockUndoLast() { engine.undoLast() }

    // MARK: - Sincronia entre o motor e as janelas

    private func scheduleSync() {
        guard !syncPending else { return }
        syncPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.syncPending = false
            self.sync()
        }
    }

    private func sync() {
        HotKeyCenter.shared.configure(enabled: Prefs.hotkeysOn, punch: Prefs.hotkeyPunch, menu: Prefs.hotkeyMenu)
        statusBar.refresh()

        let wantLock = engine.lockKind != nil
        if wantLock && !lock.isShown {
            confirm.hide()
            lock.show()
        } else if !wantLock && lock.isShown {
            // Se o navegador está abrindo o ponto, deixa ele vir pra frente.
            let link = Prefs.pontoURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let openingPonto = engine.awaitingConfirm != nil && !link.isEmpty
            lock.hide(restoreFocus: !openingPonto)
        }
        lock.enforce()

        let wantConfirm = engine.awaitingConfirm != nil && !wantLock
        if wantConfirm && !confirm.isShown {
            confirm.show()
        } else if !wantConfirm && confirm.isShown {
            confirm.hide()
        }

        // Aviso no canto: a versão discreta do alerta.
        if let kind = engine.noticeKind, !wantLock {
            if noticePanel.shownKind != kind {
                noticePanel.show(kind)
            }
        } else if noticePanel.isShown {
            noticePanel.hide()
        }

        floating.setVisible(shouldShowFloating(locked: wantLock || noticePanel.isShown))
    }

    private func shouldShowFloating(locked: Bool) -> Bool {
        if locked {
            hiddenSince = nil
            return false
        }
        switch Prefs.floatingMode {
        case "always":
            return true
        case "never":
            return false
        default:
            if statusBar.isVisibleOnScreen {
                hiddenSince = nil
                return false
            }
            // Espera uns segundos antes de aparecer, pra não piscar em transições.
            let since = hiddenSince ?? Date()
            hiddenSince = since
            return Date().timeIntervalSince(since) >= 3
        }
    }

    private func firstRunIfNeeded() {
        guard !Prefs.d.bool(forKey: Prefs.Key.firstRunDone) else { return }
        Prefs.d.set(true, forKey: Prefs.Key.firstRunDone)
        LoginItem.set(true)
        // Instalou depois da hora da entrada: hoje começa em folga, pra não travar de cara.
        if engine.record.punches.isEmpty, let due = engine.due, Date() >= due {
            engine.setDayOff(true)
        }
        settings.show()
    }

    // MARK: - Menu principal

    // O app não aparece no Dock, mas precisa de um menu pra ⌘C, ⌘V, ⌘W e ⌘Q
    // funcionarem na janela de Ajustes.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = appMenu.addItem(withTitle: "Ajustes…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sair do Ponto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Editar")
        edit.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Refazer", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Selecionar Tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Janela")
        windowMenu.addItem(withTitle: "Fechar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    @objc private func showSettings() {
        settings.show()
    }
}
