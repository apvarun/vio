import AppKit
import SwiftUI

/// A small always-on-top pill shown near the text caret (or top-center of
/// the screen) while dictation is recording.
final class RecordingIndicator {
    static let shared = RecordingIndicator()

    private var panel: NSPanel?

    func show(caret: CGRect?, hint: String) {
        hide()
        guard let main = NSScreen.main ?? NSScreen.screens.first else { return }
        var screen = main
        var anchor: NSPoint?

        if let caret {
            screen = NSScreen.screens.first {
                $0.frame.contains(NSPoint(x: caret.midX, y: caret.midY))
            } ?? main
            anchor = NSPoint(x: caret.midX, y: caret.maxY + 10)
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false

        let contentView = NSHostingView(rootView: PillView(text: hint))
        panel.contentView = contentView
        let size = contentView.fittingSize

        let origin: NSPoint
        if let anchor {
            origin = NSPoint(
                x: min(max(anchor.x - size.width / 2, screen.frame.minX + 8), screen.frame.maxX - size.width - 8),
                y: min(max(anchor.y, screen.frame.minY + 8), screen.frame.maxY - size.height - 8)
            )
        } else {
            origin = NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height - 60
            )
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct PillView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
                .modifier(Pulsing())
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.red.opacity(0.35)))
    }
}

private struct Pulsing: ViewModifier {
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.25 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}
