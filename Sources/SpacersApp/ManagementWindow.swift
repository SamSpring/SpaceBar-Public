import AppKit
import ServiceManagement
import SpacersCore

@MainActor
final class ManagementWindow: NSWindowController, NSWindowDelegate {
    weak var coordinator: AppDelegate?
    private let content = TopAlignedStackView()
    private let dividerSection = NSStackView()
    private let spacerSection = NSStackView()
    private let flexSection = NSStackView()
    private let flexList = NSStackView()
    private var flexRows: [UUID: FlexSpacerRow] = [:]
    private let layouts: LayoutSection
    private let addFlex = NSButton(title: "Add Flex Spacer", target: nil, action: nil)
    private let dividerGrid = NSStackView()
    private let spacerList = NSStackView()
    private var spacerRows: [UUID: SpacerRow] = [:]
    private var dividerTiles: [UUID: DividerTile] = [:]
    private var displayedIDs: [UUID] = []
    private let login = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let approval = NSButton(title: "Open Login Items…", target: nil, action: nil)
    private let master = NSButton(title: "Show All", target: nil, action: nil)
    private let dividerHeight: MasterDividerControl
    private let dividerOpacity: MasterDividerControl
    private let saved = NSTextField(labelWithString: "")
    private let export = NSButton(title: "Export Settings…", target: nil, action: nil)
    private let updates = NSButton(title: "Check for Updates…", target: nil, action: nil)
    private let scroll = NSScrollView()
    private var firstRefresh = true

    init(owner: AppDelegate) {
        coordinator = owner
        layouts = LayoutSection(owner: owner)
        dividerHeight = MasterDividerControl(dimension: .height, owner: owner)
        dividerOpacity = MasterDividerControl(dimension: .opacity, owner: owner)
        let height = min(948, max(500, (NSScreen.main?.frame.height ?? 1000) - 32))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = owner.isUITest ? "SpaceBar — Test" : "SpaceBar"
        window.minSize = NSSize(width: 620, height: 500)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(root)
        if let view = window.contentView {
            NSLayoutConstraint.activate([
                root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
                root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
                root.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
                root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
            ])
        }
        let heading = NSTextField(labelWithString: "A little space in your menu bar.")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        root.addArrangedSubview(heading)
        let instructions = NSTextField(wrappingLabelWithString:
            "Hold ⌘ and drag to arrange. Click an item in the menu bar for its menu. Show its number to match it to this list, or use Show All for spacer numbers and fully visible dividers.")
        instructions.textColor = .secondaryLabelColor
        root.addArrangedSubview(instructions)
        instructions.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        master.target = self
        master.action = #selector(toggleAll)
        master.bezelStyle = .rounded
        master.toolTip = "Temporarily show spacer numbers and outlines, and dividers at full opacity. Closing Settings turns this off."
        addFlex.target = self; addFlex.action = #selector(addFlexSpacer)
        addFlex.bezelStyle = .rounded
        let add = NSStackView(views: [
            NSButton(title: "Add Spacer", target: self, action: #selector(addSpacer)),
            NSButton(title: "Add Divider", target: self, action: #selector(addDivider)),
            addFlex,
            NSView(), master
        ])
        add.spacing = 8
        root.addArrangedSubview(add)
        add.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 20
        content.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 8)
        content.translatesAutoresizingMaskIntoConstraints = false
        configureSection(dividerSection, title: "Dividers")
        for (title, control) in [("Height", dividerHeight), ("Opacity", dividerOpacity)] {
            let row = masterRow(title: title, control: control)
            dividerSection.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: dividerSection.widthAnchor).isActive = true
        }
        dividerGrid.orientation = .vertical
        dividerGrid.alignment = .leading
        dividerGrid.spacing = 8
        dividerSection.addArrangedSubview(dividerGrid)
        dividerGrid.widthAnchor.constraint(equalTo: dividerSection.widthAnchor).isActive = true
        configureSection(spacerSection, title: "Spacers")
        spacerList.orientation = .vertical
        spacerList.alignment = .leading
        spacerList.spacing = 6
        spacerSection.addArrangedSubview(spacerList)
        spacerList.widthAnchor.constraint(equalTo: spacerSection.widthAnchor).isActive = true
        configureSection(flexSection, title: "Flex Spacer")
        let flexNote = NSTextField(wrappingLabelWithString: "While paused, Width sizes the spacer on release. Center then adjusts in both directions as icons change, using a separate Minimum gap. Arrange shrinks it for ⌘-dragging. Accessibility is needed for growth and centering.")
        flexNote.font = .systemFont(ofSize: 11); flexNote.textColor = .secondaryLabelColor
        flexSection.addArrangedSubview(flexNote)
        flexNote.widthAnchor.constraint(equalTo: flexSection.widthAnchor).isActive = true
        flexList.orientation = .vertical; flexList.alignment = .leading; flexList.spacing = 8
        flexSection.addArrangedSubview(flexList)
        flexList.widthAnchor.constraint(equalTo: flexSection.widthAnchor).isActive = true

        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.documentView = content
        root.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Keep the chosen layout and Restore reachable when the items scroll.
        root.addArrangedSubview(layouts.restoreControls)
        layouts.restoreControls.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        saved.font = .systemFont(ofSize: 12)
        saved.toolTip = "Item settings save automatically. macOS remembers menu bar positions separately when it can."
        root.addArrangedSubview(saved)
        let note = NSTextField(wrappingLabelWithString:
            "Settings save automatically. Experimental layout snapshots are separate; restoring visible, identifiable icons needs Accessibility access, and some need manual arranging.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        root.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        login.target = self
        login.action = #selector(toggleLogin)
        approval.target = self
        approval.action = #selector(openLoginSettings)
        approval.bezelStyle = .rounded
        let loginRow = NSStackView(views: [login, approval])
        loginRow.spacing = 8
        root.addArrangedSubview(loginRow)
        export.target = self
        export.action = #selector(exportSettings)
        export.bezelStyle = .rounded
        updates.target = self
        updates.action = #selector(checkUpdates)
        updates.bezelStyle = .rounded
        updates.toolTip = owner.updateCoordinator.updateDescription
        let footer = NSStackView(views: [export, updates, NSView(), NSButton(title: "Quit", target: self, action: #selector(quitApp))])
        footer.spacing = 8
        root.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    private func configureSection(_ section: NSStackView, title: String) {
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        section.addArrangedSubview(label)
    }

    private func masterRow(title: String, control: MasterDividerControl) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let row = NSStackView(views: [label, control])
        row.distribution = .fill
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

    func windowWillClose(_ notification: Notification) { coordinator?.managementWindowDidClose() }

    func refresh() {
        guard let owner = coordinator else { return }
        let ids = owner.configuration.items.map(\.id)
        // Group the presentation only; keep configuration order and native identities.
        // Keep live spacer sliders in place unless items have been added or removed.
        if firstRefresh || displayedIDs != ids {
            firstRefresh = false
            displayedIDs = ids
            rebuildSections(owner)
        }
        for item in owner.configuration.items {
            let number = owner.number(for: item.id)
            spacerRows[item.id]?.refresh(item, number: number)
            flexRows[item.id]?.refresh(item, number: number)
            dividerTiles[item.id]?.refresh(item, number: number)
        }
        master.isEnabled = !ids.isEmpty && owner.startupError == nil && !owner.layoutManager.isBusy
        addFlex.isEnabled = !owner.configuration.items.contains { $0.kind == .flexSpacer } && !owner.layoutManager.isBusy && owner.startupError == nil
        master.title = owner.allItemsHighlighted ? "Hide All" : "Show All"
        let status = SMAppService.mainApp.status
        login.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        login.isEnabled = !owner.isUITest
        login.toolTip = owner.loginTitle
        approval.isHidden = status != .requiresApproval && status != .notFound
        dividerHeight.refresh()
        dividerOpacity.refresh()
        layouts.refresh()
        refreshSaveStatus()
    }

    private func rebuildSections(_ owner: AppDelegate) {
        for view in content.arrangedSubviews { content.removeArrangedSubview(view); view.removeFromSuperview() }
        for view in spacerList.arrangedSubviews { spacerList.removeArrangedSubview(view); view.removeFromSuperview() }
        for view in flexList.arrangedSubviews { flexList.removeArrangedSubview(view); view.removeFromSuperview() }
        // Detach tiles before discarding their old grid rows so they can be reused.
        for tile in dividerTiles.values { tile.removeFromSuperview() }
        for view in dividerGrid.arrangedSubviews { dividerGrid.removeArrangedSubview(view); view.removeFromSuperview() }
        let items = owner.configuration.items
        spacerRows = spacerRows.filter { key, _ in items.contains { $0.id == key && $0.kind == .spacer } }
        dividerTiles = dividerTiles.filter { key, _ in items.contains { $0.id == key && $0.kind == .divider } }
        flexRows = flexRows.filter { key, _ in items.contains { $0.id == key && $0.kind == .flexSpacer } }
        if let error = owner.startupError {
            let label = NSTextField(wrappingLabelWithString: error)
            label.textColor = .systemRed
            content.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -12).isActive = true
            content.addArrangedSubview(NSButton(title: "Open Settings Folder", target: self, action: #selector(openSettings)))
            return
        }
        for section in [dividerSection, flexSection, spacerSection, layouts] {
            content.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -12).isActive = true
        }
        let flexible = items.filter { $0.kind == .flexSpacer }
        if flexible.isEmpty { flexList.addArrangedSubview(emptyLabel("No flex spacer yet. Add one above.")) }
        for item in flexible {
            let row = flexRows[item.id] ?? FlexSpacerRow(item: item, owner: owner)
            flexRows[item.id] = row
            flexList.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: flexList.widthAnchor).isActive = true
        }
        let dividers = items.filter { $0.kind == .divider }
        if dividers.isEmpty { dividerGrid.addArrangedSubview(emptyLabel("No dividers yet. Add one above.")) }
        for start in stride(from: 0, to: dividers.count, by: 3) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 12
            for column in 0..<3 {
                let index = start + column
                if index < dividers.count {
                    let item = dividers[index]
                    let tile = dividerTiles[item.id] ?? DividerTile(item: item, owner: owner)
                    dividerTiles[item.id] = tile
                    row.addArrangedSubview(tile)
                } else {
                    row.addArrangedSubview(NSView())
                }
            }
            dividerGrid.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: dividerGrid.widthAnchor).isActive = true
        }
        let spacers = items.filter { $0.kind == .spacer }
        if spacers.isEmpty { spacerList.addArrangedSubview(emptyLabel("No spacers yet. Add one above.")) }
        for item in spacers {
            let row = spacerRows[item.id] ?? SpacerRow(item: item, owner: owner)
            spacerRows[item.id] = row
            spacerList.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: spacerList.widthAnchor).isActive = true
        }
    }

    private func emptyLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    func refreshSaveStatus() {
        guard let owner = coordinator else { return }
        let failed = owner.startupError != nil || owner.saveError != nil
        saved.stringValue = owner.updateCoordinator.waitingMessage ?? "\(failed ? "⚠" : (owner.isPreviewing ? "◌" : "✓"))  \(owner.saveStatus)"
        saved.textColor = failed ? .systemRed : (owner.isPreviewing ? .secondaryLabelColor : .systemGreen)
        export.isEnabled = !failed && !owner.isPreviewing
        updates.isEnabled = owner.updateCoordinator.canCheck
    }

    @objc private func addSpacer() { coordinator?.add(.spacer) }
    @objc private func addDivider() { coordinator?.add(.divider) }
    @objc private func addFlexSpacer() { coordinator?.add(.flexSpacer) }
    @objc private func toggleAll() { coordinator?.toggleAllHighlights() }
    @objc private func toggleLogin() { coordinator?.toggleLogin() }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func exportSettings() { coordinator?.exportSettings() }
    @objc private func checkUpdates() { coordinator?.updateCoordinator.check() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func openSettings() {
        guard let owner = coordinator else { return }
        NSWorkspace.shared.open(owner.store.url.deletingLastPathComponent())
    }
}

@MainActor
private final class SpacerRow: NSStackView {
    private let id: UUID
    private weak var coordinator: AppDelegate?
    private let control: DimensionControl
    private let title = NSTextField(labelWithString: "")
    private let visibility = NSButton(title: "Show", target: nil, action: nil)
    private let remove = NSButton()

    init(item: ItemConfiguration, owner: AppDelegate) {
        precondition(item.kind == .spacer)
        id = item.id
        coordinator = owner
        control = DimensionControl(item: item, dimension: .width, owner: owner)
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 12
        distribution = .fill
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.widthAnchor.constraint(equalToConstant: 82).isActive = true
        visibility.target = self
        visibility.action = #selector(toggleVisibility)
        visibility.bezelStyle = .rounded
        visibility.widthAnchor.constraint(equalToConstant: 64).isActive = true
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove spacer")
        remove.bezelStyle = .rounded
        remove.target = self
        remove.action = #selector(removeItem)
        remove.widthAnchor.constraint(equalToConstant: 32).isActive = true
        for view in [title, control, visibility, remove] { addArrangedSubview(view) }
        heightAnchor.constraint(equalToConstant: 38).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    func refresh(_ item: ItemConfiguration, number: Int) {
        control.refresh(item)
        title.stringValue = "Spacer \(number)"
        visibility.title = item.isHighlighted ? "Hide" : "Show"
        visibility.state = item.isHighlighted ? .on : .off
        visibility.toolTip = "\(visibility.title) spacer \(number) in the menu bar"
        visibility.setAccessibilityLabel("\(visibility.title) number for spacer \(number)")
        remove.setAccessibilityLabel("Remove spacer \(number)")
    }

    @objc private func toggleVisibility() { coordinator?.toggleHighlight(id) }
    @objc private func removeItem() { coordinator?.remove(id) }
}

@MainActor
private final class DividerTile: NSStackView {
    private let id: UUID
    private weak var coordinator: AppDelegate?
    private let visibility = NSButton(title: "", target: nil, action: nil)
    private let remove = NSButton()

    init(item: ItemConfiguration, owner: AppDelegate) {
        id = item.id
        coordinator = owner
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        distribution = .fill
        spacing = 6
        visibility.target = self
        visibility.action = #selector(toggleVisibility)
        visibility.bezelStyle = .rounded
        visibility.setContentHuggingPriority(.defaultLow, for: .horizontal)
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove divider")
        remove.bezelStyle = .rounded
        remove.target = self
        remove.action = #selector(removeItem)
        remove.widthAnchor.constraint(equalToConstant: 32).isActive = true
        addArrangedSubview(visibility)
        addArrangedSubview(remove)
        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    func refresh(_ item: ItemConfiguration, number: Int) {
        visibility.title = "\(item.isHighlighted ? "Hide" : "Show") Divider \(number)"
        visibility.state = item.isHighlighted ? .on : .off
        visibility.setAccessibilityLabel("\(item.isHighlighted ? "Hide" : "Show") number for divider \(number)")
        visibility.toolTip = "Identify divider \(number) in the menu bar without changing its position"
        remove.setAccessibilityLabel("Remove divider \(number)")
        remove.toolTip = "Remove divider \(number)"
    }

    @objc private func toggleVisibility() { coordinator?.toggleHighlight(id) }
    @objc private func removeItem() { coordinator?.remove(id) }
}

@MainActor
private final class TopAlignedStackView: NSStackView {
    override var isFlipped: Bool { true }
}
