import AppKit
import SwiftUI

// O contador na barra de menus e o menu que abre a partir dele.

final class StatusBarController: NSObject, NSMenuDelegate {
    private let engine: Engine
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var lastSymbol = ""
    private var lastTitle: String? = nil

    var onOpenSettings: (() -> Void)?

    init(engine: Engine) {
        self.engine = engine
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // Guarda a posição que você escolher (⌘ + arrastar) e não deixa remover da barra.
        item.autosaveName = "PontoStatusItem"
        item.behavior = []
        item.isVisible = true

        if let button = item.button {
            let size = NSFont.menuBarFont(ofSize: 0).pointSize
            button.font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        }

        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        refresh()
    }

    func refresh() {
        guard let button = item.button else { return }

        let symbol = engine.barSymbol
        if symbol != lastSymbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Ponto")
            image?.isTemplate = true
            button.image = image
            lastSymbol = symbol
        }

        let title = engine.barTitle
        if title != lastTitle {
            button.title = title
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            lastTitle = title
        }
    }

    func openMenu() {
        item.button?.performClick(nil)
    }

    /// O ícone está mesmo aparecendo na barra? (Pode ser escondido pelo recorte
    /// da tela, por falta de espaço ou por um app em tela cheia.)
    var isVisibleOnScreen: Bool {
        guard let window = item.button?.window else { return false }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem()
        let host = NSHostingView(rootView: MenuHeader().environmentObject(engine))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: max(60, host.fittingSize.height))
        header.view = host
        menu.addItem(header)
        menu.addItem(.separator())

        if let notice = engine.notice {
            let n = add(notice, #selector(dismissNotice))
            n.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            n.toolTip = "Clique pra dispensar o aviso"
            menu.addItem(.separator())
        }

        let record = engine.record

        if let waiting = engine.awaitingConfirm {
            let c = add("Confirmar: bati \(waiting.objeto)", #selector(primary))
            showShortcut(on: c)
            add("Ainda não bati", #selector(cancelConfirm))
        } else if let next = record.nextKind {
            let b = add("Bater \(next.objeto)", #selector(primary))
            showShortcut(on: b)
            add("Já bati \(next.objeto)", #selector(markDone))
            if next == .saidaAlmoco {
                add("Encerrar o dia agora", #selector(endDay))
            }
        } else {
            let done = add("Tudo batido por hoje", nil)
            done.isEnabled = false
        }

        menu.addItem(.separator())

        if Prefs.lunchEnabled && record.time(of: .saidaAlmoco) == nil && record.phase != .encerrado {
            let l = add("Hoje sem almoço", #selector(toggleNoLunch))
            l.state = record.noLunch ? .on : .off
        }
        if record.punches.isEmpty {
            let o = add("Hoje não trabalho", #selector(toggleDayOff))
            o.state = record.dayOff ? .on : .off
        } else {
            add("Desfazer última marcação", #selector(undoLast))
        }

        menu.addItem(.separator())

        if Updater.shared.installing {
            let u = add("Atualizando o Ponto…", nil)
            u.isEnabled = false
        } else if let release = Updater.shared.available {
            add("Atualizar para a versão \(release.version)…", #selector(update))
        } else {
            add("Procurar atualização…", #selector(update))
        }

        let s = add("Ajustes…", #selector(openSettings))
        s.keyEquivalent = ","
        s.keyEquivalentModifierMask = [.command]

        let q = add("Sair do Ponto", #selector(quit))
        q.keyEquivalent = "q"
        q.keyEquivalentModifierMask = [.command]
    }

    /// Mostra o atalho de bater ao lado do item, quando ele é uma letra.
    private func showShortcut(on menuItem: NSMenuItem) {
        guard Prefs.hotkeysOn else { return }
        let key = Prefs.hotkeyPunch
        guard !key.char.isEmpty else { return }
        menuItem.keyEquivalent = key.char
        menuItem.keyEquivalentModifierMask = key.menuModifiers
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector?) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menu.addItem(menuItem)
        return menuItem
    }

    @objc private func primary() { engine.primaryAction() }
    @objc private func markDone() { engine.markDone() }
    @objc private func cancelConfirm() { engine.cancelConfirm() }
    @objc private func endDay() { engine.startPunch(.saida) }
    @objc private func toggleNoLunch() { engine.setNoLunch(!engine.record.noLunch) }
    @objc private func toggleDayOff() { engine.setDayOff(!engine.record.dayOff) }
    @objc private func undoLast() { engine.undoLast() }
    @objc private func dismissNotice() { engine.dismissNotice() }
    @objc private func update() { Updater.shared.promptAvailable() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// Topo do menu: contador grande, progresso e as marcações do dia.
struct MenuHeader: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(engine.statusLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if let exit = engine.predictedExit {
                    Text("Saída prevista \(Fmt.hora(exit))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.contador(engine.worked, segundos: true))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("de \(Fmt.minutos(Prefs.rules.workMinutes))")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            ProgressView(value: engine.progress)
                .progressViewStyle(.linear)

            HStack(spacing: 0) {
                ForEach(PunchKind.allCases, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.nomeCurto)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(engine.record.time(of: kind).map { Fmt.hora($0) } ?? "–")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 2)

            Text(engine.nextLine)
                .font(.system(size: 12))
                .foregroundColor(engine.isOverdue ? .orange : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 300, alignment: .leading)
    }
}
