import AppKit
import SpacersCore

@MainActor
final class FlexSpacerCoordinator: NSObject {
    weak var owner: AppDelegate?
    private var timer: Timer?
    private var monitoringActivity: NSObjectProtocol?
    private var pending = false
    private var reading = false
    private var readingTask: Task<Void, Never>?
    private var measurementGeneration = 0
    private var retryNotBefore: Date?
    private var systemSleeping = false
    private var displaySleeping = CGDisplayIsAsleep(CGMainDisplayID()) != 0
    private var sessionInactive = false
    private var recovery = FlexRecoveryGate()
    private(set) var completedObservationCount = 0
    var isMonitoring: Bool { timer?.isValid == true }
    var hasMonitoringActivity: Bool { monitoringActivity != nil }
    private var canMonitor: Bool { !systemSleeping && !displaySleeping && !sessionInactive }
    private(set) var lastFrame: CGRect?
    private(set) var lastScreen: LayoutScreen?
    private(set) var status = "Add a flex spacer to keep a gap centered."

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(frameChanged), name: NSWindow.didMoveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(frameChanged), name: NSWindow.didResizeNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(workspaceStateChanged), name: name, object: nil)
        }
    }

    func configurationChanged() {
        let enabled = owner?.configuration.items.contains { $0.kind == .flexSpacer && $0.flex?.isEnabled == true } == true
        if enabled && canMonitor && timer == nil {
            // AppKit does not promise notifications for every system-side status
            // item move. Center is ongoing user-requested work: keep its timer
            // out of App Nap, without preventing display or system idle sleep.
            monitoringActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Keep the requested menu bar gap centered while the display is awake")
            let timer = Timer(timeInterval: 0.75, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
            timer.tolerance = 0.25
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !enabled || !canMonitor {
            stopMonitoring()
        }
        if !enabled {
            recovery.reset()
            retryNotBefore = nil
            if let item = owner?.configuration.items.first(where: { $0.kind == .flexSpacer }) {
                publish("Paused at \(Int(owner?.controllers[item.id].map { Double($0.statusItem.length) } ?? item.width)) pt. Use Center to follow icons; Arrange if hidden.")
            }
        } else if !canMonitor {
            publish("Waiting for the display and session to wake. Center will resume automatically.")
        }
        schedule()
        refreshAvailableRoom()
    }

    func stopMonitoring() {
        timer?.invalidate(); timer = nil
        if let monitoringActivity { ProcessInfo.processInfo.endActivity(monitoringActivity) }
        monitoringActivity = nil
        measurementGeneration += 1
        readingTask?.cancel(); readingTask = nil; reading = false
    }

    @objc private func workspaceStateChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.willSleepNotification: systemSleeping = true
        case NSWorkspace.didWakeNotification: systemSleeping = false
        case NSWorkspace.screensDidSleepNotification: displaySleeping = true
        case NSWorkspace.screensDidWakeNotification: displaySleeping = false
        case NSWorkspace.sessionDidResignActiveNotification: sessionInactive = true
        case NSWorkspace.sessionDidBecomeActiveNotification: sessionInactive = false
        default: return
        }
        // Discard pre-sleep AX handles and observations. A canceled old read
        // must never resize, pause Center, or clear the newer read's busy flag.
        stopMonitoring()
        owner?.menuGeometry.invalidateOwnBindings()
        lastFrame = nil; lastScreen = nil; recovery.wait()
        retryNotBefore = nil
        configurationChanged()
    }

    @objc private func frameChanged(_ notification: Notification) { if timer != nil { schedule() } }
    @objc private func tick() { rebalance() }
    private func schedule() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            self?.pending = false
            self?.rebalance()
        }
    }

    private(set) var isAdjusting = false
    private(set) var resizeFailureCanRetry = false

    /// No dragging or active width probes. Missing/ambiguous geometry refuses
    /// growth; shrinking remains available to recover an oversized hidden item.
    func resizeSafely(_ id: UUID, to width: Double) async -> Bool {
        resizeFailureCanRetry = false
        guard !isAdjusting, let owner, let controller = owner.controllers[id],
              width.isFinite, (6...3000).contains(width), !owner.layoutManager.isBusy else { return false }
        defer { if owner.isUITest { print("QA resize \(width) pt: \(status)") } }
        let original = Double(controller.statusItem.length)
        if abs(original - width) < 0.5 { return true }
        if width < original {
            controller.applyFlexWidth(width)
            publish("Sized to \(Int(width)) pt.")
            return true
        }
        guard MenuBarAccess.isTrusted else {
            resizeFailureCanRetry = true
            publish("Growth needs Accessibility to check available room. Open Accessibility Settings below; shrinking and Arrange still work.")
            return false
        }
        isAdjusting = true
        defer { isAdjusting = false; owner.refreshFeatureUI() }
        let saved = owner.configuration
        guard let room = await availableRoom(for: id) else {
            resizeFailureCanRetry = true
            availableWidth = nil
            publish("Cannot check this spacer’s room safely. Use Arrange, ⌘-drag it into view, then try again.")
            return false
        }
        let (capacity, before, apps, screens, icon, menuOwner) = room
        let identifier = "SpaceBar.Item.\(id.uuidString)"
        availableWidth = capacity.rounded(.down)
        guard width <= capacity else {
            resizeFailureCanRetry = true
            publish("Only \(Int(capacity.rounded(.down))) pt fits without hiding visible icons. Reduce the gap or remove icons; size kept at \(Int(original)) pt."); return false
        }
        guard NSWorkspace.shared.menuBarOwningApplication?.processIdentifier == menuOwner else {
            resizeFailureCanRetry = true
            publish("Waiting for the current app’s menu to settle before growing the gap.")
            return false
        }
        guard owner.configuration == saved, owner.controllers[id] === controller,
              !owner.layoutManager.isBusy, NSEvent.pressedMouseButtons == 0,
              !Task.isCancelled, abs(controller.statusItem.length - original) < 0.5 else { return false }
        controller.applyFlexWidth(width)
        // Verify the native host after the single resize. If the OS hides an
        // item or changes order/right anchor, roll back. A proven change in
        // other icons may retry after settling; actual reordering still pauses.
        try? await Task.sleep(for: .milliseconds(180))
        // MenuBarAgent can replace a proxy when its width changes. Rebind by
        // verified ownership and unique visible width before checking the host;
        // a stale AX handle is not evidence that the spacer disappeared.
        await owner.menuGeometry.resolveOwnItems(ids: [id])
        let after = await owner.menuGeometry.read(apps: apps, screens: screens)
        guard owner.configuration == saved, owner.controllers[id] === controller else {
            // Another edit may arrive during verification. Revert our runtime
            // change only when no newer width/Arrange action replaced it.
            if owner.controllers[id] === controller, abs(controller.statusItem.length - width) < 0.5,
               owner.configuration.items.first(where: { $0.id == id })?.width == saved.items.first(where: { $0.id == id })?.width {
                controller.applyFlexWidth(original)
            }
            return false
        }
        let resized = after.icons.first { $0.identifier == identifier && $0.displayID == icon.displayID }
        let beforeOrder = orderSignature(before.icons, display: icon.displayID, excluding: identifier)
        let afterOrder = orderSignature(after.icons, display: icon.displayID, excluding: identifier)
        let othersBefore = before.icons.filter { $0.displayID == icon.displayID && $0.identifier != identifier }
        let othersAfter = after.icons.filter { $0.displayID == icon.displayID && $0.identifier != identifier }
        let orderPreserved = beforeOrder == afterOrder ||
            FlexResizeSafety.visibleItemsPreserved(before: othersBefore, after: othersAfter)
        let anchorStable = resized.map { abs(($0.left + $0.width) - (icon.left + icon.width)) <= 2 && abs($0.width - icon.width - width + original) <= 2 } ?? false
        if Task.isCancelled || !anchorStable || !orderPreserved {
            controller.applyFlexWidth(original)
            let ownSizeApplied = resized.map { abs($0.width - icon.width - width + original) <= 2 } ?? false
            if !Task.isCancelled, resized == nil {
                resizeFailureCanRetry = true
                retryNotBefore = Date().addingTimeInterval(3)
                publish("Waiting for macOS to expose the spacer’s updated position. Previous width kept; Center remains on.")
                return false
            }
            if !Task.isCancelled, ownSizeApplied,
               (orderPreserved || FlexResizeSafety.environmentChangedWithoutReordering(before: othersBefore, after: othersAfter)) {
                resizeFailureCanRetry = true
                retryNotBefore = Date().addingTimeInterval(3)
                publish("Menu bar positions changed during the check. Previous width kept; waiting for them to settle.")
                return false
            }
            publish("macOS could not keep this size visible and in place. Previous width restored; centering paused.")
            return false
        }
        publish("Sized to \(Int(width)) pt; visible icon order checked.")
        return true
    }

    private func availableRoom(for id: UUID) async -> (maximum: Double, before: MenuBarReadout, apps: [LayoutApp], screens: [LayoutScreen], icon: LayoutIcon, menuOwner: pid_t)? {
        guard let owner, let controller = owner.controllers[id], MenuBarAccess.isTrusted else { return nil }
        let original = Double(controller.statusItem.length)
        let knownScreens = MenuBarAccess.screens()
        let screens = Array(knownScreens.prefix(1))
        await owner.menuGeometry.resolveOwnItems(ids: [id])
        let apps = MenuBarAccess.apps(qaOnly: false)
        let before = await owner.menuGeometry.read(apps: apps, screens: screens)
        let identifier = "SpaceBar.Item.\(id.uuidString)"
        guard let icon = before.icons.first(where: { $0.identifier == identifier }),
              let screen = screens.first(where: { $0.display.id == icon.displayID }),
              let pid = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier else {
            return nil
        }
        var ownMenuRight: Double?
        if pid == NSRunningApplication.current.processIdentifier {
            ownMenuRight = NSApp.mainMenu?.items.map { $0.accessibilityFrame() }.filter {
                $0.width > 0 && $0.minX >= screen.bounds.minX && $0.maxX < screen.bounds.midX
            }.map { Double($0.maxX) }.max()
            if ownMenuRight == nil, let menu = NSApp.mainMenu {
                // Self-directed AX IPC can return unavailable/virtual frames.
                // Our own fixed menus have known titles. Reserve more than
                // twice their text widths plus generous padding, never guess
                // another application's menu boundary this way.
                let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SpaceBar"
                let font = NSFont.menuBarFont(ofSize: 0)
                let reserve = menu.items.filter { !$0.isHidden }.reduce(64.0) { sum, item in
                    let text = item.title.isEmpty ? appName : item.title
                    return sum + Double((text as NSString).size(withAttributes: [.font: font]).width) * 2 + 48
                }
                ownMenuRight = screen.bounds.minX + max(400, reserve)
            }
        }
        let menuRight: Double?
        if let ownMenuRight { menuRight = ownMenuRight }
        else { menuRight = await Task.detached { MenuBarAccess.applicationMenuRight(pid: pid, screen: screen, knownScreens: knownScreens) }.value }
        guard let menuRight,
              let leftmost = before.icons.filter({ $0.displayID == icon.displayID }).map(\.left).min(),
              let capacity = FlexSafety.maximumWidth(current: original,
                leftmostIcon: screen.bounds.minX + leftmost, applicationMenuRight: menuRight) else {
            return nil
        }
        return (capacity, before, apps, screens, icon, pid)
    }

    private(set) var availableWidth: Double?

    /// Read only while Settings is visible. Never resize an item to estimate room.
    func refreshAvailableRoom() {
        guard canMonitor, !reading, !isAdjusting, let owner, owner.isManagementVisible,
              !owner.layoutManager.isBusy,
              let item = owner.configuration.items.first(where: { $0.kind == .flexSpacer }),
              let controller = owner.controllers[item.id] else { return }
        reading = true
        let generation = measurementGeneration
        let width = controller.statusItem.length
        readingTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == measurementGeneration { reading = false; readingTask = nil } }
            let room = await availableRoom(for: item.id)
            guard generation == measurementGeneration, canMonitor, !Task.isCancelled,
                  owner.configuration.items.first(where: { $0.id == item.id }) == item,
                  owner.controllers[item.id] === controller, controller.statusItem.length == width,
                  !isAdjusting else { return }
            availableWidth = room?.maximum.rounded(.down)
            owner.refreshFeatureUI()
        }
    }

    private func orderSignature(_ icons: [LayoutIcon], display: String, excluding: String) -> [String] {
        icons.filter { $0.displayID == display && $0.identifier != excluding }.sorted { $0.left < $1.left }.map {
            "\($0.bundleID)|\($0.identifier)|\(Int(($0.width * 2).rounded()))"
        }
    }

    func rebalance() {
        guard let owner, let item = owner.configuration.items.first(where: { $0.kind == .flexSpacer }),
              let settings = item.flex, let controller = owner.controllers[item.id] else {
            publish("Add a flex spacer to keep a gap centered."); return
        }
        guard settings.isEnabled, canMonitor else { return }
        if let retryNotBefore, Date() < retryNotBefore { return }
        guard !owner.layoutManager.isBusy, !owner.isPreviewing, !isAdjusting,
              NSEvent.pressedMouseButtons == 0, !reading else { return }
        guard MenuBarAccess.isTrusted else {
            wait("Waiting for Accessibility access. Center will resume when access is available."); return
        }
        reading = true
        let generation = measurementGeneration
        readingTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == measurementGeneration { reading = false; readingTask = nil } }
            let screens = Array(MenuBarAccess.screens().prefix(1))
            let readout = await owner.menuGeometry.readOwn(item.id, screens: screens)
            guard generation == measurementGeneration, canMonitor, !Task.isCancelled,
                  !owner.isPreviewing, owner.configuration.items.first(where: { $0.id == item.id }) == item,
                  !owner.layoutManager.isBusy, NSEvent.pressedMouseButtons == 0 else { return }
            completedObservationCount += 1
            guard let icon = readout.icons.first(where: { $0.identifier == "SpaceBar.Item.\(item.id.uuidString)" }),
                  let screen = screens.first(where: { $0.display.id == icon.displayID }) else {
                lastFrame = nil; lastScreen = nil
                wait("Waiting for the spacer to become visible and identifiable. Center will resume automatically; use Arrange if it stays hidden."); return
            }
            let frame = CGRect(x: screen.bounds.minX + icon.left, y: screen.bounds.minY + icon.top,
                               width: icon.width, height: icon.height)
            lastFrame = frame; lastScreen = screen
            let protectedGap = max(6, screen.notch.map { $0.width + 24 } ?? 0)
            let minimum = max(settings.centeringMinimumWidth, protectedGap)
            let padding = max(0, frame.width - controller.statusItem.length)
            guard let result = FlexGeometry.solve(rightEdge: frame.maxX, center: screen.bounds.midX,
                screenLeft: screen.bounds.minX, minimum: minimum + padding,
                maximum: settings.maximumWidth + padding, protectedMinimum: protectedGap + padding) else {
                wait("Waiting for enough room within the gap limits. Current size kept; Center will resume automatically."); return
            }
            if result.rightSideCrowded {
                wait("Right-hand icons reach the protected center area. Waiting; Center will resume automatically when they move back."); return
            }
            guard recovery.canResume(rightEdge: frame.maxX, displayID: screen.display.id) else {
                publish("Room is returning. Checking the anchor before Center resumes…"); return
            }
            let width = max(6, result.width - padding)
            if abs(controller.statusItem.length - width) > 1 {
                guard await resizeSafely(item.id, to: width) else {
                    if generation == measurementGeneration, canMonitor, !Task.isCancelled,
                       owner.configuration.items.first(where: { $0.id == item.id }) == item {
                        if resizeFailureCanRetry { wait("Waiting for safe room to resize. Current size kept; Center will retry automatically.") }
                        else { pause(item, message: status) }
                    }
                    return
                }
            }
            guard generation == measurementGeneration, canMonitor, !Task.isCancelled,
                  owner.configuration.items.first(where: { $0.id == item.id }) == item else { return }
            if result.isCentered { publish("Centered on \(screen.display.name) · \(Int(width)) pt") }
            else if result.isMinimumLimited {
                publish("At your minimum gap. Lower it to allow more compensation; Center is still running.")
            } else { publish("At the maximum width — increase it or move the spacer to center the gap.") }
        }
    }

    private func wait(_ message: String) {
        recovery.wait()
        publish(message)
    }

    private func pause(_ item: ItemConfiguration, message: String) {
        guard let owner, owner.configuration.items.first(where: { $0.id == item.id }) == item else { return }
        var paused = item
        paused.width = owner.controllers[item.id].map { Double($0.statusItem.length) } ?? item.width
        paused.flex?.isEnabled = false
        _ = owner.update(paused)
        publish(message)
    }

    private func publish(_ value: String) {
        guard value != status else { return }
        status = value
        owner?.refreshFeatureUI()
    }
}

@MainActor
final class FlexSpacerRow: NSStackView {
    private let id: UUID
    private weak var owner: AppDelegate?
    private let title = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let enable = NSButton(title: "Center", target: nil, action: nil)
    private let arrange = NSButton(title: "Arrange", target: nil, action: nil)
    private let show = NSButton(title: "Show", target: nil, action: nil)
    private let minimum = TrackingSlider()
    private let minimumCaption = NSTextField(labelWithString: "Width")
    private let maximum = TrackingSlider()
    private let minimumLabel = NSTextField(labelWithString: "")
    private let maximumLabel = NSTextField(labelWithString: "")
    private var isSaving = false

    init(item: ItemConfiguration, owner: AppDelegate) {
        id = item.id; self.owner = owner
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 8
        title.font = .systemFont(ofSize: 13, weight: .medium)
        enable.target = self; enable.action = #selector(toggleEnabled)
        arrange.target = self; arrange.action = #selector(arrangeItem)
        arrange.toolTip = "Pause and shrink this spacer so it is easy to Command-drag into place."
        show.target = self; show.action = #selector(toggleShow)
        let remove = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove flex spacer")!, target: self, action: #selector(deleteItem))
        for button in [arrange, enable, show, remove] { button.bezelStyle = .rounded }
        let heading = NSStackView(views: [title, NSView(), arrange, enable, show, remove])
        heading.spacing = 8; addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        for (label, slider, value) in [("Minimum gap", minimum, minimumLabel), ("Maximum width", maximum, maximumLabel)] {
            let caption = slider === minimum ? minimumCaption : NSTextField(labelWithString: label)
            caption.widthAnchor.constraint(equalToConstant: 110).isActive = true
            slider.minValue = 6; slider.maxValue = 3000; slider.isContinuous = true
            slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
            slider.setAccessibilityLabel("Flex spacer \(label.lowercased())")
            slider.target = self; slider.action = #selector(sliderChanged)
            value.widthAnchor.constraint(equalToConstant: 62).isActive = true
            value.alignment = .right; value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            let row = NSStackView(views: [caption, slider, value]); row.spacing = 10
            addArrangedSubview(row); row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        minimum.toolTip = "Width while paused; a separate minimum gap while Center runs. Setting a starting width does not lock the smallest automatic size."
        maximum.toolTip = "Caps the spacer width. A higher maximum leaves the width unchanged until more room is needed."
        minimum.onTrackingEnded = { [weak self] in self?.saveLimits(sizingFromMinimum: true) }
        maximum.onTrackingEnded = { [weak self] in self?.saveLimits(sizingFromMinimum: false) }
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        addArrangedSubview(status); status.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        refresh(item, number: owner.number(for: id))
    }
    required init?(coder: NSCoder) { fatalError("Not implemented") }
    func refresh(_ item: ItemConfiguration, number: Int) {
        title.stringValue = "Flex Spacer \(number)"
        enable.title = item.flex?.isEnabled == true ? "Pause" : "Center"
        show.title = item.isHighlighted ? "Hide" : "Show"
        let isCentering = item.flex?.isEnabled == true
        minimumCaption.stringValue = isCentering ? "Minimum gap" : "Width"
        minimum.setAccessibilityLabel(isCentering ? "Flex spacer minimum gap" : "Flex spacer width")
        if !minimum.isTracking && !maximum.isTracking && !isSaving {
            // Arrange is a temporary width below the centering minimum. While
            // paused, show the width this slider actually controls.
            let value = isCentering ? (item.flex?.centeringMinimumWidth ?? 6) : item.width
            let limit = owner?.flexCoordinator.availableWidth ?? item.width
            minimum.maxValue = max(value, min(item.flex?.maximumWidth ?? 1600, limit))
            minimum.doubleValue = value
            maximum.doubleValue = item.flex?.maximumWidth ?? 1600
        }
        updateLabels()
        status.stringValue = owner?.flexCoordinator.status ?? ""
        for control in [arrange, enable, show, minimum, maximum] as [NSControl] { control.isEnabled = owner?.layoutManager.isBusy != true && owner?.flexCoordinator.isAdjusting != true && !isSaving }
    }
    private func updateLabels() {
        minimumLabel.stringValue = "\(Int(minimum.doubleValue)) pt"
        maximumLabel.stringValue = "\(Int(maximum.doubleValue)) pt"
    }
    @objc private func sliderChanged(_ sender: NSSlider) {
        sender.doubleValue = sender.doubleValue.rounded()
        if sender === minimum { maximum.doubleValue = max(maximum.doubleValue, minimum.doubleValue) }
        else { minimum.doubleValue = min(minimum.doubleValue, maximum.doubleValue) }
        updateLabels()
        if minimum.isTracking || maximum.isTracking {
            owner?.previewFlexLimits(id, minimum: minimum.doubleValue, maximum: maximum.doubleValue,
                                     sizingFromMinimum: sender === minimum)
        } else { saveLimits(sizingFromMinimum: sender === minimum) }
    }
    private func saveLimits(sizingFromMinimum: Bool) {
        guard !isSaving else { return }
        let lower = minimum.doubleValue.rounded(), upper = maximum.doubleValue.rounded()
        isSaving = true
        Task { [weak self] in
            guard let self, let owner else { return }
            defer {
                isSaving = false
                if let item = owner.configuration.items.first(where: { $0.id == id }) {
                    refresh(item, number: owner.number(for: id))
                }
                owner.flexCoordinator.refreshAvailableRoom()
            }
            await owner.setFlexLimits(id, minimum: lower, maximum: upper, sizingFromMinimum: sizingFromMinimum)
        }
    }
    @objc private func arrangeItem() { owner?.arrangeFlex(id) }
    @objc private func toggleEnabled() { owner?.toggleFlex(id) }
    @objc private func toggleShow() { owner?.toggleHighlight(id) }
    @objc private func deleteItem() { owner?.remove(id) }
}
