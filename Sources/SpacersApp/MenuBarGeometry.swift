import AppKit
@preconcurrency import ApplicationServices
import SpacersCore

/// AX references are immutable handles; the public AX API supports IPC from
/// background threads. Never pass AppKit objects into the background scan.
struct MenuBarTarget: @unchecked Sendable {
    let element: AXUIElement
    let app: LayoutApp
    let rect: CGRect
    let displayID: String
    let identifier: String
    let label: String
}
struct OwnMenuBarBinding: @unchecked Sendable {
    let element: AXUIElement
    let identifier: String
    let label: String
    let requiresUniqueWidth: Bool
}
struct MenuBarReadout: Sendable {
    var icons: [LayoutIcon] = []
    var targets: [UUID: MenuBarTarget] = [:]
}

@MainActor
final class MenuBarGeometry {
    weak var owner: AppDelegate?
    private var bindings: [UUID: [OwnMenuBarBinding]] = [:]
    private var hostPadding: MenuBarHostPadding?
    private var calibratedLengths: [UUID: Double] = [:]
    private var resolving = false
    private var bindingGeneration = 0
    init(owner: AppDelegate) { self.owner = owner }

    func invalidateOwnBindings() {
        bindingGeneration += 1
        bindings.removeAll()
        hostPadding = nil
        calibratedLengths.removeAll()
    }

    func read(apps: [LayoutApp], screens: [LayoutScreen]) async -> MenuBarReadout {
        let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
            .map { LayoutApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier!, name: "macOS") }
        let known = bindings.values.flatMap { $0 }
        let task = Task.detached(priority: .userInitiated) {
            MenuBarAccess.read(apps: apps, screens: screens, agent: agent, bindings: known)
        }
        return await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }

    func readOwn(_ id: UUID, screens: [LayoutScreen]) async -> MenuBarReadout {
        guard !Task.isCancelled, let app = MenuBarAccess.apps(qaOnly: true).first else { return MenuBarReadout() }
        if let known = bindings[id], !known.isEmpty {
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
                .map { LayoutApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier!, name: "macOS") }
            let task = Task.detached { MenuBarAccess.readBindings(known, app: app, screens: screens, agent: agent) }
            let readout = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled else { return MenuBarReadout() }
            if let owner, let length = owner.controllers[id]?.statusItem.length,
               let padding = hostPadding, readout.icons.count == 1, let icon = readout.icons.first,
               padding.fits(icon.width, length: length),
               !known.contains(where: \.requiresUniqueWidth) ||
                owner.controllers.values.filter({ padding.fits(icon.width, length: $0.statusItem.length) }).count == 1 {
                return readout
            }
        }
        await resolveOwnItems(ids: [id])
        guard !Task.isCancelled else { return MenuBarReadout() }
        return await read(apps: [app], screens: screens)
    }

    /// Bind only uniquely identifiable visible widths. Reading a layout must
    /// never change a width, click an icon, or write a placement preference.
    /// Identical anonymous dividers stay anonymous and remain in the reference.
    func resolveOwnItems(ids: Set<UUID>? = nil) async {
        guard MenuBarAccess.isTrusted, !resolving, !Task.isCancelled, let owner else { return }
        resolving = true
        defer { resolving = false }
        let generation = bindingGeneration
        let lengths = owner.controllers.mapValues { Double($0.statusItem.length) }
        let apps = MenuBarAccess.apps(qaOnly: true)
        let screens = Array(MenuBarAccess.screens().prefix(1))
        guard let app = apps.first, let screen = screens.first,
              Set(owner.configuration.items.map(\.id)) == Set(lengths.keys) else { return }
        let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
            .map { LayoutApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier!, name: "macOS") }
        let task = Task.detached { MenuBarAccess.read(apps: apps, screens: screens, agent: agent, bindings: []) }
        let raw = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        guard generation == bindingGeneration, !Task.isCancelled,
              lengths == owner.controllers.mapValues({ Double($0.statusItem.length) }) else { return }
        // The read is already confined to the own app. Keep the PID check at
        // this boundary too; never infer ownership from a host width or order.
        let own = raw.icons.filter { raw.targets[$0.id]?.app.pid == app.pid }
        let resolution = OwnMenuBarMatching.resolve(lengths: lengths, icons: own,
            bundleID: app.bundleID, displayID: screen.display.id,
            expectedPadding: lengths == calibratedLengths ? nil : hostPadding)
        if let padding = resolution.padding {
            hostPadding = padding
            calibratedLengths = lengths
        }
        bindings = bindings.filter { id, values in
            guard let match = resolution.matches[id], let target = raw.targets[match] else { return false }
            return values.contains { CFEqual(target.element, $0.element) }
        }
        for item in owner.configuration.items where ids == nil || ids!.contains(item.id) {
            guard bindings[item.id] == nil, let match = resolution.matches[item.id],
                  let target = raw.targets[match] else { continue }
            let expectedID = OwnMenuBarMatching.identifier(for: item.id)
            bindings[item.id] = [OwnMenuBarBinding(element: target.element, identifier: expectedID,
                label: "\(item.kind.title) \(owner.number(for: item.id))", requiresUniqueWidth: target.identifier.isEmpty)]
        }
    }
}
