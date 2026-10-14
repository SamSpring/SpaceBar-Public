import AppKit
import SpacersCore

@MainActor
final class LayoutManager {
    weak var owner: AppDelegate?
    private(set) var library = LayoutLibrary()
    private(set) var libraryError: String?
    private(set) var isBusy = false
    private(set) var status = "Experimental layouts are saved inside SpaceBar. Choose one below to try restoring it."
    private var operation: Task<Void, Never>?
    let store: LayoutStore

    init(owner: AppDelegate) {
        self.owner = owner
        store = LayoutStore(url: owner.store.url.deletingLastPathComponent().appendingPathComponent("layouts.json"))
        do { library = try store.load() }
        catch { libraryError = error.localizedDescription; status = "Saved layouts need attention. The original file is unchanged." }
    }

    func requestAccess() { MenuBarAccess.requestAccess(); owner?.refreshFeatureUI() }
    func explainAccess() {
        status = "This running copy does not have Accessibility access. Open its settings below. If SpaceBar is already on, remove its existing entry with −, then use + to add /Applications/SpaceBar.app again. Check that it is on, then try Save Layout."
        owner?.showManagement()
        owner?.refreshFeatureUI()
    }
    func stop() { operation?.cancel(); status = "Stopping…"; owner?.refreshFeatureUI() }

    func saveCurrent() {
        guard !isBusy, libraryError == nil, let owner, !owner.flexCoordinator.isAdjusting else { return }
        guard MenuBarAccess.isTrusted else { explainAccess(); return }
        let alert = NSAlert()
        alert.messageText = "Save Menu Bar Layout — Experimental"
        alert.informativeText = "Saves the main display’s visible icon order and SpaceBar settings. Only visible, identifiable icons can be restored; some need manual arranging."
        let name = NSTextField(string: "Layout \(library.layouts.count + 1)")
        name.frame = NSRect(x: 0, y: 0, width: 310, height: 24)
        alert.accessoryView = name; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120 else { owner.showError("Choose a layout name.", detail: "Use between 1 and 120 characters."); return }
        begin("Saving visible menu bar icons…")
        operation = Task { [weak self] in
            guard let self else { return }
            defer { finish() }
            do {
                let snapshot = try await capture(name: title)
                try Task.checkCancellation()
                var next = library; next.layouts.append(snapshot)
                try store.save(next); library = next
                status = "Saved “\(title)” in SpaceBar · \(snapshot.icons.count) visible icons. Choose it below to restore."
            } catch is CancellationError { status = "Save stopped. Existing layouts were kept." }
            catch { status = error.localizedDescription; owner.showError("Experimental layout could not be saved.", detail: status) }
        }
    }

    func delete(_ id: UUID) {
        guard !isBusy, libraryError == nil else { return }
        var next = library; next.layouts.removeAll { $0.id == id }
        do { try store.save(next); library = next; owner?.refreshFeatureUI() }
        catch { owner?.showError("Experimental layout could not be deleted.", detail: error.localizedDescription) }
    }

    func restore(_ id: UUID, qaProbe: Bool = false) {
        guard !isBusy, libraryError == nil, let owner, !owner.flexCoordinator.isAdjusting,
              let snapshot = library.layouts.first(where: { $0.id == id }) else { return }
        guard MenuBarAccess.isTrusted else { explainAccess(); return }
        guard MenuBarAccess.canPostEvents else { explainAccess(); return }
        if qaProbe && !(owner.isUITest && CommandLine.arguments.contains("--feature-probe")) { return }
        let alert = NSAlert()
        alert.messageText = "Restore “\(snapshot.name)”? — Experimental"
        alert.informativeText = "SpaceBar restores its saved settings and attempts to Command-drag visible, identifiable icons into their saved order; some need manual arranging. A recovery layout is saved first. Leave the mouse alone while it runs. Missing, ambiguous, locked, or hidden icons will be reported."
        alert.addButton(withTitle: "Restore"); alert.addButton(withTitle: "Cancel")
        if !qaProbe && alert.runModal() != .alertFirstButtonReturn { return }
        begin("Saving a recovery layout…")
        operation = Task { [weak self] in
            guard let self else { return }
            defer { finish() }
            do {
                let backup = try await capture(name: "Before Restore — \(Date().formatted(date: .abbreviated, time: .shortened))")
                try Task.checkCancellation()
                var next = library; next.layouts.append(backup)
                // Abort before changing anything if the recovery write fails.
                try store.save(next); library = next
                guard owner.applySavedConfiguration(snapshot.configuration) else { throw CocoaError(.fileWriteUnknown) }
                try await Task.sleep(for: .milliseconds(350))
                let screens = Array(MenuBarAccess.screens().prefix(1))
                let apps = MenuBarAccess.apps(qaOnly: owner.isUITest)
                await owner.menuGeometry.resolveOwnItems()
                let initial = await readIcons(apps: apps, screens: screens)
                var skipped: [String] = []
                var completed = 0
                let ordered = snapshot.icons.sorted { $0.displayID == $1.displayID ? $0.left > $1.left : $0.displayID < $1.displayID }
                for (index, saved) in ordered.enumerated() {
                    try Task.checkCancellation()
                    status = "Restoring \(index + 1) of \(ordered.count) · \(saved.appName)"; owner.refreshFeatureUI()
                    guard let screen = screens.first(where: { $0.display.id == saved.displayID }),
                          let previous = snapshot.displays.first(where: { $0.id == saved.displayID }),
                          abs(previous.width - screen.display.width) < 1, abs(previous.height - screen.display.height) < 1 else {
                        skipped.append("\(saved.title): display is missing or its resolution changed"); continue
                    }
                    let savedRight = snapshot.icons.filter { $0.displayID == saved.displayID && $0.left > saved.left }
                        .sorted { $0.left < $1.left }.first { LayoutMatching.match($0, in: initial) != nil }
                    let relevantIDs = Set([saved.bundleID, savedRight?.bundleID].compactMap { $0 })
                    let relevantApps = apps.filter { relevantIDs.contains($0.bundleID) }
                    let readout = await owner.menuGeometry.read(apps: relevantApps, screens: screens)
                    let live = readout.icons.filter { $0.bundleID != Bundle.main.bundleIdentifier || $0.identifier.hasPrefix("SpaceBar.Item.") }
                    try Task.checkCancellation()
                    guard let current = LayoutMatching.match(saved, in: live) else {
                        skipped.append("\(saved.title): missing, hidden, or ambiguous"); continue
                    }
                    let rect = globalRect(current, screen: screen)
                    let right = savedRight.flatMap { LayoutMatching.match($0, in: live) }
                    // Use a freshly read neighbor rather than blindly replaying a
                    // coordinate after icons have appeared or disappeared.
                    let targetX = right.map { screen.bounds.minX + $0.left - 2 } ??
                        (screen.bounds.minX + saved.left + saved.width / 2)
                    let destination = CGPoint(x: targetX, y: rect.midY)
                    let targetRect = CGRect(x: destination.x - 1, y: destination.y - 1, width: 3, height: 3)
                    if qaProbe { print("Restore QA \(saved.label): current \(current.left), saved \(saved.left), target \(targetX), right \(right?.left.description ?? "none")") }
                    if abs(current.left - saved.left) > 3 || right.map({ current.left >= $0.left }) == true {
                        guard let source = screen.usablePoint(in: rect), screen.usablePoint(in: targetRect) != nil else {
                            skipped.append("\(saved.title): drag point is behind the notch"); continue
                        }
                        do {
                            guard let target = readout.targets[current.id] else { throw LayoutOperationError.iconMoved }
                            try await MenuBarAccess.drag(from: source, to: destination, target: target)
                            try await Task.sleep(for: .milliseconds(250))
                            if saved.bundleID == Bundle.main.bundleIdentifier { await owner.menuGeometry.resolveOwnItems() }
                        } catch is CancellationError { throw CancellationError() }
                        catch LayoutOperationError.userInterrupted { throw LayoutOperationError.userInterrupted }
                        catch { skipped.append("\(saved.title): \(error.localizedDescription)"); continue }
                    }
                    let after = await readIcons(apps: relevantApps, screens: screens)
                    guard let verified = LayoutMatching.match(saved, in: after) else {
                        skipped.append("\(saved.title): could not verify after dragging"); continue
                    }
                    if let right, let neighbor = after.first(where: { $0.identityKey == right.identityKey && $0.displayID == right.displayID }),
                       verified.left >= neighbor.left {
                        skipped.append("\(saved.title): macOS did not allow this move")
                    } else { completed += 1 }
                }
                let final = await readIcons(apps: apps, screens: screens)
                let exact = snapshot.icons.filter { saved in
                    guard let icon = LayoutMatching.match(saved, in: final) else { return false }
                    return abs(icon.left - saved.left) <= 3
                }.count
                status = "Finished: \(completed) icons checked in order; \(exact) at saved positions; \(skipped.count) skipped."
                owner.refreshFeatureUI()
                if !skipped.isEmpty {
                    if qaProbe { print("QA restore skips: \(skipped)") }
                    else { owner.showError("Experimental restore: some icons need manual arranging.", detail: skipped.joined(separator: "\n") + "\n\nYour “Before Restore” layout is available below.") }
                }
            } catch is CancellationError { status = "Restore stopped. Changes already made remain; use the “Before Restore” layout to undo them." }
            catch {
                status = error.localizedDescription
                if qaProbe { print("QA restore error: \(status)") }
                else { owner.showError("Experimental layout restore stopped.", detail: status + "\nThe recovery layout and existing saved layouts were kept.") }
            }
        }
    }

    func view(_ id: UUID) {
        guard !isBusy, let snapshot = library.layouts.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "\(snapshot.name) — Experimental Layout"
        alert.informativeText = "Saved order, from left to right on the main display. Only visible, identifiable icons can be restored; some need manual arranging. Use this reference and SpaceBar’s item numbers to arrange them."
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 250))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false; text.isRichText = false
        text.font = .systemFont(ofSize: 12)
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.maxSize = NSSize(width: 460, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.string = snapshot.icons.sorted { $0.left < $1.left }.enumerated()
            .map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
        scroll.documentView = text
        alert.accessoryView = scroll; alert.addButton(withTitle: "Done")
        alert.runModal()
    }

    func capture(name: String) async throws -> MenuBarLayout {
        guard let owner, MenuBarAccess.isTrusted else { throw LayoutOperationError.accessRequired }
        let screens = Array(MenuBarAccess.screens().prefix(1))
        let apps = MenuBarAccess.apps(qaOnly: owner.isUITest)
        var icons: [LayoutIcon] = []
        // The host's AX tree can briefly lag newly created native items. Retry
        // only reads, with a bounded delay; never probe with width changes.
        for attempt in 0..<3 {
            try Task.checkCancellation()
            await owner.menuGeometry.resolveOwnItems()
            icons = await readIcons(apps: apps, screens: screens)
            if !icons.isEmpty { break }
            if attempt < 2 { try await Task.sleep(for: .milliseconds(250)) }
        }
        guard !icons.isEmpty else { throw LayoutOperationError.emptyCapture }
        var configuration = owner.configuration
        for index in configuration.items.indices where configuration.items[index].kind == .flexSpacer {
            let item = configuration.items[index]
            configuration.items[index].width = owner.controllers[item.id].map { Double($0.statusItem.length) } ?? item.width
        }
        let snapshot = MenuBarLayout(name: name, configuration: configuration,
                                     displays: screens.map(\.display), icons: icons)
        try snapshot.validate()
        return snapshot
    }

    func addSnapshot(_ snapshot: MenuBarLayout) throws {
        guard libraryError == nil, !isBusy else { throw LayoutOperationError.libraryUnavailable }
        var next = library; next.layouts.append(snapshot)
        try store.save(next); library = next
        owner?.refreshFeatureUI()
    }

    private func readIcons(apps: [LayoutApp], screens: [LayoutScreen]) async -> [LayoutIcon] {
        guard let owner else { return [] }
        // Anonymous icons remain useful in the saved visual reference. Restore
        // separately refuses ambiguous identities instead of guessing.
        return await owner.menuGeometry.read(apps: apps, screens: screens).icons
    }
    private func globalRect(_ icon: LayoutIcon, screen: LayoutScreen) -> CGRect {
        CGRect(x: screen.bounds.minX + icon.left, y: screen.bounds.minY + icon.top, width: icon.width, height: icon.height)
    }
    private func begin(_ message: String) { isBusy = true; status = message; owner?.refreshFeatureUI() }
    private func finish() {
        isBusy = false; operation = nil
        owner?.flexCoordinator.configurationChanged()
        owner?.refreshFeatureUI()
        if owner?.terminationRequested == true { NSApp.reply(toApplicationShouldTerminate: true) }
    }
}

@MainActor
final class LayoutSection: NSStackView {
    private weak var owner: AppDelegate?
    private let status = NSTextField(wrappingLabelWithString: "")
    private let save = NSButton(title: "Save Layout… (Experimental)", target: nil, action: nil)
    private let access = NSButton(title: "Open Accessibility Settings…", target: nil, action: nil)
    private let accessState = NSTextField(labelWithString: "")
    private let stop = NSButton(title: "Stop", target: nil, action: nil)
    private let openFolder = NSButton(title: "Open Layouts Folder…", target: nil, action: nil)
    private let list = NSStackView()
    private var displayedIDs: [UUID] = []
    let restoreControls = NSStackView()
    private let choice = NSPopUpButton()
    private let restore = NSButton(title: "Restore Layout… (Experimental)", target: nil, action: nil)
    private var selectedID: UUID? { choice.selectedItem?.representedObject as? UUID }
    init(owner: AppDelegate) {
        self.owner = owner
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 8
        let title = NSTextField(labelWithString: "Menu Bar Layouts — Experimental"); title.font = .systemFont(ofSize: 14, weight: .semibold)
        addArrangedSubview(title)
        save.target = self; save.action = #selector(saveLayout)
        access.target = self; access.action = #selector(enableAccess)
        stop.target = self; stop.action = #selector(stopRestore)
        openFolder.target = self; openFolder.action = #selector(openLayoutsFolder)
        for button in [save, access, stop, openFolder] { button.bezelStyle = .rounded }
        accessState.font = .systemFont(ofSize: 11)
        accessState.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        accessState.lineBreakMode = .byTruncatingTail
        addArrangedSubview(NSStackView(views: [save, access, accessState, stop, openFolder]))
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        addArrangedSubview(status); status.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        let note = NSTextField(wrappingLabelWithString: "Experimental. Only visible, identifiable icons on the main display can be restored; some need manual arranging. Restoring is always your choice.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        addArrangedSubview(note); note.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 6
        addArrangedSubview(list); list.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        let selectedTitle = NSTextField(labelWithString: "Saved layout")
        selectedTitle.font = .systemFont(ofSize: 12)
        choice.setAccessibilityLabel("Saved menu bar layout")
        choice.menu = NSMenu()
        choice.setContentHuggingPriority(.defaultLow, for: .horizontal)
        choice.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        choice.toolTip = "Experimental layouts stay inside SpaceBar; choose one to try restoring. Some icons need manual arranging."
        choice.target = self; choice.action = #selector(selectionChanged)
        restore.target = self; restore.action = #selector(restoreSelected)
        restore.bezelStyle = .rounded
        restoreControls.spacing = 8; restoreControls.alignment = .centerY
        for view in [selectedTitle, choice, restore] { restoreControls.addArrangedSubview(view) }
    }
    required init?(coder: NSCoder) { fatalError("Not implemented") }
    func refresh() {
        guard let owner else { return }
        let manager = owner.layoutManager
        status.stringValue = manager.status
        accessState.stringValue = MenuBarAccess.isTrusted ? "✓ Access enabled" : "Access needed"
        accessState.toolTip = "Accessibility access is needed for layouts and flex growth."
        accessState.textColor = MenuBarAccess.isTrusted ? .systemGreen : .secondaryLabelColor
        access.toolTip = "Open macOS permission settings. SpaceBar never prompts automatically."
        access.isEnabled = !manager.isBusy
        save.isEnabled = !manager.isBusy && manager.libraryError == nil && owner.startupError == nil
        stop.isHidden = !manager.isBusy
        openFolder.isHidden = manager.libraryError == nil
        let ids = manager.library.layouts.map(\.id)
        if ids != displayedIDs || choice.numberOfItems == 0 {
            let previousSelection = selectedID
            let newestAdded = ids.last != displayedIDs.last && ids.count > displayedIDs.count
            displayedIDs = ids
            choice.removeAllItems()
            for layout in manager.library.layouts.reversed() {
                choice.menu?.addItem(NSMenuItem(title: layout.name, action: nil, keyEquivalent: ""))
                choice.lastItem?.representedObject = layout.id
                choice.lastItem?.toolTip = "\(layout.createdAt.formatted()) · \(layout.icons.count) visible icons"
            }
            if ids.isEmpty { choice.addItem(withTitle: "No saved layouts yet") }
            else { choice.selectItem(at: 0) }
            if !newestAdded, let previousSelection,
                    let index = choice.itemArray.firstIndex(where: { $0.representedObject as? UUID == previousSelection }) {
                choice.selectItem(at: index)
            }
            for view in list.arrangedSubviews { list.removeArrangedSubview(view); view.removeFromSuperview() }
            for layout in manager.library.layouts.reversed() {
                let row = LayoutRow(layout: layout, owner: owner)
                list.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            }
        }
        let canRestore = !manager.isBusy && manager.libraryError == nil && owner.startupError == nil && !owner.flexCoordinator.isAdjusting
        choice.isEnabled = canRestore && !ids.isEmpty
        restore.isEnabled = canRestore && selectedID != nil
        restore.toolTip = selectedID == nil ? "Save a layout first." : "Restore the selected layout. You'll confirm before any icons move."
        for row in list.arrangedSubviews.compactMap({ $0 as? LayoutRow }) { row.setEnabled(!manager.isBusy) }
    }
    @objc private func selectionChanged() { refresh() }
    @objc private func restoreSelected() { if let id = selectedID { owner?.layoutManager.restore(id) } }
    @objc private func saveLayout() { owner?.layoutManager.saveCurrent() }
    @objc private func enableAccess() { owner?.layoutManager.requestAccess() }
    @objc private func stopRestore() { owner?.layoutManager.stop() }
    @objc private func openLayoutsFolder() {
        guard let owner else { return }
        NSWorkspace.shared.open(owner.layoutManager.store.url.deletingLastPathComponent())
    }
}

@MainActor
private final class LayoutRow: NSStackView {
    private let id: UUID
    private weak var owner: AppDelegate?
    private let view = NSButton(title: "View", target: nil, action: nil)
    private let remove = NSButton()
    init(layout: MenuBarLayout, owner: AppDelegate) {
        id = layout.id; self.owner = owner
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .centerY; spacing = 8
        let label = NSTextField(labelWithString: layout.name)
        label.lineBreakMode = .byTruncatingTail; label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.toolTip = "\(layout.createdAt.formatted()) · \(layout.icons.count) visible icons"
        view.target = self; view.action = #selector(viewLayout); view.bezelStyle = .rounded
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete saved layout")
        remove.target = self; remove.action = #selector(deleteLayout); remove.bezelStyle = .rounded
        for view in [label, NSView(), view, remove] { addArrangedSubview(view) }
    }
    required init?(coder: NSCoder) { fatalError("Not implemented") }
    func setEnabled(_ enabled: Bool) { view.isEnabled = enabled; remove.isEnabled = enabled }
    @objc private func viewLayout() { owner?.layoutManager.view(id) }
    @objc private func deleteLayout() { owner?.layoutManager.delete(id) }
}
