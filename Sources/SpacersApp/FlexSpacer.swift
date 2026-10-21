import AppKit
import SpacersCore
import os

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
    private var safetyPause: (id: UUID, message: String)?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "local.samuelaviv.MenuBarSpacers", category: "FlexSpacer")
    private var recordedResizeFailure = false
    private struct CapacityContext: Hashable {
        let display: String
        let menuOwner: pid_t
        let menuRight: Double
        let screenLeft: Double
        let screenWidth: Double
    }
    private struct NativeLimit {
        let width: FlexGrowthLimit
        let arrangement: FlexBarArrangement
    }
    private var nativeLimits: [CapacityContext: NativeLimit] = [:]
    private var resizeRequiresRecovery = false
    private var resizeRetryStatus = "Waiting for safe room or settled positions. Center remains on and will retry automatically."
    private var delayedVerificationCount = 0
#if SPACEBAR_LOCAL_DIAGNOSTICS
    private var lastCapacityDetails: [String: Any] = [:]
    private var lastResizeDetails: [String: Any] = [:]
    private var lastAppliedResizeDetails: [String: Any] = [:]
#endif
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
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
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
                let reason = safetyPause?.id == item.id ? safetyPause?.message : nil
                publish(reason ?? "Paused at \(Int(owner?.controllers[item.id].map { Double($0.statusItem.length) } ?? item.width)) pt. Use Center to follow icons; Arrange if hidden.")
            }
        } else if !canMonitor {
            publish("Waiting for the display and session to wake. Center will resume automatically.")
        }
        if enabled { safetyPause = nil }
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

    func manualControlRequested() {
        safetyPause = nil
        retryNotBefore = nil
        recovery.reset()
        recordedResizeFailure = false
        nativeLimits.removeAll()
    }

#if SPACEBAR_LOCAL_DIAGNOSTICS
    func writeRuntimeDiagnostic() {
        guard let owner else { return }
        let item = owner.configuration.items.first { $0.kind == .flexSpacer }
        var value: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()),
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "status": status, "monitoring": isMonitoring, "activity": hasMonitoringActivity,
            "canMonitor": canMonitor, "reading": reading, "adjusting": isAdjusting,
            "observations": completedObservationCount, "recoveryWaiting": recovery.isWaiting,
            "delayedVerifications": delayedVerificationCount,
            "systemSleeping": systemSleeping, "displaySleeping": displaySleeping,
            "sessionInactive": sessionInactive, "trusted": MenuBarAccess.isTrusted,
            "previewing": owner.isPreviewing, "layoutBusy": owner.layoutManager.isBusy,
            "mouseButtons": NSEvent.pressedMouseButtons, "enabled": item?.flex?.isEnabled == true]
        value["allowsLeftOverflow"] = item?.flex?.allowsLeftOverflow == true
        value["nativeLimits"] = nativeLimits.map { ["menuOwnerPID": Int($0.key.menuOwner),
            "display": $0.key.display, "menuRight": $0.key.menuRight,
            "acceptedWidth": $0.value.width.acceptedWidth, "normalizedLeft": $0.value.width.normalizedLeft,
            "rightEdge": $0.value.width.referenceRightEdge ?? 0] as [String: Any] }
        value["capacityCheck"] = lastCapacityDetails
        value["lastResize"] = lastResizeDetails
        value["lastAppliedResize"] = lastAppliedResizeDetails
        if let item { value["runtimeWidth"] = owner.controllers[item.id].map { Double($0.statusItem.length) } }
        if let lastFrame { value["frame"] = [Double(lastFrame.minX), Double(lastFrame.minY), Double(lastFrame.width), Double(lastFrame.height)] }
        if let lastScreen { value["displayCenter"] = Double(lastScreen.bounds.midX) }
        if let availableWidth { value["availableWidth"] = availableWidth }
        if let retryNotBefore { value["retryNotBefore"] = ISO8601DateFormatter().string(from: retryNotBefore) }
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: owner.store.url.deletingLastPathComponent().appendingPathComponent("flex-runtime-state.json"), options: .atomic)
        } catch { logger.error("Could not write the requested local flex diagnostic.") }
    }
#endif

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
        nativeLimits.removeAll()
        lastFrame = nil; lastScreen = nil; recovery.wait()
        retryNotBefore = nil
        configurationChanged()
    }

    @objc private func frameChanged(_ notification: Notification) { if timer != nil { schedule() } }
    @objc private func activeApplicationChanged(_ notification: Notification) {
        retryNotBefore = nil
        if timer != nil { schedule() }
    }
    @objc private func screenParametersChanged(_ notification: Notification) {
        stopMonitoring()
        owner?.menuGeometry.invalidateOwnBindings()
        nativeLimits.removeAll()
        lastFrame = nil; lastScreen = nil
        retryNotBefore = nil; recovery.wait()
        configurationChanged()
    }
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

    /// No dragging or active width probes. Missing/ambiguous geometry refuses
    /// growth; shrinking remains available to recover an oversized hidden item.
    func resizeSafely(_ id: UUID, to width: Double) async -> FlexResizeResult {
        resizeRetryStatus = "Waiting for safe room or settled positions. Center remains on and will retry automatically."
        guard !isAdjusting, let owner, let controller = owner.controllers[id],
              width.isFinite, (6...3000).contains(width), !owner.layoutManager.isBusy else { return .retry }
        resizeRequiresRecovery = false
        defer { if owner.isUITest { print("QA resize \(width) pt: \(status)") } }
        let original = Double(controller.statusItem.length)
#if SPACEBAR_LOCAL_DIAGNOSTICS
        let started = Date()
        var diagnosticResult = "waiting"
        var overflowHiddenCount = 0
        defer {
            lastResizeDetails = ["original": original, "requested": width,
                "result": diagnosticResult, "overflowHiddenCount": overflowHiddenCount,
                "elapsedMilliseconds": Date().timeIntervalSince(started) * 1000]
            if diagnosticResult == "applied" { lastAppliedResizeDetails = lastResizeDetails }
        }
#endif
        if abs(original - width) < 0.5 { return .applied }
        if width < original {
            controller.applyFlexWidth(width)
#if SPACEBAR_LOCAL_DIAGNOSTICS
            diagnosticResult = "applied"
#endif
            publish("Sized to \(Int(width)) pt.")
            return .applied
        }
        guard MenuBarAccess.isTrusted else {
            publish("Growth needs Accessibility to check available room. Open Accessibility Settings below; shrinking and Arrange still work.")
            return .retry
        }
        isAdjusting = true
        defer { isAdjusting = false; owner.refreshFeatureUI() }
        let saved = owner.configuration
        let allowsOverflow = saved.items.first(where: { $0.id == id })?.flex?.allowsLeftOverflow == true
        guard let room = await availableRoom(for: id) else {
            availableWidth = nil
            publish("Cannot check this spacer’s room safely. Use Arrange, ⌘-drag it into view, then try again.")
            return .retry
        }
        let (capacity, before, apps, screens, icon, context) = room
        let identifier = "SpaceBar.Item.\(id.uuidString)"
        availableWidth = capacity.rounded(.down)
        guard width <= capacity else {
            if nativeLimits[context] != nil {
                resizeRetryStatus = "Waiting for room on the left. macOS cannot fit a centered gap with these icons and application menus. Center remains on; free some room and it will resume."
            } else {
                resizeRetryStatus = "Only \(Int(capacity.rounded(.down))) pt fits without hiding visible icons. Center remains on and will retry when room returns."
            }
            publish(resizeRetryStatus); return .retry
        }
        guard NSWorkspace.shared.menuBarOwningApplication?.processIdentifier == context.menuOwner else {
            publish("Waiting for the current app’s menu to settle before growing the gap.")
            return .retry
        }
        guard owner.configuration == saved, owner.controllers[id] === controller,
              !owner.layoutManager.isBusy, NSEvent.pressedMouseButtons == 0,
              !Task.isCancelled, abs(controller.statusItem.length - original) < 0.5 else {
            publish("Waiting for the current interaction to finish. Center will retry automatically.")
            return .retry
        }
        controller.applyFlexWidth(width)
        resizeRequiresRecovery = true
        // Verify the native host after the single resize. Native overflow is
        // allowed only by the user's explicit preference and a separate check
        // retaining every native object and the remaining visible order.
        // A proven change in
        // other icons may retry after settling; actual reordering still pauses.
        // MenuBarAgent can replace a proxy when its width changes. Rebind by
        // verified ownership and unique visible width before checking the host;
        // a stale AX handle is not evidence that the spacer disappeared.
        var after = MenuBarReadout()
        var resized: LayoutIcon?
        var comparison: (before: [LayoutIcon], after: [LayoutIcon]) = ([], [])
        var result = FlexResizeResult.retry
        var previousBoundary: Double?
        var confirmedBoundary: Double?
        var verificationReads = 0
        // Re-read the SAME requested size; never probe by applying more sizes.
        // Native animations can temporarily overlap items at the 180 ms mark.
        for delay in [180, 180, 300, 400] {
            try? await Task.sleep(for: .milliseconds(delay))
            if Task.isCancelled { break }
            await owner.menuGeometry.resolveOwnItems(ids: [id])
            after = await owner.menuGeometry.read(apps: apps, screens: screens)
            verificationReads += 1
            guard owner.configuration == saved, owner.controllers[id] === controller else { break }
            guard NSWorkspace.shared.menuBarOwningApplication?.processIdentifier == context.menuOwner else {
                result = .retry
                confirmedBoundary = nil
                resizeRetryStatus = "Waiting for the current app’s menus to settle. Center remains on and will retry automatically."
                break
            }
            resized = after.icons.first { $0.identifier == identifier && $0.displayID == icon.displayID }
            comparison = before.resizeComparison(with: after, display: icon.displayID, excluding: identifier)
            result = FlexResizeSafety.verifyGrowth(originalLength: original, requestedLength: width,
                before: icon, after: resized, othersBefore: comparison.before, othersAfter: comparison.after)
            if result == .retry, allowsOverflow {
                result = FlexNativeOverflow.verifyGrowth(originalLength: original, requestedLength: width,
                    before: icon, after: resized,
                    othersBefore: before.icons.filter { $0.displayID == icon.displayID && $0.identifier != identifier },
                    othersAfter: after.icons.filter { $0.displayID == icon.displayID && $0.identifier != identifier },
                    matches: before.proxyMatches(with: after, display: icon.displayID, excluding: identifier))
#if SPACEBAR_LOCAL_DIAGNOSTICS
                if result == .applied, let resized {
                    overflowHiddenCount = FlexNativeOverflow.hiddenCount(spacer: resized,
                        others: after.icons.filter { $0.displayID == icon.displayID && $0.identifier != identifier })
                }
#endif
            }
            let boundary = FlexResizeSafety.observedLeftBoundary(before: icon, after: resized,
                growth: width - original, othersBefore: comparison.before, othersAfter: comparison.after)
            confirmedBoundary = boundary.flatMap { value in
                previousBoundary.map { abs($0 - value) <= 1 ? value : nil } ?? nil
            }
            previousBoundary = boundary
            if result == .applied || NSEvent.pressedMouseButtons != 0 { break }
        }
        guard owner.configuration == saved, owner.controllers[id] === controller else {
            // Another edit may arrive during verification. Revert our runtime
            // change only when no newer width/Arrange action replaced it.
            if owner.controllers[id] === controller, abs(controller.statusItem.length - width) < 0.5,
               owner.configuration.items.first(where: { $0.id == id })?.width == saved.items.first(where: { $0.id == id })?.width {
                controller.applyFlexWidth(original)
            }
            return .retry
        }
        if Task.isCancelled || NSEvent.pressedMouseButtons != 0 ||
            NSWorkspace.shared.menuBarOwningApplication?.processIdentifier != context.menuOwner {
            result = .retry
            confirmedBoundary = nil
        }
        if result != .applied {
#if SPACEBAR_LOCAL_DIAGNOSTICS
            diagnosticResult = String(describing: result)
#endif
            controller.applyFlexWidth(original)
            var rememberedClipping = false
            if !allowsOverflow, !Task.isCancelled, NSEvent.pressedMouseButtons == 0,
               confirmedBoundary != nil,
               let leftmost = before.icons.map(\.left).min(),
               let limit = FlexGrowthLimit(current: original, leftmostIcon: context.screenLeft + leftmost,
                    rightEdge: context.screenLeft + icon.left + icon.width) {
                if nativeLimits.count >= 8 { nativeLimits.removeAll() }
                nativeLimits[context] = NativeLimit(width: limit, arrangement: arrangement(in: before, spacer: icon))
                rememberedClipping = true
                resizeRetryStatus = "Waiting for room on the left. macOS compressed those icons during growth, so the previous width was restored. Center will resume when room returns."
            }
            if !Task.isCancelled, NSEvent.pressedMouseButtons == 0,
               !recordedResizeFailure || result == .unsafeOrder || rememberedClipping {
                recordSafetyStop(before: before, after: after, original: original, requested: width,
                                 comparison: comparison, clippingConfirmed: rememberedClipping,
                                 verificationReads: verificationReads)
                recordedResizeFailure = true
            }
            if result == .retry {
                retryNotBefore = Date().addingTimeInterval(3)
                publish("Waiting for macOS to finish updating menu bar positions. Previous width kept; Center will retry automatically.")
            } else {
                publish("Icon order could not be verified after resizing. Previous width restored; Center paused for safety. Click Center to try again.")
            }
            return result
        }
        if verificationReads > 1 {
            delayedVerificationCount += 1
            logger.notice("Growth verification settled after \(verificationReads) readouts.")
        }
        publish("Sized to \(Int(width)) pt; visible icon order checked.")
#if SPACEBAR_LOCAL_DIAGNOSTICS
        diagnosticResult = "applied"
#endif
        return .applied
    }

    /// Keep only the latest safety failure, without labels or menu contents.
    /// A future report can distinguish a real order change from missing proxies.
    private func recordSafetyStop(before: MenuBarReadout, after: MenuBarReadout,
                                  original: Double, requested: Double,
                                  comparison: (before: [LayoutIcon], after: [LayoutIcon]),
                                  clippingConfirmed: Bool, verificationReads: Int) {
        guard let owner else { return }
        func snapshot(_ readout: MenuBarReadout) -> [[String: Any]] {
            readout.icons.map { icon in
                ["bundleID": icon.bundleID, "displayID": icon.displayID,
                 "frame": [icon.left, icon.top, icon.width, icon.height],
                 "proxyToken": icon.id.uuidString]
            }
        }
        let continuity = comparison.before.compactMap { icon -> [String: String]? in
            guard icon.identifier.hasPrefix("SpaceBar.Resize."),
                  let other = comparison.after.first(where: { $0.identifier == icon.identifier }) else { return nil }
            return ["before": icon.id.uuidString, "after": other.id.uuidString]
        }
        let record: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()),
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "originalLength": original, "requestedLength": requested,
            "clippingConfirmed": clippingConfirmed, "verificationReads": verificationReads,
            "before": snapshot(before), "after": snapshot(after),
            "beforeCoherent": FlexResizeSafety.isCoherent(before.icons),
            "afterCoherent": FlexResizeSafety.isCoherent(after.icons),
            "proxyContinuity": continuity]
        do {
            let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: owner.store.url.deletingLastPathComponent().appendingPathComponent("flex-last-safety-stop.json"), options: .atomic)
        } catch { logger.error("Could not save the local flex safety-stop diagnostic.") }
    }

    private func availableRoom(for id: UUID) async -> (maximum: Double, before: MenuBarReadout, apps: [LayoutApp], screens: [LayoutScreen], icon: LayoutIcon, context: CapacityContext)? {
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
        let allowsOverflow = owner.configuration.items.first(where: { $0.id == id })?.flex?.allowsLeftOverflow == true
        let others = before.icons.filter { $0.displayID == icon.displayID && $0.identifier != identifier }
        // Overlapping frames normally mean a non-atomic read. The one allowed
        // exception is a recognized leading group behind native overflow.
        guard FlexResizeSafety.isCoherent(before.icons) ||
            (allowsOverflow && FlexNativeOverflow.isRecognized(spacer: icon, others: others)) else { return nil }
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
              let leftmost = before.icons.filter({ $0.displayID == icon.displayID }).map(\.left).min() else {
            return nil
        }
        let context = CapacityContext(display: icon.displayID, menuOwner: pid,
            menuRight: menuRight.rounded(), screenLeft: screen.bounds.minX, screenWidth: screen.bounds.width)
        let leftmostAbsolute = screen.bounds.minX + leftmost
        guard let nominalCapacity = FlexSafety.maximumWidth(current: original,
            leftmostIcon: leftmostAbsolute, applicationMenuRight: menuRight) else { return nil }
        // A native refusal is valid for the actual surrounding icons/processes.
        // Added/removed/rearranged icons can invalidate it even when their net
        // width happens to leave the leftmost coordinate almost unchanged.
        if let limit = nativeLimits[context] {
            if limit.arrangement != arrangement(in: before, spacer: icon) ||
                !limit.width.applies(toRightEdge: screen.bounds.minX + icon.left + icon.width) {
                nativeLimits.removeValue(forKey: context)
            }
        }
        // Width + left edge is unchanged by our own resize/rollback. Only an
        // external gain in room increases a previously rejected native limit.
        let nativeCapacity = nativeLimits[context]?.width.maximumWidth(current: original, leftmostIcon: leftmostAbsolute)
        let capacity: Double
        if allowsOverflow {
            nativeLimits.removeValue(forKey: context)
            // Keep the entire spacer on this display. The OS may hide leading
            // status items, but centering cannot push the gap off-screen.
            capacity = max(6, icon.left + icon.width - max(0, icon.width - original))
        } else { capacity = min(nominalCapacity, nativeCapacity ?? nominalCapacity) }
#if SPACEBAR_LOCAL_DIAGNOSTICS
        lastCapacityDetails = ["menuOwnerPID": Int(pid), "ownPID": Int(ProcessInfo.processInfo.processIdentifier),
            "menuOwnerBundle": apps.first(where: { $0.pid == pid })?.bundleID ?? "unknown",
            "menuRight": menuRight, "nominalCapacity": nominalCapacity, "leftmost": leftmostAbsolute,
            "currentLength": original, "capacity": capacity,
            "allowsLeftOverflow": allowsOverflow,
            "leftmostBundle": before.icons.min(by: { $0.left < $1.left })?.bundleID ?? "unknown"]
#endif
        return (capacity, before, apps, screens, icon, context)
    }

    private func arrangement(in readout: MenuBarReadout, spacer: LayoutIcon) -> FlexBarArrangement {
        FlexBarArrangement(spacer: spacer, icons: readout.icons,
            owners: readout.targets.mapValues { $0.app.pid })
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

    func rebalance() {
        guard let owner, let item = owner.configuration.items.first(where: { $0.kind == .flexSpacer }),
              let settings = item.flex, let controller = owner.controllers[item.id] else {
            publish("Add a flex spacer to keep a gap centered."); return
        }
        guard settings.isEnabled, canMonitor else { return }
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
            // A new right-hand anchor is fresh external evidence. Never make
            // it wait through the backoff for an earlier, different layout.
            if let previous = lastFrame, abs(previous.maxX - frame.maxX) > 2 {
                retryNotBefore = nil
                // This must also happen in the cheap own-frame poll: a return
                // to center needs no resize/full scan, but still ends the old
                // failure's lifetime before a later move back to its position.
                nativeLimits = nativeLimits.filter { context, limit in
                    context.display != screen.display.id || limit.width.applies(toRightEdge: frame.maxX)
                }
            }
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
                publish("Checking the spacer’s anchor before Center can continue…"); return
            }
            let width = max(6, result.width - padding)
            // Apply the verified target once. Fixed 24 pt increments caused a
            // visible staircase and repeated full-bar scans for one change.
            // Backoff applies only to growth; shrinking must remain responsive.
            if width > Double(controller.statusItem.length) + 1,
               let retryNotBefore, Date() < retryNotBefore {
                publish(resizeRetryStatus); return
            }
            if abs(controller.statusItem.length - width) > 1 {
                let resize = await resizeSafely(item.id, to: width)
                guard resize == .applied else {
                    if generation == measurementGeneration, canMonitor, !Task.isCancelled,
                       owner.configuration.items.first(where: { $0.id == item.id }) == item {
                        if resize == .unsafeOrder { pause(item, message: status) }
                        else {
                            if resizeRequiresRecovery { wait(resizeRetryStatus) }
                            else {
                                // Read-only capacity refusal needs no anchor
                                // recovery cycle. Keep heavy scans bounded;
                                // the cheap own-frame poll still sees changes.
                                retryNotBefore = Date().addingTimeInterval(1.5)
                                publish(resizeRetryStatus)
                            }
                        }
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
        safetyPause = (item.id, message)
        logger.notice("Center paused for safety: \(message, privacy: .public)")
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
    private let allowOverflow = NSButton(checkboxWithTitle: "Keep centered when left icons overflow", target: nil, action: nil)
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
        allowOverflow.target = self; allowOverflow.action = #selector(toggleOverflow)
        allowOverflow.toolTip = "Allow macOS to put leftmost icons in its hidden menu bar area when the gap grows."
        addArrangedSubview(allowOverflow)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        addArrangedSubview(status); status.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        refresh(item, number: owner.number(for: id))
    }
    required init?(coder: NSCoder) { fatalError("Not implemented") }
    func refresh(_ item: ItemConfiguration, number: Int) {
        title.stringValue = "Flex Spacer \(number)"
        enable.title = item.flex?.isEnabled == true ? "Pause" : "Center"
        show.title = item.isHighlighted ? "Hide" : "Show"
        allowOverflow.state = item.flex?.allowsLeftOverflow == true ? .on : .off
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
        for control in [arrange, enable, show, minimum, maximum, allowOverflow] as [NSControl] { control.isEnabled = owner?.layoutManager.isBusy != true && owner?.flexCoordinator.isAdjusting != true && !isSaving }
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
    @objc private func toggleOverflow() { owner?.setFlexAllowsLeftOverflow(id, enabled: allowOverflow.state == .on) }
    @objc private func deleteItem() { owner?.remove(id) }
}
