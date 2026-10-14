import AppKit
import SpacersCore

@MainActor
private final class MenuAction: NSObject {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @objc func invoke(_ sender: NSMenuItem) {
        // Finish menu tracking before removing items or presenting a window.
        let action = action
        DispatchQueue.main.async { action() }
    }
}

@MainActor
extension NSMenu {
    @discardableResult
    func addAction(_ title: String, state: NSControl.StateValue = .off,
                   key: String = "", action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let handler = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.invoke(_:)), keyEquivalent: key)
        item.target = handler
        item.representedObject = handler
        item.state = state
        addItem(item)
        return item
    }

    func addNote(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    let statusItem: NSStatusItem
    var configuration: ItemConfiguration
    weak var owner: AppDelegate?
    var displayedNumber: Int { owner?.number(for: configuration.id) ?? 1 }

    init(configuration: ItemConfiguration, owner: AppDelegate) {
        self.configuration = configuration
        self.owner = owner
        statusItem = NSStatusBar.system.statusItem(withLength: configuration.width)
        super.init()
        statusItem.autosaveName = configuration.autosaveName
        // Reordering is native. Removal happens through the item's menu, so a
        // mistaken drag off the bar cannot strand an invisible last item.
        statusItem.behavior = []
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        update(configuration)
    }

    func update(_ configuration: ItemConfiguration) {
        self.configuration = configuration
        if let width = StatusItemSizing.widthToApply(for: configuration, currentWidth: statusItem.length) {
            statusItem.length = width
        }
        render()
    }

    func applyFlexWidth(_ width: Double) {
        statusItem.length = width
        render()
    }

    func refreshAppearance() { render() }
    var displaysNumber: Bool {
        owner?.isShowingAll == true ? configuration.kind != .divider : configuration.isHighlighted
    }
    var displayedOpacity: Double { owner?.isShowingAll == true ? 1 : configuration.opacity }

    private func render() {
        guard let button = statusItem.button else { return }
        var configuration = self.configuration
        configuration.width = statusItem.length
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = "\(configuration.kind.title) \(displayedNumber) • Click for options • ⌘-drag to move"
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.menuBarItem)
        button.setAccessibilityIdentifier("SpaceBar.Item.\(configuration.id.uuidString)")
        let dimension: ItemDimension = configuration.kind != .divider ? .width : .height
        button.setAccessibilityLabel("\(configuration.kind.title) \(displayedNumber), \(dimension.title.lowercased()) \(dimension.label(for: configuration[dimension]))")
        if displaysNumber {
            button.image = ItemNumberImage.make(configuration: configuration, number: displayedNumber)
        } else if configuration.kind == .divider {
            let height = min(configuration.height, max(4, NSStatusBar.system.thickness - 6))
            let thickness = configuration.thickness
            let opacity = displayedOpacity
            let image = NSImage(size: NSSize(width: 4, height: height), flipped: false) { rect in
                NSColor.black.withAlphaComponent(opacity).setFill()
                NSBezierPath(rect: NSRect(x: rect.midX - thickness / 2, y: 0,
                                          width: thickness, height: rect.height)).fill()
                return true
            }
            image.isTemplate = true
            button.image = image
        } else {
            button.image = nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        owner?.populate(menu, for: configuration.id)
    }

    func menuDidClose(_ menu: NSMenu) {
        owner?.cancelPreview(for: configuration.id)
        owner?.cancelDividerPreview()
    }

    func remove() {
        statusItem.menu?.delegate = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

@MainActor
enum ItemNumberImage {
    static func make(configuration: ItemConfiguration, number: Int) -> NSImage {
        let outline = configuration.kind != .divider
        let number = String(number)
        let width = configuration.width
        let baseFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let textWidth = (number as NSString).size(withAttributes: [.font: baseFont]).width
        let availableWidth = max(1, width - (outline ? 2 : 0))
        let fontSize = 11 * min(1, availableWidth / max(1, textWidth))
        // Fit the label inside the allocated width. A narrow divider temporarily
        // shows its number in place of the line; showing labels never widens it.
        let image = NSImage(size: NSSize(width: width, height: 16), flipped: false) { rect in
            if outline {
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
                NSColor.black.withAlphaComponent(0.12).setFill()
                path.fill()
                NSColor.black.withAlphaComponent(0.65).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
            let text = number as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                      withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }

}
