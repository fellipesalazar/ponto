import AppKit
import SwiftUI

// A trava: uma janela por tela, por cima de tudo, até você decidir.

final class LockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class LockController {
    private let engine: Engine
    private var windows: [NSWindow] = []
    private var monitor: Any?
    private var previousApp: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?

    var isShown: Bool { !windows.isEmpty }

    init(engine: Engine) {
        self.engine = engine
    }

    func show() {
        guard !isShown else { return }

        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }

        buildWindows()

        // Some com Dock e barra de menus e desliga o ⌘Tab enquanto a trava está na frente.
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.isShown else { return event }
            self.handleKey(event)
            return nil
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isShown else { return }
            self.closeWindows()
            self.buildWindows()
            self.enforce()
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.enforce()
        }
    }

    func hide(restoreFocus: Bool) {
        guard isShown else { return }
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        if let o = screenObserver {
            NotificationCenter.default.removeObserver(o)
            screenObserver = nil
        }
        if let o = resignObserver {
            NotificationCenter.default.removeObserver(o)
            resignObserver = nil
        }
        closeWindows()
        NSApp.presentationOptions = []
        if restoreFocus, let app = previousApp, !app.isTerminated {
            _ = app.activate(options: [])
        }
        previousApp = nil
    }

    /// Mantém a trava na frente se algo tentar passar por cima.
    func enforce() {
        guard isShown else { return }
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        for w in windows {
            w.orderFrontRegardless()
        }
        if let key = NSApp.keyWindow, windows.contains(where: { $0 === key }) {
            return
        }
        windows.first?.makeKey()
    }

    private func buildWindows() {
        // A tela onde o cursor está vai primeiro, pra receber o teclado.
        var screens = NSScreen.screens
        if let mouseScreen = screenWithMouse(),
           let index = screens.firstIndex(where: { $0 === mouseScreen }) {
            screens.insert(screens.remove(at: index), at: 0)
        }
        for screen in screens {
            windows.append(makeWindow(for: screen))
        }
    }

    private func closeWindows() {
        for w in windows {
            w.orderOut(nil)
        }
        windows.removeAll()
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let w = LockWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]

        // Aceita o primeiro clique mesmo se outro app ainda estiver na frente.
        let host = FirstMouseHostingView(rootView: LockView().environmentObject(engine))
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)

        w.contentView = blur
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            w.animator().alphaValue = 1
        }
        return w
    }

    private func handleKey(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()

        // Saída de emergência: ⌃⌥⌘Q fecha o app.
        if flags.contains([.control, .option, .command]) && chars == "q" {
            NSApp.terminate(nil)
            return
        }

        guard engine.lockArmed, !event.isARepeat else { return }
        guard flags.intersection([.command, .control, .option]).isEmpty else { return }

        if event.keyCode == 36 || event.keyCode == 76 { // Return ou Enter
            engine.startPunch()
            return
        }

        switch chars {
        case "j": engine.markDone()
        case "n": engine.lockExtra()
        case "1": engine.snooze(minutes: snoozeOptions[0])
        case "2": engine.snooze(minutes: snoozeOptions[1])
        case "3": engine.snooze(minutes: snoozeOptions[2])
        case "4": engine.snooze(minutes: snoozeOptions[3])
        default: break
        }
    }
}

struct LockView: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
            if let kind = engine.lockKind {
                card(kind)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ kind: PunchKind) -> some View {
        VStack(spacing: 0) {
            Image(systemName: kind.simbolo)
                .font(.system(size: 46))
                .foregroundColor(.accentColor)
                .padding(.bottom, 18)

            Text(kind.chamada)
                .font(.system(size: 30, weight: .bold))

            Text(engine.lockSubtitle(kind))
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            if engine.preview != nil {
                Text("Isto é um teste. Qualquer opção fecha.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
            }

            HStack(spacing: 12) {
                Button {
                    engine.startPunch()
                } label: {
                    KeyLabel(title: "Bater agora", key: "↩", prominent: true)
                        .frame(minWidth: 170)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    engine.markDone()
                } label: {
                    KeyLabel(title: "Já bati", key: "J")
                        .frame(minWidth: 110)
                }
            }
            .controlSize(.large)
            .padding(.top, 28)

            Divider()
                .padding(.vertical, 22)

            Text("Lembrar de novo em")
                .font(.callout)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                ForEach(Array(snoozeOptions.enumerated()), id: \.offset) { pair in
                    Button {
                        engine.snooze(minutes: pair.element)
                    } label: {
                        KeyLabel(title: "\(pair.element) min", key: "\(pair.offset + 1)")
                    }
                }
            }
            .padding(.top, 10)

            if let extra = engine.lockExtraTitle(kind) {
                Button {
                    engine.lockExtra()
                } label: {
                    KeyLabel(title: extra, key: "N")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .padding(.top, 20)
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 40)
        .frame(width: 540)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 30, x: 0, y: 10)
        .disabled(!engine.lockArmed)
    }
}
