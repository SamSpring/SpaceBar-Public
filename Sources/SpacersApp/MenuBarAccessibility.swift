import AppKit
@preconcurrency import ApplicationServices
import SpacersCore

struct LayoutApp: Sendable {
    let pid: pid_t
    let bundleID: String
    let name: String
}

struct LayoutScreen: Sendable {
    let display: LayoutDisplay
    let bounds: CGRect
    let menuHeight: Double
    let notch: CGRect?

    func usablePoint(in rect: CGRect) -> CGPoint? {
        let area = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: menuHeight)
        let visible = rect.intersection(area)
        guard !visible.isNull, visible.width >= 3, visible.height >= 3 else { return nil }
        for x in [visible.midX, visible.maxX - 2, visible.minX + 2] {
            let point = CGPoint(x: x, y: visible.midY)
            if notch?.contains(point) != true { return point }
        }
        return nil
    }
}

enum MenuBarAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }
    static var canPostEvents: Bool { CGPreflightPostEventAccess() }
    @MainActor static func requestAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor static func screens() -> [LayoutScreen] {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value) else { return nil }
            let id = CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
            let bounds = CGDisplayBounds(number.uint32Value)
            var notch: CGRect?
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                notch = CGRect(x: left.maxX, y: primaryTop - screen.frame.maxY,
                               width: right.minX - left.maxX, height: max(left.height, right.height))
            }
            return LayoutScreen(display: LayoutDisplay(id: id, name: screen.localizedName,
                                                       width: bounds.width, height: bounds.height),
                                bounds: bounds, menuHeight: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top), notch: notch)
        }
    }

    @MainActor static func apps(qaOnly: Bool) -> [LayoutApp] {
        if qaOnly {
            // The regular flex poll reads only our own item. Do not query every
            // running application's dynamic LaunchServices properties each tick.
            let app = NSRunningApplication.current
            guard let id = Bundle.main.bundleIdentifier else { return [] }
            return [LayoutApp(pid: app.processIdentifier, bundleID: id, name: app.localizedName ?? id)]
        }
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, !app.isTerminated,
                  !qaOnly || id == Bundle.main.bundleIdentifier else { return nil }
            return LayoutApp(pid: app.processIdentifier, bundleID: id, name: app.localizedName ?? id)
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions),
              [point.x, point.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    /// Read the immediate left-hand application menu frames, never menu contents.
    static func applicationMenuRight(pid: pid_t, screen: LayoutScreen, knownScreens: [LayoutScreen]) -> Double? {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let bar = element(attribute(root, kAXMenuBarAttribute)) else { return nil }
        AXUIElementSetMessagingTimeout(bar, 0.12)
        guard let barFrame = frame(bar),
              let children = attribute(bar, kAXChildrenAttribute) as? [AXUIElement],
              !children.isEmpty, children.count <= 32 else { return nil }
        let frames = children.compactMap { item -> CGRect? in
            AXUIElementSetMessagingTimeout(item, 0.12)
            return frame(item)
        }
        guard frames.count == children.count else { return nil }
        return ApplicationMenuGeometry.rightEdge(menuBar: barFrame, items: frames,
            targetDisplay: screen.bounds, knownDisplays: knownScreens.map(\.bounds))
    }

    /// On macOS 27 the system hosts the visible items. Read only its menu-bar
    /// windows and immediate status proxies; never traverse a delegated app's
    /// windows, left-hand menus, or popup menus.
    static func read(apps: [LayoutApp], screens: [LayoutScreen], agent: LayoutApp?,
                     bindings: [OwnMenuBarBinding]) -> MenuBarReadout {
        var result = MenuBarReadout()
        func append(_ target: MenuBarTarget) {
            guard let screen = screens.first(where: { $0.display.id == target.displayID }),
                  screen.usablePoint(in: target.rect) != nil else { return }
            let icon = LayoutIcon(bundleID: target.app.bundleID, appName: target.app.name,
                identifier: target.identifier, label: target.label, displayID: target.displayID,
                left: target.rect.minX - screen.bounds.minX, top: max(0, target.rect.minY - screen.bounds.minY),
                width: target.rect.width, height: target.rect.height)
            // The same AX object can occur in both extras and a window.
            guard !result.targets.values.contains(where: { CFEqual($0.element, target.element) && $0.displayID == target.displayID }) else { return }
            result.icons.append(icon); result.targets[icon.id] = target
        }
        func screenFor(_ rect: CGRect) -> LayoutScreen? {
            screens.first { rect.minX >= $0.bounds.minX && rect.maxX <= $0.bounds.maxX &&
                rect.minY >= $0.bounds.minY - 2 && rect.maxY <= $0.bounds.minY + $0.menuHeight + 8 }
        }
        if let agent {
            let root = AXUIElementCreateApplication(agent.pid)
            AXUIElementSetMessagingTimeout(root, 0.15)
            let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.12)
                guard !Task.isCancelled, let area = frame(window), screenFor(area) != nil else { continue }
                for proxy in attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                    if Task.isCancelled { break }
                    AXUIElementSetMessagingTimeout(proxy, 0.12)
                    guard let rect = frame(proxy), let screen = screenFor(rect),
                          (attribute(proxy, kAXHiddenAttribute) as? Bool) != true else { continue }
                    let children = attribute(proxy, kAXChildrenAttribute) as? [AXUIElement] ?? []
                    // A remote app proxy may expose the owning application in
                    // place of the item. Use its PID only, without reading it.
                    if let delegated = children.first(where: { child in
                        var pid: pid_t = 0; AXUIElementGetPid(child, &pid)
                        return apps.contains { $0.pid == pid && pid != agent.pid }
                    }) {
                        var pid: pid_t = 0; AXUIElementGetPid(delegated, &pid)
                        guard let app = apps.first(where: { $0.pid == pid }) else { continue }
                        let bound = bindings.first { CFEqual($0.element, proxy) }
                        append(MenuBarTarget(element: proxy, app: app, rect: rect, displayID: screen.display.id,
                            identifier: bound?.identifier ?? "", label: bound?.label ?? ""))
                        continue
                    }
                    // Native system items and apps that expose proper AX leaves.
                    var budget = 16
                    func visit(_ item: AXUIElement, depth: Int) {
                        guard depth < 4, budget > 0, !Task.isCancelled else { return }; budget -= 1
                        AXUIElementSetMessagingTimeout(item, 0.12)
                        let role = attribute(item, kAXRoleAttribute) as? String ?? ""
                        guard ![kAXApplicationRole, kAXWindowRole, kAXMenuRole].contains(role) else { return }
                        var pid: pid_t = 0; AXUIElementGetPid(item, &pid)
                        guard let app = apps.first(where: { $0.pid == pid }) else { return }
                        if [kAXMenuBarItemRole, kAXButtonRole].contains(role) {
                            let id = attribute(item, kAXIdentifierAttribute) as? String ?? ""
                            let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                                .compactMap { attribute(item, $0) as? String }.first { !$0.isEmpty } ?? ""
                            append(MenuBarTarget(element: proxy, app: app, rect: rect, displayID: screen.display.id,
                                                 identifier: id, label: label)); return
                        }
                        for child in attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
                    }
                    visit(proxy, depth: 0)
                }
            }
            result.icons = LayoutMatching.stampOccurrences(result.icons)
            return result
        }
        // Older/public client-side trees, retained as a bounded fallback.
        for app in apps {
            if Task.isCancelled { break }
            let deadline = Date().addingTimeInterval(0.8)
            let root = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(root, 0.15)
            guard let bar = element(attribute(root, kAXExtrasMenuBarAttribute)) else { continue }
            var budget = 128
            func visit(_ item: AXUIElement, depth: Int) {
                guard budget > 0, depth < 5, Date() < deadline, !Task.isCancelled else { return }; budget -= 1
                AXUIElementSetMessagingTimeout(item, 0.15)
                let role = attribute(item, kAXRoleAttribute) as? String ?? ""
                guard role != kAXMenuRole else { return }
                if [kAXMenuBarItemRole, kAXButtonRole].contains(role), let rect = frame(item),
                   let screen = screenFor(rect) {
                    let id = attribute(item, kAXIdentifierAttribute) as? String ?? ""
                    let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                        .compactMap { attribute(item, $0) as? String }.first { !$0.isEmpty } ?? ""
                    append(MenuBarTarget(element: item, app: app, rect: rect, displayID: screen.display.id,
                                         identifier: id, label: label)); return
                }
                for child in attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? [] { visit(child, depth: depth + 1) }
            }
            visit(bar, depth: 0)
        }
        result.icons = LayoutMatching.stampOccurrences(result.icons)
        return result
    }

    static func readBindings(_ bindings: [OwnMenuBarBinding], app: LayoutApp,
                             screens: [LayoutScreen], agent: LayoutApp?) -> MenuBarReadout {
        var result = MenuBarReadout()
        var visibleProxies: [AXUIElement] = []
        if let agent {
            let root = AXUIElementCreateApplication(agent.pid)
            AXUIElementSetMessagingTimeout(root, 0.12)
            for window in attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                if Task.isCancelled { break }
                AXUIElementSetMessagingTimeout(window, 0.12)
                guard let rect = frame(window), screens.contains(where: {
                    abs(rect.minX - $0.bounds.minX) < 1 && abs(rect.minY - $0.bounds.minY) < 1
                }) else { continue }
                visibleProxies += attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []
            }
        }
        for binding in bindings {
            if Task.isCancelled { break }
            // Fetch a fresh reference from the host. Cached remote AX handles
            // can become unreadable after a width update despite equal identity.
            guard let proxy = agent == nil ? binding.element : visibleProxies.first(where: { CFEqual($0, binding.element) }) else { continue }
            AXUIElementSetMessagingTimeout(proxy, 0.12)
            guard let rect = frame(proxy),
                  (attribute(proxy, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains(where: {
                      var pid: pid_t = 0; AXUIElementGetPid($0, &pid); return pid == app.pid
                  }), let screen = screens.first(where: {
                      rect.minX >= $0.bounds.minX && rect.maxX <= $0.bounds.maxX &&
                      rect.minY >= $0.bounds.minY - 2 && rect.maxY <= $0.bounds.minY + $0.menuHeight + 8
                  }), screen.usablePoint(in: rect) != nil else { continue }
            let icon = LayoutIcon(bundleID: app.bundleID, appName: app.name,
                identifier: binding.identifier, label: binding.label, displayID: screen.display.id,
                left: rect.minX - screen.bounds.minX, top: max(0, rect.minY - screen.bounds.minY),
                width: rect.width, height: rect.height)
            result.icons.append(icon)
            result.targets[icon.id] = MenuBarTarget(element: proxy, app: app, rect: rect,
                displayID: screen.display.id, identifier: binding.identifier, label: binding.label)
        }
        return result
    }

    static func drag(from source: CGPoint, to destination: CGPoint, target: MenuBarTarget) async throws {
        guard isTrusted, CGPreflightPostEventAccess() else { throw LayoutOperationError.accessRequired }
        try Task.checkCancellation()
        // Recheck the source before any mouse-down; a stale coordinate must not
        // accidentally operate another app's item or open an application menu.
        var hit: AXUIElement?
        guard target.rect.contains(source),
              AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(source.x), Float(source.y), &hit) == .success,
              let hit else { throw LayoutOperationError.iconMoved }
        // The system host may return a descendant. Verify immutable AX identity
        // rather than accepting a host PID shared by every application's icons.
        var candidate: AXUIElement? = hit
        var verified = false
        for _ in 0..<4 {
            guard let current = candidate else { break }
            if CFEqual(current, target.element) { verified = true; break }
            candidate = element(attribute(current, kAXParentAttribute))
        }
        if !verified {
            var pid: pid_t = 0; AXUIElementGetPid(hit, &pid)
            if pid == target.app.pid {
                let id = attribute(hit, kAXIdentifierAttribute) as? String ?? ""
                let role = attribute(hit, kAXRoleAttribute) as? String ?? ""
                let sameHostedFrame = frame(hit).map { rect in
                    abs(rect.minX - target.rect.minX) <= 3 && abs(rect.maxX - target.rect.maxX) <= 3 &&
                    abs(rect.minY - target.rect.minY) <= 8 && abs(rect.maxY - target.rect.maxY) <= 8
                } ?? false
                verified = (!target.identifier.isEmpty && id == target.identifier) ||
                    (role == kAXMenuBarItemRole && sameHostedFrame)

            }

        }
        if !verified && Bundle.main.bundleIdentifier?.hasSuffix(".UITests") == true {
            var pid: pid_t = 0; AXUIElementGetPid(hit, &pid)
            print("QA rejected drag owner \(pid), expected \(target.app.pid), source \(source), target \(target.rect)")
            if pid == target.app.pid { print("QA hit frame \(String(describing: frame(hit)))") }
        }
        guard verified else { throw LayoutOperationError.iconMoved }
        guard let eventSource = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: source, mouseButton: .left),
              let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: destination, mouseButton: .left) else {
            throw LayoutOperationError.eventUnavailable
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        var last = source
        let started = Date()
        let mouseAge = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
        let keyAge = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        down.post(tap: .cghidEventTap)
        defer {
            // Always release even if Stop or a task cancellation arrives mid-drag.
            up.location = last
            up.post(tap: .cghidEventTap)
        }
        for step in 1...24 {
            try await Task.sleep(for: .milliseconds(25))
            try Task.checkCancellation()
            let elapsed = Date().timeIntervalSince(started)
            if CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved) + 0.05 < mouseAge + elapsed ||
                CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) + 0.05 < keyAge + elapsed {
                throw LayoutOperationError.userInterrupted
            }
            let fraction = Double(step) / 24
            let previous = last
            last = CGPoint(x: source.x + (destination.x - source.x) * fraction,
                           y: source.y + (destination.y - source.y) * fraction)
            guard let event = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDragged,
                                      mouseCursorPosition: last, mouseButton: .left) else { throw LayoutOperationError.eventUnavailable }
            event.setIntegerValueField(.mouseEventDeltaX, value: Int64((last.x - previous.x).rounded()))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64((last.y - previous.y).rounded()))
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}

enum LayoutOperationError: LocalizedError {
    case accessRequired, iconMoved, eventUnavailable, emptyCapture, libraryUnavailable, userInterrupted
    var errorDescription: String? {
        switch self {
        case .accessRequired: "Enable SpaceBar in System Settings → Privacy & Security → Accessibility to save and restore other apps’ icons."
        case .iconMoved: "The icon moved or is not accessible. It was skipped."
        case .eventUnavailable: "macOS could not create the drag events."
        case .emptyCapture: "No visible menu bar icons were accessible. Show the menu bar and try again."
        case .libraryUnavailable: "The saved layouts file could not be loaded. It has been kept unchanged."
        case .userInterrupted: "Restore stopped because the mouse or keyboard was used. Changes already made remain; the “Before Restore” layout is available to undo them."
        }
    }
}
