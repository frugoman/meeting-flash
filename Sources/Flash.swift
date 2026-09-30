import AppKit

/// Click-through red overlay on every screen that pulses a few times, then disappears.
@MainActor
final class Flasher {
    private var windows: [NSWindow] = []

    func flash(title: String?, subtitle: String?, pulses: Int = 3) {
        guard windows.isEmpty else { return } // already flashing

        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = false
            w.hasShadow = false
            w.backgroundColor = NSColor.systemRed.withAlphaComponent(0.55)
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.alphaValue = 0
            w.setFrame(screen.frame, display: false)

            if let title {
                w.contentView = Self.label(title: title, subtitle: subtitle, in: screen.frame.size)
            }
            w.orderFrontRegardless()
            windows.append(w)
        }
        pulse(remaining: pulses)
    }

    private func pulse(remaining: Int) {
        guard remaining > 0 else {
            windows.forEach { $0.close() }
            windows.removeAll()
            return
        }
        animate(to: 1, duration: 0.25) { [weak self] in
            // Hold longer on the last pulse so the title can be read.
            DispatchQueue.main.asyncAfter(deadline: .now() + (remaining == 1 ? 1.5 : 0.35)) {
                self?.animate(to: 0, duration: 0.3) {
                    self?.pulse(remaining: remaining - 1)
                }
            }
        }
    }

    private func animate(to alpha: CGFloat, duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            windows.forEach { $0.animator().alphaValue = alpha }
        }, completionHandler: { Task { @MainActor in completion() } })
    }

    private static func label(title: String, subtitle: String?, in size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 64, weight: .heavy)
        titleField.textColor = .white
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail

        let subField = NSTextField(labelWithString: subtitle ?? "")
        subField.font = .systemFont(ofSize: 30, weight: .semibold)
        subField.textColor = .white.withAlphaComponent(0.9)
        subField.alignment = .center

        let stack = NSStackView(views: [titleField, subField])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.85),
        ])
        return container
    }
}
