import AppKit
import ServiceManagement
import SpacersCore
import SpaceBarUpdates
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UpdateHost {
    private(set) var configuration = Configuration()
    private(set) var controllers: [UUID: StatusItemController] = [:]
    private(set) var store = ConfigurationStore.standard
    private var management: ManagementWindow?
    private var loadFailed = false
    lazy var menuGeometry = MenuBarGeometry(owner: self)
    lazy var flexCoordinator = FlexSpacerCoordinator(owner: self)
    lazy var layoutManager = LayoutManager(owner: self)
    lazy var updateCoordinator = UpdateCoordinator(owner: self)
    var updateBlockingReason: String? {
        UpdatePolicy.blockingReason(layoutBusy: layoutManager.isBusy, previewing: isPreviewing,
            resizing: false, saveFailed: saveError != nil || startupError != nil)
    }
    var updateInstallBlockingReason: String? {
        UpdatePolicy.blockingReason(layoutBusy: layoutManager.isBusy, previewing: isPreviewing,
            resizing: flexCoordinator.isAdjusting, saveFailed: saveError != nil || startupError != nil)
    }
    func updateStateDidChange() { refreshFeatureUI() }
    func stopForUpdate() { flexCoordinator.stopMonitoring() }
    private var applyingSnapshot = false
    var terminationRequested = false
    private(set) var startupError: String?
    private(set) var previewingID: UUID?
    private var previewingFlexWidth: Double?
    private(set) var isShowingAll = false
    private(set) var previewingDividerDimension: ItemDimension?
    var previewingDividers: Bool { previewingDividerDimension != nil }
    private(set) var saveError: String?
    var isUITest: Bool { Bundle.main.bundleIdentifier?.hasSuffix(".UITests") == true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isUITest {
            // Even an accidental plain launch of the QA bundle is isolated.
            store = ConfigurationStore(url: ConfigurationStore.standard.url.deletingLastPathComponent()
                .appendingPathComponent("QA/configuration.json"))
            if let index = CommandLine.arguments.firstIndex(of: "--test-store"),
               CommandLine.arguments.indices.contains(index + 1) {
                store = ConfigurationStore(url: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
        }
        installApplicationMenu()
        var firstLaunch = false
        do {
            if let saved = try store.load() {
                configuration = saved
            } else {
                firstLaunch = true
                configuration = Configuration(items: [ItemConfiguration(kind: .divider)])
                try store.save(configuration)
            }
        } catch {
            loadFailed = true
            startupError = "Your saved items could not be loaded. The file has been kept unchanged.\n\(error.localizedDescription)"
        }
        for item in configuration.items { controllers[item.id] = StatusItemController(configuration: item, owner: self) }
        flexCoordinator.configurationChanged()
        if firstLaunch || configuration.items.isEmpty || startupError != nil { showManagement() }
        if isUITest, CommandLine.arguments.contains("--smoke-test") {
            Task { await self.runSmokeTest() }
        }
        if isUITest, CommandLine.arguments.contains("--test-login-roundtrip") {
            DispatchQueue.main.async { self.runLoginProbe() }
        }
        if isUITest, CommandLine.arguments.contains("--feature-probe") {
            Task { await self.runFeatureProbe() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManagement()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        flexCoordinator.stopMonitoring()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if updateCoordinator.installing, updateInstallBlockingReason != nil {
            return .terminateCancel
        }
        if layoutManager.isBusy {
            terminationRequested = true
            layoutManager.stop()
            return .terminateLater
        }
        // Drop the temporary Dock tile before quitting as well as on window close.
        sender.setActivationPolicy(.accessory)
        return .terminateNow
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        for controller in controllers.values { controller.update(controller.configuration) }
        flexCoordinator.configurationChanged()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        management?.refresh()
        flexCoordinator.refreshAvailableRoom()
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addAction("Manage Items…", key: ",") { [weak self] in self?.showManagement() }
        appMenu.addAction("Check for Updates…") { [weak self] in self?.updateCoordinator.check() }
        appMenu.addAction("Stop Layout Restore (Experimental)", key: ".") { [weak self] in self?.layoutManager.stop() }
        appMenu.addItem(.separator())
        appMenu.addAction("Quit SpaceBar", key: "q") { NSApp.terminate(nil) }
        let root = NSMenuItem()
        root.submenu = appMenu
        main.addItem(root)
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                        ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                        ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editRoot.submenu = edit
        main.addItem(editRoot)
        NSApp.mainMenu = main
    }

    func populate(_ menu: NSMenu, for id: UUID) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        guard let item = configuration.items.first(where: { $0.id == id }) else { return }
        menu.addNote("\(item.kind.title) \(number(for: id))")
        let controlItem = NSMenuItem()
        if item.kind == .spacer {
            controlItem.view = MenuDimensionView(item: item, dimension: .width, owner: self)
        } else if item.kind == .divider {
            controlItem.view = MenuMasterDividerView(dimension: .height, owner: self)
        } else {
            let holder = NSView(frame: NSRect(x: 0, y: 0, width: 510, height: 175))
            let row = FlexSpacerRow(item: item, owner: self)
            row.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 18),
                row.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -18),
                row.centerYAnchor.constraint(equalTo: holder.centerYAnchor)
            ])
            controlItem.view = holder
        }
        menu.addItem(controlItem)
        menu.addAction("Show Item Number", state: item.isHighlighted ? .on : .off) { [weak self] in
            self?.toggleHighlight(id)
        }
        menu.addAction(allItemsHighlighted ? "Hide All" : "Show All") { [weak self] in
            self?.toggleAllHighlights()
        }
        menu.addItem(.separator())
        menu.addAction("Add Spacer") { [weak self] in self?.add(.spacer) }
        menu.addAction("Add Divider") { [weak self] in self?.add(.divider) }
        let addFlex = menu.addAction("Add Flex Spacer") { [weak self] in self?.add(.flexSpacer) }
        addFlex.isEnabled = !configuration.items.contains { $0.kind == .flexSpacer }
        menu.addItem(.separator())
        menu.addAction("Remove This \(item.kind.title)") { [weak self] in self?.remove(id) }
        menu.addItem(.separator())
        menu.addNote(saveStatus)
        addLoginAction(to: menu)
        menu.addAction("Manage Items…") { [weak self] in self?.showManagement() }
        let updates = menu.addAction("Check for Updates…") { [weak self] in self?.updateCoordinator.check() }
        updates.isEnabled = updateCoordinator.canCheck
        menu.addAction("Export Settings…") { [weak self] in self?.exportSettings() }
        menu.addAction("Save Menu Bar Layout… (Experimental)") { [weak self] in self?.layoutManager.saveCurrent() }
        let restore = NSMenuItem(title: "Restore Menu Bar Layout (Experimental)", action: nil, keyEquivalent: "")
        let savedLayouts = layoutManager.library.layouts
        if !savedLayouts.isEmpty {
            let choices = NSMenu()
            for layout in savedLayouts.reversed() {
                choices.addAction(layout.name) { [weak self] in self?.layoutManager.restore(layout.id) }
            }
            restore.submenu = choices
        }
        restore.isEnabled = !savedLayouts.isEmpty && !layoutManager.isBusy && layoutManager.libraryError == nil && !flexCoordinator.isAdjusting
        menu.addItem(restore)
        menu.addNote("Hold ⌘ and drag to arrange")
        menu.addItem(.separator())
        menu.addAction("Quit SpaceBar", key: "q") { NSApp.terminate(nil) }
    }

    func addLoginAction(to menu: NSMenu) {
        let status = SMAppService.mainApp.status
        let title = status == .requiresApproval ? "Launch at Login — Approval Needed" :
            (status == .notFound ? "Enable Launch at Login…" : "Launch at Login")
        menu.addAction(title,
                       state: status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)) { [weak self] in
            self?.toggleLogin()
        }
        if status == .requiresApproval {
            menu.addAction("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
        }
        if status == .notFound {
            menu.addAction("Open Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
        }
    }

    var loginTitle: String {
        switch SMAppService.mainApp.status {
        case .enabled: "Launch at Login: On"
        case .requiresApproval: "Launch at Login: Approval Needed"
        case .notFound: "Launch at Login…"
        default: "Launch at Login: Off"
        }
    }

    var saveStatus: String {
        if startupError != nil { return "Saved settings need attention" }
        if isPreviewing { return "Previewing — saves when you release" }
        if saveError != nil { return "Change could not be saved" }
        return "Spacers saved"
    }

    var allItemsHighlighted: Bool {
        isShowingAll
    }

    func number(for id: UUID) -> Int { (configuration.items.firstIndex { $0.id == id } ?? 0) + 1 }

    var isPreviewing: Bool { previewingID != nil || previewingDividers }

    var commonDividerOpacity: Double? { commonDividerValue(.opacity) }
    var commonDividerHeight: Double? { commonDividerValue(.height) }

    func commonDividerValue(_ dimension: ItemDimension) -> Double? {
        let dividers = configuration.items.filter { $0.kind == .divider }
        guard let value = dividers.first?[dimension],
              dividers.allSatisfy({ abs($0[dimension] - value) < 0.000001 }) else { return nil }
        return value
    }

    func toggleLogin() {
        guard !isUITest else { return }
        do {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval: try SMAppService.mainApp.unregister()
            default: try SMAppService.mainApp.register()
            }
            management?.refresh()
            if SMAppService.mainApp.status == .requiresApproval {
                let alert = NSAlert()
                alert.messageText = "Allow SpaceBar at login"
                alert.informativeText = "macOS needs your approval in System Settings → General → Login Items."
                alert.addButton(withTitle: "Open Login Items")
                alert.addButton(withTitle: "Later")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "macOS could not change login startup."
            alert.informativeText = "Move SpaceBar to Applications and try again. You can also add it manually in System Settings → General → Login Items → Open at Login, using the + button.\n\n\(error.localizedDescription)"
            alert.addButton(withTitle: "Open Login Items")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { SMAppService.openSystemSettingsLoginItems() }
        }
    }

    @discardableResult
    func commit(_ next: Configuration) -> Bool {
        guard !layoutManager.isBusy || applyingSnapshot else { return false }
        guard !loadFailed else {
            showError("The saved file needs attention.", detail: "Open the settings folder from Manage Items, keep a copy, then repair or move configuration.json and reopen the app. Your original file has not been overwritten.")
            return false
        }
        do {
            // Save first; a failed disk write never silently changes the running items.
            try store.save(next)
            configuration = next
            previewingID = nil
            previewingFlexWidth = nil
            previewingDividerDimension = nil
            saveError = nil
            flexCoordinator.configurationChanged()
            return true
        } catch {
            saveError = error.localizedDescription
            management?.refresh()
            showError("Your change could not be saved.", detail: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func add(_ kind: ItemKind) -> UUID? {
        if kind == .flexSpacer && configuration.items.contains(where: { $0.kind == .flexSpacer }) { return nil }
        var item = ItemConfiguration(kind: kind)
        if kind == .divider, let opacity = commonDividerOpacity { item.opacity = opacity }
        if kind == .divider, let height = commonDividerHeight { item.height = height }
        item.isHighlighted = false
        var next = configuration
        if kind == .flexSpacer { next.version = 2 }
        next.items.append(item)
        guard commit(next) else { return nil }
        controllers[item.id] = StatusItemController(configuration: item, owner: self)
        management?.refresh()
        return item.id
    }

    func set(_ dimension: ItemDimension, value: Double, for id: UUID) {
        guard var item = configuration.items.first(where: { $0.id == id }) else { return }
        item[dimension] = value
        if !update(item) { cancelPreview(for: id) }
    }

    func preview(_ dimension: ItemDimension, value: Double, for id: UUID) {
        guard !loadFailed, !layoutManager.isBusy, var item = configuration.items.first(where: { $0.id == id }) else { return }
        if previewingDividers { cancelDividerPreview() }
        if let previous = previewingID, previous != id { cancelPreview(for: previous) }
        item[dimension] = value
        previewingID = id
        controllers[id]?.update(item)
        management?.refreshSaveStatus()
    }

    func cancelPreview(for id: UUID) {
        guard previewingID == id else { return }
        let originalFlexWidth = previewingFlexWidth
        previewingID = nil
        previewingFlexWidth = nil
        if let item = configuration.items.first(where: { $0.id == id }) { controllers[id]?.update(item) }
        if let originalFlexWidth { controllers[id]?.applyFlexWidth(originalFlexWidth) }
        management?.refresh()
    }

    func previewDividers(_ dimension: ItemDimension, value: Double) {
        guard !loadFailed, !layoutManager.isBusy, [.height, .opacity].contains(dimension), dimension.range.contains(value),
              configuration.items.contains(where: { $0.kind == .divider }) else { return }
        if let id = previewingID { cancelPreview(for: id) }
        if let previous = previewingDividerDimension, previous != dimension { cancelDividerPreview() }
        previewingDividerDimension = dimension
        for var item in configuration.items where item.kind == .divider {
            item[dimension] = value
            controllers[item.id]?.update(item)
        }
        management?.refreshSaveStatus()
    }

    func cancelDividerPreview() {
        guard previewingDividers else { return }
        previewingDividerDimension = nil
        for item in configuration.items where item.kind == .divider { controllers[item.id]?.update(item) }
        management?.refresh()
    }

    @discardableResult
    func setDividers(_ dimension: ItemDimension, value: Double) -> Bool {
        guard [.height, .opacity].contains(dimension), value.isFinite, dimension.range.contains(value),
              configuration.items.contains(where: { $0.kind == .divider }) else { return false }
        var next = configuration
        for index in next.items.indices where next.items[index].kind == .divider {
            next.items[index][dimension] = value
        }
        guard commit(next) else {
            cancelDividerPreview()
            return false
        }
        for item in next.items where item.kind == .divider { controllers[item.id]?.update(item) }
        management?.refresh()
        return true
    }

    func toggleHighlight(_ id: UUID) {
        guard var item = configuration.items.first(where: { $0.id == id }) else { return }
        item.isHighlighted.toggle()
        _ = update(item)
    }

    func toggleAllHighlights() {
        isShowingAll.toggle()
        // Identification is temporary and never writes width, opacity or IDs.
        for controller in controllers.values { controller.refreshAppearance() }
        management?.refresh()
    }

    @discardableResult
    func update(_ item: ItemConfiguration) -> Bool {
        guard let index = configuration.items.firstIndex(where: { $0.id == item.id }) else { return false }
        var next = configuration
        next.items[index] = item
        guard commit(next) else { return false }
        controllers[item.id]?.update(item)
        management?.refresh()
        return true
    }

    func remove(_ id: UUID) {
        var next = configuration
        next.items.removeAll { $0.id == id }
        guard commit(next) else { return }
        controllers.removeValue(forKey: id)?.remove()
        // Row numbers can shift after a removal; update images on the same items.
        for item in configuration.items { controllers[item.id]?.update(item) }
        management?.refresh()
        if configuration.items.isEmpty { showManagement() }
    }

    func showManagement() {
        if management == nil { management = ManagementWindow(owner: self) }
        NSApp.setActivationPolicy(.regular)
        management?.refresh()
        management?.showWindow(nil)
        management?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        flexCoordinator.refreshAvailableRoom()
    }

    var isManagementVisible: Bool { management?.window?.isVisible == true }

    func managementWindowDidClose() {
        if let id = previewingID { cancelPreview(for: id) }
        cancelDividerPreview()
        isShowingAll = false
        if configuration.items.contains(where: \.isHighlighted) {
            var next = configuration
            for index in next.items.indices { next.items[index].isHighlighted = false }
            if commit(next) {
                for item in next.items { controllers[item.id]?.update(item) }
            }
        }
        for controller in controllers.values { controller.refreshAppearance() }
        NSApp.setActivationPolicy(.accessory)
    }

    func refreshFeatureUI() { management?.refresh() }

    func toggleFlex(_ id: UUID) {
        guard var item = configuration.items.first(where: { $0.id == id }), item.kind == .flexSpacer else { return }
        if item.flex?.isEnabled != true && !MenuBarAccess.isTrusted { layoutManager.explainAccess(); return }
        if item.flex?.isEnabled == true { item.width = controllers[id].map { Double($0.statusItem.length) } ?? item.width }
        item.flex?.isEnabled.toggle()
        _ = update(item)
    }

    func arrangeFlex(_ id: UUID) {
        guard var item = configuration.items.first(where: { $0.id == id }), item.kind == .flexSpacer else { return }
        item.flex?.isEnabled = false; item.width = 24; item.isHighlighted = true
        // update saves first and then applies the native width. Refresh the
        // paused status after the shrink, rather than reporting the old length.
        if update(item) { flexCoordinator.configurationChanged() }
    }

    private func flexLimitWidth(_ item: ItemConfiguration, minimum: Double, maximum: Double,
                                sizingFromMinimum: Bool) -> Double {
        if item.flex?.isEnabled != true && sizingFromMinimum { return minimum }
        let currentWidth = previewingID == item.id ? previewingFlexWidth : nil
        let liveWidth = controllers[item.id].map { Double($0.statusItem.length) }
        return min(maximum, max(minimum, currentWidth ?? liveWidth ?? item.width))
    }

    func previewFlexLimits(_ id: UUID, minimum: Double, maximum: Double, sizingFromMinimum: Bool) {
        guard !loadFailed, !layoutManager.isBusy,
              let item = configuration.items.first(where: { $0.id == id }), item.kind == .flexSpacer,
              minimum.isFinite, maximum.isFinite, (6...3000).contains(minimum),
              (minimum...3000).contains(maximum) else { return }
        if let previous = previewingID, previous != id { cancelPreview(for: previous) }
        if previewingID != id { previewingFlexWidth = controllers[id].map { Double($0.statusItem.length) } }
        // Tracking changes the labels only. Apply one checked size on release;
        // continuous large native resizes can cause macOS to hide/reorder icons.
        previewingID = id
        management?.refreshSaveStatus()
    }

    func setFlexLimits(_ id: UUID, minimum: Double, maximum: Double, sizingFromMinimum: Bool = true) async {
        guard var item = configuration.items.first(where: { $0.id == id }), item.kind == .flexSpacer else { return }
        guard minimum.isFinite, maximum.isFinite, (6...3000).contains(minimum),
              (minimum...3000).contains(maximum) else { cancelPreview(for: id); return }
        let original = item
        let originalWidth = controllers[id].map { Double($0.statusItem.length) } ?? item.width
        let isCentering = item.flex?.isEnabled == true
        let lower = isCentering || sizingFromMinimum ? minimum : 6
        let width = flexLimitWidth(item, minimum: lower, maximum: maximum, sizingFromMinimum: sizingFromMinimum)
        guard await flexCoordinator.resizeSafely(id, to: width),
              configuration.items.first(where: { $0.id == id }) == original else {
            cancelPreview(for: id); return
        }
        item.width = width
        if isCentering { item.flex?.minimumGap = minimum }
        // Preserve the independently chosen auto floor when sizing a paused item.
        // Keep the legacy field valid for older builds without using it as a floor.
        let legacyMinimum = item.flex?.minimumWidth ?? 6
        item.flex?.minimumWidth = min(legacyMinimum, maximum)
        item.flex?.maximumWidth = maximum
        if let gap = item.flex?.minimumGap { item.flex?.minimumGap = min(gap, maximum) }
        if !update(item) {
            controllers[id]?.applyFlexWidth(originalWidth)
            cancelPreview(for: id)
        }
    }

    @discardableResult
    func applySavedConfiguration(_ saved: Configuration) -> Bool {
        // Reuse retained UUIDs and NSStatusItems. Only items explicitly added or
        // removed by the chosen snapshot need to be created or removed.
        applyingSnapshot = true
        defer { applyingSnapshot = false }
        guard commit(saved) else { return false }
        let wanted = Set(saved.items.map(\.id))
        for id in Array(controllers.keys) where !wanted.contains(id) { controllers.removeValue(forKey: id)?.remove() }
        for item in saved.items {
            if let controller = controllers[item.id] {
                controller.update(item)
                if item.kind == .flexSpacer { controller.applyFlexWidth(item.width) }
            }
            else { controllers[item.id] = StatusItemController(configuration: item, owner: self) }
        }
        management?.refresh()
        return true
    }

    func closeManagement() { management?.close() }

    func exportSettings(to url: URL) throws {
        guard !loadFailed else { throw CocoaError(.fileReadCorruptFile) }
        try ConfigurationStore(url: url).save(configuration)
    }

    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SpaceBar Settings.json"
        panel.title = "Export Settings"
        panel.message = "Save spacer and divider settings. macOS manages their menu bar positions separately."
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try exportSettings(to: url) }
        catch { showError("Settings could not be exported.", detail: error.localizedDescription) }
    }

    func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
