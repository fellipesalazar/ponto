import AppKit
import SwiftUI

/// Opções de adiamento, na ordem das teclas 1 a 4.
let snoozeOptions = [5, 10, 15, 30]

/// Texto de botão com a tecla de atalho ao lado.
struct KeyLabel: View {
    let title: String
    let key: String
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(prominent ? Color.white.opacity(0.22) : Color.primary.opacity(0.1))
                )
                .opacity(0.85)
        }
    }
}

/// Hosting view que aceita o primeiro clique mesmo com outro app na frente.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Tela onde o cursor está agora.
func screenWithMouse() -> NSScreen? {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
        ?? NSScreen.main
        ?? NSScreen.screens.first
}

func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding<Date>(
        get: {
            Calendar.current.startOfDay(for: Date())
                .addingTimeInterval(TimeInterval(minutes.wrappedValue * 60))
        },
        set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    )
}
