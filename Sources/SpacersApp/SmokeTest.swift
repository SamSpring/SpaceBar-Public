import AppKit
import ServiceManagement
import SpacersCore

@MainActor
extension AppDelegate {
    func runLoginProbe() {
        precondition(isUITest)
        let service = SMAppService.mainApp
        let before = service.status
        print("Login status before: \(before.rawValue)")
        guard before == .notFound || before == .notRegistered else {
            print("SKIP: Existing QA registration kept unchanged.")
            NSApp.terminate(nil)
            return
        }
        do {
            try service.register()
            print("Registration succeeded; status: \(service.status.rawValue)")
        } catch {
            print("Registration error: \(error as NSError)")
        }
        do {
            try service.unregister()
            print("QA entry unregistered; status: \(service.status.rawValue)")
        } catch {
            print("Unregister result: \(error as NSError); status: \(service.status.rawValue)")
        }
        NSApp.terminate(nil)
    }

    func runSmokeTest() async {
        do {
            try check(isUITest)
            try await Task.sleep(for: .milliseconds(300))
            let divider = add(.divider)!
            let spacer = add(.spacer)!
            let native = controllers.mapValues(\.statusItem)
            set(.width, value: 64, for: spacer)
            try check(controllers[spacer]!.statusItem === native[spacer])
            try check(controllers[spacer]!.statusItem.autosaveName == "Item.\(spacer.uuidString)")
            let bytes = try Data(contentsOf: store.url)
            preview(.width, value: 50, for: spacer)
            try check(controllers[spacer]!.statusItem.length == 50)
            try assertTrue(equalFile(store.url, bytes))
            cancelPreview(for: spacer)
            try check(controllers[spacer]!.statusItem.length == 64)
            try check(setDividers(.opacity, value: 0.55))
            try check(setDividers(.height, value: 20))
            let beforeShow = configuration
            let showBytes = try Data(contentsOf: store.url)
            let dividerImage = controllers[divider]!.statusItem.button!.image!.tiffRepresentation!
            toggleHighlight(divider)
            try check(controllers[divider]!.displaysNumber)
            let withIndividual = configuration
            toggleAllHighlights()
            try check(isShowingAll && controllers[spacer]!.displaysNumber)
            try check(!controllers[divider]!.displaysNumber && controllers[divider]!.displayedOpacity == 1)
            try check(configuration == withIndividual)
            try check(controllers.allSatisfy { $0.value.statusItem === native[$0.key] })
            toggleAllHighlights()
            try check(!isShowingAll && controllers[divider]!.displaysNumber)
            try check(controllers[divider]!.displayedOpacity == 0.55)
            toggleHighlight(divider)
            try check(configuration == beforeShow)
            toggleAllHighlights()
            closeManagement()
            try check(!isShowingAll && !controllers[divider]!.displaysNumber)
            try check(controllers[spacer]!.statusItem.button!.image == nil)
            try check(controllers[divider]!.statusItem.button!.image!.tiffRepresentation! == dividerImage)
            try check(controllers[divider]!.displayedOpacity == 0.55 && configuration == beforeShow)
            try assertTrue(equalFile(store.url, showBytes))
            try check(NSApp.activationPolicy() == .accessory)
            showManagement()
            try check(NSApp.activationPolicy() == .regular)
            toggleHighlight(spacer)
            closeManagement()
            try check(configuration.items.allSatisfy { !$0.isHighlighted } && !isShowingAll)
            try check(controllers[spacer]!.statusItem.button?.image == nil)
            showManagement()
            let beforeDividerPreview = configuration
            previewDividers(.opacity, value: 0.8)
            try check(isPreviewing && configuration == beforeDividerPreview)
            cancelDividerPreview()
            try check(controllers[divider]!.configuration.opacity == 0.55)
            let menu = NSMenu(); populate(menu, for: divider)
            try check(menu.items.allSatisfy { $0.submenu == nil })
            try check(menu.items.filter { $0.view is MenuMasterDividerView }.count == 1)
            try check(menu.items.contains { $0.title == "Show All" })
            let view = NSApp.windows.first { $0.title == "SpaceBar — Test" }!.contentView!
            try check(findButtons(in: view).contains { $0.title == "Check for Updates…" && $0.isEnabled })
            try check(menu.items.contains { $0.title == "Check for Updates…" && $0.isEnabled })
            try check(updateCoordinator.availability == .development,
                      "Native QA and local development must not install public updates")
            let restoreButton = findButtons(in: view).first { $0.title == "Restore Layout… (Experimental)" }!
            let layoutChoice = findPopups(in: view).first { $0.accessibilityLabel() == "Saved menu bar layout" }!
            try check(!restoreButton.isHidden && !restoreButton.isEnabled && restoreButton.enclosingScrollView == nil,
                      "Restore must stay visible outside the scrolling item list, even before the first save")
            let firstChoice = MenuBarLayout(name: "Same name", configuration: configuration, displays: [], icons: [])
            let secondChoice = MenuBarLayout(name: "Same name", configuration: configuration, displays: [], icons: [])
            let beforeLayoutChoices = try Data(contentsOf: store.url)
            try layoutManager.addSnapshot(firstChoice)
            try layoutManager.addSnapshot(secondChoice)
            try check(restoreButton.isEnabled && layoutChoice.numberOfItems == 2)
            try check(layoutChoice.selectedItem?.representedObject as? UUID == secondChoice.id)
            layoutChoice.selectItem(at: 1)
            layoutChoice.sendAction(layoutChoice.action!, to: layoutChoice.target)
            refreshFeatureUI()
            try check(layoutChoice.selectedItem?.representedObject as? UUID == firstChoice.id,
                      "Refreshing must preserve the user's selected layout, including duplicate names")
            let restoreMenu = NSMenu(); populate(restoreMenu, for: divider)
            try check(restoreMenu.items.first { $0.title == "Restore Menu Bar Layout (Experimental)" }?.submenu?.items.count == 2)
            layoutManager.delete(firstChoice.id)
            try check(layoutChoice.numberOfItems == 1 && layoutChoice.selectedItem?.representedObject as? UUID == secondChoice.id)
            layoutManager.delete(secondChoice.id)
            try check(!restoreButton.isEnabled)
            try assertTrue(equalFile(store.url, beforeLayoutChoices))
            print("PASS: Restore stays visible; saved-layout choices retain their identities/selection, including duplicate names. Menu Restore lists snapshots; choices/deletion do not change the live configuration.")
            try check(findSliders(in: view).filter { $0.accessibilityLabel() == "All dividers opacity" }.count == 1)
            try check(findSliders(in: view).filter { $0.accessibilityLabel() == "All dividers height" }.count == 1)
            let export = store.url.deletingLastPathComponent().appendingPathComponent("export.json")
            try exportSettings(to: export)
            try assertTrue(ConfigurationStore(url: export).load() == configuration)
            print("PASS: Temporary Show All numbers only spacers, forces divider opacity without saving it, restores individual appearance, and clears on Settings close. Existing native IDs, master controls, menus, previews and export survive.")

            let flexID = add(.flexSpacer)!
            try check(add(.flexSpacer) == nil)
            let flex = controllers[flexID]!.statusItem
            arrangeFlex(flexID)
            let minimumSlider = findSliders(in: view).first { $0.accessibilityLabel() == "Flex spacer width" }!
            try check(flex.length == 24 && minimumSlider.doubleValue == 24,
                      "After Arrange, the paused width slider must show the actual native width")
            try check(findButtons(in: view).contains { $0.title == "Open Accessibility Settings…" && !$0.isHidden })
            try check(saveStatus == "Spacers saved")
            for width in [18.0, 6.0] {
                minimumSlider.doubleValue = width
                minimumSlider.sendAction(minimumSlider.action!, to: minimumSlider.target)
                for _ in 0..<150 {
                    if configuration.items.first(where: { $0.id == flexID })?.width == width && minimumSlider.isEnabled { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                try check(flex.length == width && minimumSlider.doubleValue == width)
                try check(try store.load()?.items.first(where: { $0.id == flexID })?.width == width)
                try check(configuration.items.first(where: { $0.id == flexID })?.flex?.centeringMinimumWidth == 6)
            }
            await setFlexLimits(flexID, minimum: 6, maximum: 3000)
            try check(flex.length == 6)
            try check(configuration.items.first(where: { $0.id == flexID })?.flex?.minimumWidth == 220)
            try check(configuration.items.first(where: { $0.id == flexID })?.flex?.centeringMinimumWidth == 6,
                      "Manual sizing must not change the independent centering minimum")
            let savedLimits = configuration
            let limitsBytes = try Data(contentsOf: store.url)
            previewFlexLimits(flexID, minimum: 2800, maximum: 3000, sizingFromMinimum: true)
            try check(flex.length == 6 && isPreviewing && configuration == savedLimits)
            try assertTrue(equalFile(store.url, limitsBytes))
            cancelPreview(for: flexID)
            try check(flex.length == 6 && !isPreviewing)
            await setFlexLimits(flexID, minimum: 2800, maximum: 3000)
            try check(flex.length == 6 && configuration == savedLimits, "Unsafe growth was applied or persisted")
            if MenuBarAccess.isTrusted {
                toggleFlex(flexID)
                try check(minimumSlider.accessibilityLabel() == "Flex spacer minimum gap" && minimumSlider.doubleValue == 6)
                try await Task.sleep(for: .milliseconds(1900))
                try check(configuration.items.first(where: { $0.id == flexID })?.flex?.isEnabled == true,
                          "Temporary crowding or unreadable geometry must not permanently disable Center")
                try check(try store.load()?.items.first(where: { $0.id == flexID })?.flex?.isEnabled == true)
                try check(flex.length == 6 && flexCoordinator.status.contains("Waiting"),
                          "QA's left-side spacer must wait safely rather than resize into the center")
                try check(flexCoordinator.isMonitoring && flexCoordinator.hasMonitoringActivity)
                closeManagement()
                let workspace = NSWorkspace.shared.notificationCenter
                let backgroundCount = flexCoordinator.completedObservationCount
                try await Task.sleep(for: .milliseconds(2400))
                try check(!isManagementVisible && flexCoordinator.completedObservationCount >= backgroundCount + 2,
                          "Center must keep observing without a visible Settings window")
                let wakeBytes = try Data(contentsOf: store.url)
                let wakeConfiguration = configuration
                let wakeItems = controllers.mapValues(\.statusItem)
                for cycle in 0..<3 {
                    workspace.post(name: NSWorkspace.screensDidSleepNotification, object: NSWorkspace.shared)
                    workspace.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
                    try check(!flexCoordinator.isMonitoring && !flexCoordinator.hasMonitoringActivity)
                    let sleepingCount = flexCoordinator.completedObservationCount
                    try await Task.sleep(for: .milliseconds(900))
                    try check(flexCoordinator.completedObservationCount == sleepingCount,
                              "Sleeping displays must stop observation and release the activity")
                    // The system and display wake notifications can arrive in
                    // either order. Do not restart until both are awake.
                    let firstWake = cycle == 1 ? NSWorkspace.didWakeNotification : NSWorkspace.screensDidWakeNotification
                    let secondWake = cycle == 1 ? NSWorkspace.screensDidWakeNotification : NSWorkspace.didWakeNotification
                    workspace.post(name: firstWake, object: NSWorkspace.shared)
                    try check(!flexCoordinator.isMonitoring)
                    workspace.post(name: secondWake, object: NSWorkspace.shared)
                    try check(flexCoordinator.isMonitoring && flexCoordinator.hasMonitoringActivity)
                    let resumedCount = flexCoordinator.completedObservationCount
                    try await Task.sleep(for: .milliseconds(2400))
                    try check(flexCoordinator.completedObservationCount >= resumedCount + 2,
                              "Wake must resume repeated observations without clicking or opening Settings")
                    try check(configuration == wakeConfiguration && flex.length == 6)
                    try check(controllers.allSatisfy { $0.value.statusItem === wakeItems[$0.key] })
                    try assertTrue(equalFile(store.url, wakeBytes))
                }
                workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: NSWorkspace.shared)
                try check(!flexCoordinator.isMonitoring && !flexCoordinator.hasMonitoringActivity)
                workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: NSWorkspace.shared)
                try check(flexCoordinator.isMonitoring && flexCoordinator.hasMonitoringActivity)
                toggleFlex(flexID)
                try check(!flexCoordinator.isMonitoring && !flexCoordinator.hasMonitoringActivity)
                workspace.post(name: NSWorkspace.screensDidSleepNotification, object: NSWorkspace.shared)
                workspace.post(name: NSWorkspace.screensDidWakeNotification, object: NSWorkspace.shared)
                try check(!flexCoordinator.isMonitoring && !flexCoordinator.hasMonitoringActivity,
                          "Wake must not turn a manually paused Center back on")
                showManagement()
                try check(minimumSlider.accessibilityLabel() == "Flex spacer width" && minimumSlider.doubleValue == flex.length)
                print("PASS: Center observes with Settings closed; three isolated display/system sleep-wake cycles and session return resume the timer and activity without edits or new status items. Manual Pause stays paused after wake.")
                print("PASS: Native manual Width saves sizes without raising the independent Minimum gap; Center and Pause switch the control correctly.")
                try check(configuration.items.first(where: { $0.id == flexID })?.flex?.isEnabled == false)
                print("PASS: Center retains its saved enabled intent while crowded/hidden and keeps the native width; manual Pause cancels automatic recovery.")
                try await Task.sleep(for: .milliseconds(300))
                let lengths = controllers.mapValues { $0.statusItem.length }
                let captureBytes = try Data(contentsOf: store.url)
                let snapshot = try await layoutManager.capture(name: "Read-only QA")
                try check(!snapshot.icons.isEmpty)
                try check(controllers.allSatisfy { $0.value.statusItem.length == lengths[$0.key] })
                try assertTrue(equalFile(store.url, captureBytes))
                try layoutManager.addSnapshot(snapshot)
                try assertTrue(layoutManager.store.load().layouts.contains(snapshot))
                print("PASS: Accessibility capture saves visible reference including anonymous items without resizing, dragging or writing configuration.")
                let beforeGrowth = configuration
                await setFlexLimits(flexID, minimum: 18, maximum: 3000)
                if flex.length == 18 {
                    await setFlexLimits(flexID, minimum: 6, maximum: 3000)
                    try check(flex.length == 6)
                    print("PASS: Small checked flex growth/shrink remains visible; oversized growth is rejected.")
                    for width in [18.0, 6.0, 24.0, 6.0] {
                        minimumSlider.doubleValue = width
                        minimumSlider.sendAction(minimumSlider.action!, to: minimumSlider.target)
                        for _ in 0..<150 {
                            if configuration.items.first(where: { $0.id == flexID })?.width == width && minimumSlider.isEnabled { break }
                            try await Task.sleep(for: .milliseconds(20))
                        }
                        try check(flex.length == width && minimumSlider.doubleValue == width,
                                  "Native width slider target \(width), native \(flex.length), slider \(minimumSlider.doubleValue), saved \(configuration.items.first(where: { $0.id == flexID })?.width ?? -1); \(flexCoordinator.status); menu owner \(NSWorkspace.shared.menuBarOwningApplication?.localizedName ?? "unknown")")
                        try check(configuration.items.first(where: { $0.id == flexID })?.width == width)
                        try check(try store.load()?.items.first(where: { $0.id == flexID })?.width == width)
                        try check(configuration.items.first(where: { $0.id == flexID })?.flex?.centeringMinimumWidth == 6)
                    }
                    try await Task.sleep(for: .milliseconds(250))
                    try check(minimumSlider.maxValue < 3000 && minimumSlider.maxValue >= flex.length,
                              "Paused width slider must use checked room rather than the full 3000 pt range")
                    print("PASS: Native flex slider commits repeated growth/shrink and saved widths without snapping back; Arrange shows actual width and the slider range uses checked room. Permission settings remains visible.")
                } else {
                    try check(flex.length == 6 && configuration == beforeGrowth)
                    try check(flexCoordinator.status.contains("Cannot check this spacer’s room safely") ||
                              flexCoordinator.status.contains("without hiding visible icons") ||
                              flexCoordinator.status.contains("Previous width restored"),
                              "Unexpected reason for refusing growth: \(flexCoordinator.status)")
                    print("LIMIT: QA growth was safely refused: \(flexCoordinator.status)")
                }
            } else {
                layoutManager.saveCurrent()
                try check(layoutManager.status.contains("does not have Accessibility"))
                try check(!layoutManager.isBusy)
                print("PASS: Missing access produces inline guidance, without OS prompts or opening settings. Native growth/capture requires installed-app permission verification.")
            }
            try check(controllers[flexID]!.statusItem === flex)
            await setFlexLimits(flexID, minimum: .nan, maximum: 3000)
            try check(flex.length == 6)
            let limits = configuration
            try check(applySavedConfiguration(limits))
            try check(controllers[flexID]!.statusItem === flex)
            for id in configuration.items.map(\.id) { remove(id) }
            try check(controllers.isEmpty)
            try assertTrue(store.load()?.items.isEmpty == true)
            print("PASS: Flex preview changes labels only; invalid/oversized changes preserve configuration and native identity; last-item recovery remains available. No login registration changed.")
            closeManagement()
            try await Task.sleep(for: .milliseconds(300))
            NSApp.terminate(nil)
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            NSApp.setActivationPolicy(.accessory)
            try? await Task.sleep(for: .milliseconds(300))
            exit(1)
        }
    }

    private func check(_ value: Bool, _ message: String = "", file: StaticString = #fileID, line: UInt = #line) throws {
        if !value {
            throw NSError(domain: "SpaceBar QA", code: Int(line), userInfo: [NSLocalizedDescriptionKey: "\(file):\(line) \(message.isEmpty ? "Check failed" : message)"])
        }
    }
    private func assertTrue(_ value: Bool, file: StaticString = #fileID, line: UInt = #line) throws { try check(value, file: file, line: line) }
    private func equalFile(_ url: URL, _ data: Data) throws -> Bool { try Data(contentsOf: url) == data }

    private func findButtons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { findButtons(in: $0) }
    }

    private func findSliders(in view: NSView) -> [NSSlider] {
        (view as? NSSlider).map { [$0] } ?? view.subviews.flatMap { findSliders(in: $0) }
    }

    private func findPopups(in view: NSView) -> [NSPopUpButton] {
        (view as? NSPopUpButton).map { [$0] } ?? view.subviews.flatMap { findPopups(in: $0) }
    }

    private func writeNumberPreview() throws {
        var spacer = ItemConfiguration(kind: .spacer)
        spacer.width = 64
        let divider = ItemConfiguration(kind: .divider)
        var narrow = ItemConfiguration(kind: .spacer)
        narrow.width = 6
        let samples = [(spacer, 2), (divider, 14), (narrow, 10)]
        let images = samples.map { ItemNumberImage.make(configuration: $0.0, number: $0.1) }
        for (index, image) in images.enumerated() {
            precondition(image.isTemplate && image.size.width <= samples[index].0.width)
        }
        let preview = NSImage(size: NSSize(width: 500, height: 190), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            for (index, image) in images.enumerated() {
                let y = 140 - CGFloat(index) * 55
                let title = "\(samples[index].0.kind.title) \(samples[index].1), \(Int(samples[index].0.width)) pt (3×)" as NSString
                title.draw(at: NSPoint(x: 12, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black])
                image.draw(in: NSRect(x: 265, y: y - 8, width: image.size.width * 3, height: image.size.height * 3))
            }
            return true
        }
        let data = NSBitmapImageRep(data: preview.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let output = store.url.deletingLastPathComponent().appendingPathComponent("number-preview.png")
        try data.write(to: output)
        if let index = CommandLine.arguments.firstIndex(of: "--number-preview"),
           CommandLine.arguments.indices.contains(index + 1) {
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
    }
}
