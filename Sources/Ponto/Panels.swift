import AppKit
import SwiftUI

// Painéis flutuantes: a confirmação "Bateu?", o aviso no canto e o contador que nunca some.

// MARK: - Confirmação

final class ConfirmPanelController {
    private let engine: Engine
    private var panel: NSPanel?

    var isShown: Bool { panel != nil }

    init(engine: Engine) {
        self.engine = engine
    }

    func show() {
        guard panel == nil else { return }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true

        let host = FirstMouseHostingView(rootView: ConfirmView().environmentObject(engine))
        let size = host.fittingSize
        blur.frame = NSRect(origin: .zero, size: size)
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        p.contentView = blur
        p.setContentSize(size)

        // No alto da tela em que você está, pra não cobrir a página do ponto.
        if let screen = screenWithMouse() {
            let area = screen.visibleFrame
            let origin = NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 16)
            p.setFrameOrigin(origin)
        }

        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct ConfirmView: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 30))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(verbatim: subtitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 16)

            Button("Ainda não") {
                engine.cancelConfirm()
            }

            Button {
                engine.confirmPunch()
            } label: {
                KeyLabel(title: "Bati", key: "⌃⌥⌘P", prominent: true)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 500)
    }

    private var subtitle: String {
        let prefix = engine.previewConfirm ? "Teste: nada vai ser registrado" : "Esperando você confirmar"
        return prefix + " · " + Fmt.regressiva(left)
    }

    private var title: String {
        guard let kind = engine.awaitingConfirm else { return "Bateu o ponto?" }
        return "Bateu \(kind.objeto)?"
    }

    private var left: TimeInterval {
        guard let deadline = engine.confirmDeadline else { return 0 }
        return deadline.timeIntervalSince(engine.now)
    }
}

// MARK: - Aviso no canto

/// Versão discreta do alerta: fica no canto de cima à direita até você decidir,
/// sem travar a tela.
final class NoticePanelController {
    private let engine: Engine
    private var panel: NSPanel?
    private(set) var shownKind: PunchKind?

    var isShown: Bool { panel != nil }

    init(engine: Engine) {
        self.engine = engine
    }

    func show(_ kind: PunchKind) {
        if panel != nil { hide() }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true

        let host = FirstMouseHostingView(rootView: NoticeView(kind: kind).environmentObject(engine))
        let size = host.fittingSize
        blur.frame = NSRect(origin: .zero, size: size)
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        p.contentView = blur
        p.setContentSize(size)

        if let screen = screenWithMouse() {
            let area = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: area.maxX - size.width - 14, y: area.maxY - size.height - 14))
        }

        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            p.animator().alphaValue = 1
        }
        panel = p
        shownKind = kind
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        shownKind = nil
    }
}

struct NoticeView: View {
    @EnvironmentObject var engine: Engine
    let kind: PunchKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: kind.simbolo)
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.chamada)
                        .font(.headline)
                    Text(engine.lockSubtitle(kind))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    engine.startPunch()
                } label: {
                    KeyLabel(title: "Bater agora", key: "⌃⌥⌘P", prominent: true)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    engine.markDone()
                } label: {
                    Text(verbatim: "Já bati")
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text(verbatim: "Lembrar em")
                    .font(.callout)
                    .foregroundColor(.secondary)
                ForEach(snoozeOptions, id: \.self) { minutes in
                    Button {
                        engine.snooze(minutes: minutes)
                    } label: {
                        Text(verbatim: "\(minutes) min")
                    }
                    .controlSize(.small)
                }
            }

            if let extra = engine.lockExtraTitle(kind) {
                Button {
                    engine.lockExtra()
                } label: {
                    Text(verbatim: extra)
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }
}

// MARK: - Contador flutuante

final class FloatingCounterController {
    private let engine: Engine
    private var panel: NSPanel?
    private var host: NSView?
    private var moveObserver: NSObjectProtocol?

    init(engine: Engine) {
        self.engine = engine
    }

    func setVisible(_ visible: Bool) {
        if visible {
            if panel == nil { build() }
            fit()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func build() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 90, height: 26),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 13
        blur.layer?.masksToBounds = true

        let h = NSHostingView(rootView: PillView().environmentObject(engine))
        blur.addSubview(h)
        p.contentView = blur
        host = h
        panel = p

        fit()
        place(p)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: p, queue: .main
        ) { [weak p] _ in
            guard let p = p else { return }
            Prefs.d.set(Double(p.frame.origin.x), forKey: Prefs.Key.floatingX)
            Prefs.d.set(Double(p.frame.origin.y), forKey: Prefs.Key.floatingY)
        }
    }

    /// Ajusta a largura ao texto, mantendo o canto de cima à esquerda no lugar.
    private func fit() {
        guard let p = panel, let h = host else { return }
        let size = h.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        if abs(p.frame.width - size.width) > 0.5 || abs(p.frame.height - size.height) > 0.5 {
            let top = p.frame.maxY
            p.setFrame(NSRect(x: p.frame.origin.x, y: top - size.height, width: size.width, height: size.height),
                       display: true)
        }
        h.frame = NSRect(origin: .zero, size: size)
    }

    private func place(_ p: NSPanel) {
        if Prefs.d.object(forKey: Prefs.Key.floatingX) != nil {
            let saved = NSPoint(x: Prefs.d.double(forKey: Prefs.Key.floatingX),
                                y: Prefs.d.double(forKey: Prefs.Key.floatingY))
            let frame = NSRect(origin: saved, size: p.frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                p.setFrameOrigin(saved)
                return
            }
        }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let area = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: area.maxX - p.frame.width - 12, y: area.maxY - p.frame.height - 8))
        }
    }
}

struct PillView: View {
    @EnvironmentObject var engine: Engine

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: engine.barSymbol)
            if !engine.barTitle.isEmpty {
                Text(engine.barTitle)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .fixedSize()
    }
}
