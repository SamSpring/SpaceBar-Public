import AppKit
import ImageIO
import SpacersCore

@MainActor
public enum SupportArtwork {
    // Decode only a thumbnail when this UI is first opened. The full generated
    // image is never kept decoded in the background menu-bar process.
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "CoffeeCup", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }()

    public static func view(size: CGFloat) -> NSImageView {
        let view = NSImageView()
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel("A smiling coffee cup with a little orbiting star")
        NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: size),
                                     view.heightAnchor.constraint(equalToConstant: size)])
        return view
    }
}

/// A nonmodal thank-you. It never changes Dock policy, menu-bar items, or
/// starts a network request until the user chooses the Ko-fi button.
@MainActor
public final class SupportThankYouWindow: NSWindowController, NSWindowDelegate {
    private let store: SupportNoticeStore
    private let doNotShow = NSButton(checkboxWithTitle: "Don’t show this after updates", target: nil, action: nil)
    private let openURL: (URL) -> Bool
    private let onClose: () -> Void

    public init(store: SupportNoticeStore, openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
                onClose: @escaping () -> Void = {}) {
        self.store = store; self.openURL = openURL; self.onClose = onClose
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Thanks for using SpaceBar"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.delegate = self
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 22
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(root)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
            ])
        }
        let heading = NSTextField(labelWithString: "Enjoying a little extra space?")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        let copy = NSStackView(); copy.orientation = .vertical; copy.alignment = .leading; copy.spacing = 8
        copy.addArrangedSubview(heading)
        let message = NSTextField(wrappingLabelWithString:
            "SpaceBar is free. If it makes your menu bar feel a little better, you can buy me a coffee to support its development. Completely optional, always appreciated.")
        message.textColor = .secondaryLabelColor
        copy.addArrangedSubview(message)
        message.widthAnchor.constraint(equalTo: copy.widthAnchor).isActive = true
        copy.addArrangedSubview(doNotShow)
        copy.setCustomSpacing(12, after: message)
        let hero = NSStackView(views: [SupportArtwork.view(size: 92), copy])
        hero.alignment = .centerY; hero.spacing = 14
        root.addArrangedSubview(hero); hero.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let later = NSButton(title: "Not now", target: self, action: #selector(dismiss))
        later.keyEquivalent = "\u{1b}"
        let coffee = NSButton(title: SpaceBarSupport.buttonTitle, target: self, action: #selector(openSupport))
        coffee.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil)
        coffee.imagePosition = .imageLeading
        coffee.toolTip = "Opens Ko-fi in your browser. Support is optional."
        for button in [later, coffee] { button.bezelStyle = .rounded }
        let buttons = NSStackView(views: [NSView(), later, coffee]); buttons.spacing = 8
        root.addArrangedSubview(buttons); buttons.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        buttons.heightAnchor.constraint(equalToConstant: 32).isActive = true
        // Dismissal is the keyboard default; support always requires a click.
        panel.defaultButtonCell = later.cell as? NSButtonCell
        panel.center()
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    public func present() {
        showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate()
    }

    @objc private func dismiss() { close() }
    @objc private func openSupport() { if openURL(SpaceBarSupport.url) { close() } }

    public func windowWillClose(_ notification: Notification) {
        if doNotShow.state == .on { try? store.disablePrompts() }
        onClose()
    }
}
