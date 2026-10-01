import AppKit

/// What the overlay shows: a colour (its alpha is the overlay's opacity) or a photo filling the screen.
enum FlashLook {
    case color(NSColor)
    case photo(NSImage)
}

/// Overlay on every screen that pulses a few times, then stays until you click anywhere or press a key.
@MainActor
final class Flasher {
    private var windows: [NSWindow] = []
    /// Bumped on dismiss so pending pulse steps from that flash stop.
    private var generation = 0
    /// Called when the user dismisses the flash.
    var onDismiss: (() -> Void)?

    func flash(title: String?, subtitle: String?, look: FlashLook, pulses: Int = 3) {
        // A newer alert (say "at start" after "5 min before") replaces one that's still up, so it pulses again.
        if !windows.isEmpty {
            generation += 1
            windows.forEach { $0.close() }
            windows.removeAll()
        }

        for screen in NSScreen.screens {
            let w = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = false
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.hidesOnDeactivate = false // panels hide with an inactive app by default, and this one always is
            w.alphaValue = 0
            w.setFrame(screen.frame, display: false)

            let view = DismissView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onDismiss = { [weak self] in self?.dismiss() }
            switch look {
            case .color(let color):
                w.backgroundColor = color
            case .photo(let image):
                w.backgroundColor = .black
                view.showPhoto(image, dimmed: title != nil)
            }
            Self.addLabels(title: title, subtitle: subtitle, to: view)
            w.contentView = view
            w.orderFrontRegardless()
            windows.append(w)
        }

        // Key without activating the app, so a key press dismisses it and focus stays with the app you were in.
        if let first = windows.first {
            first.makeKey()
            first.makeFirstResponder(first.contentView)
        }

        pulse(remaining: pulses, generation: generation)
    }

    func dismiss() {
        guard !windows.isEmpty else { return }
        generation += 1
        onDismiss?()
        let closing = windows
        windows.removeAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            Task { @MainActor in closing.forEach { $0.close() } }
        })
    }

    /// Fades in and out, and on the last pulse fades in and stays until dismissed.
    private func pulse(remaining: Int, generation: Int) {
        guard generation == self.generation else { return }
        animate(to: 1, duration: 0.25) { [weak self] in
            guard remaining > 1 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard generation == self?.generation else { return }
                self?.animate(to: 0, duration: 0.3) {
                    self?.pulse(remaining: remaining - 1, generation: generation)
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

    private static func addLabels(title: String?, subtitle: String?, to container: NSView) {
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 8

        var views: [NSView] = []
        if let title {
            let titleField = NSTextField(labelWithString: title)
            titleField.font = .systemFont(ofSize: 64, weight: .heavy)
            titleField.textColor = .white
            titleField.alignment = .center
            titleField.lineBreakMode = .byTruncatingTail
            titleField.shadow = shadow
            views.append(titleField)

            let subField = NSTextField(labelWithString: subtitle ?? "")
            subField.font = .systemFont(ofSize: 30, weight: .semibold)
            subField.textColor = .white.withAlphaComponent(0.9)
            subField.alignment = .center
            subField.shadow = shadow
            views.append(subField)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let hint = NSTextField(labelWithString: "Click anywhere or press any key to dismiss")
        hint.font = .systemFont(ofSize: 16, weight: .medium)
        hint.textColor = .white.withAlphaComponent(0.8)
        hint.shadow = shadow
        hint.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hint)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.85),
            hint.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -60),
        ])
    }
}

/// A non-activating panel can take key presses without MeetingFlash stealing focus
/// (macOS usually refuses to activate a background menu bar app anyway).
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Fills the overlay and dismisses it on any click or key press.
private final class DismissView: NSView {
    var onDismiss: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { onDismiss?() }
    override func rightMouseDown(with event: NSEvent) { onDismiss?() }
    override func otherMouseDown(with event: NSEvent) { onDismiss?() }
    override func keyDown(with event: NSEvent) { onDismiss?() }

    /// Photo scaled to fill the screen, darkened a little when text sits on top of it.
    func showPhoto(_ image: NSImage, dimmed: Bool) {
        wantsLayer = true
        let photo = CALayer()
        photo.contents = image
        photo.contentsGravity = .resizeAspectFill
        photo.frame = bounds
        photo.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        photo.masksToBounds = true
        layer?.addSublayer(photo)
        if dimmed {
            let scrim = CALayer()
            scrim.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
            scrim.frame = bounds
            scrim.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer?.addSublayer(scrim)
        }
    }
}
