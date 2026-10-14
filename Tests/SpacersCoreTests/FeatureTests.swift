import Foundation
import CoreGraphics
import Testing
@testable import SpacersCore

@Test func flexCompensatesTwiceTheRightGroupMovementWithoutDrift() throws {
    let initial = try #require(FlexGeometry.solve(rightEdge: 900, center: 720, screenLeft: 0, minimum: 220, maximum: 1400))
    let removed = try #require(FlexGeometry.solve(rightEdge: 910, center: 720, screenLeft: 0, minimum: 220, maximum: 1400))
    let added = try #require(FlexGeometry.solve(rightEdge: 890, center: 720, screenLeft: 0, minimum: 220, maximum: 1400))
    #expect(initial.width == 360 && initial.isCentered)
    #expect(removed.width == initial.width + 20 && added.width == initial.width - 20)
    #expect(900 - initial.width / 2 == 720)
    #expect(910 - removed.width / 2 == 720)
    #expect(890 - added.width / 2 == 720)
    #expect(FlexGeometry.solve(rightEdge: 900, center: 720, screenLeft: 0, minimum: 220, maximum: 1400) == initial)
}

@Test func flexLimitsProtectTheGapAndReportImpossibleCentering() throws {
    let limited = try #require(FlexGeometry.solve(rightEdge: 760, center: 720, screenLeft: 0, minimum: 220, maximum: 1400))
    #expect(limited.width == 220 && limited.isMinimumLimited && !limited.isCentered)
    #expect(!limited.rightSideCrowded) // A chosen minimum is not a physical collision.
    let crowded = try #require(FlexGeometry.solve(rightEdge: 722, center: 720, screenLeft: 0, minimum: 220, maximum: 1400))
    #expect(crowded.rightSideCrowded && crowded.isMinimumLimited)
    let capped = try #require(FlexGeometry.solve(rightEdge: 1400, center: 720, screenLeft: 0, minimum: 220, maximum: 500))
    #expect(capped.width == 500 && !capped.isCentered && !capped.rightSideCrowded)
    #expect(FlexGeometry.solve(rightEdge: .nan, center: 720, screenLeft: 0, minimum: 220, maximum: 500) == nil)
    #expect(FlexGeometry.solve(rightEdge: 100, center: 720, screenLeft: 0, minimum: 220, maximum: 500) == nil)
    let secondary = try #require(FlexGeometry.solve(rightEdge: -540, center: -720, screenLeft: -1440, minimum: 220, maximum: 1400))
    #expect(secondary.width == 360 && secondary.isCentered)
}

@Test func legacyStartingWidthDoesNotPreventCompensatingForANewIcon() throws {
    let legacy = try JSONDecoder().decode(FlexSettings.self, from: Data(
        #"{"isEnabled":false,"minimumWidth":428,"maximumWidth":1600}"#.utf8))
    try legacy.validate()
    #expect(legacy.minimumWidth == 428 && legacy.minimumGap == nil)
    #expect(legacy.centeringMinimumWidth == 6)
    // Native hosts include four points of padding around the configured width.
    let padding = 4.0
    let before = try #require(FlexGeometry.solve(rightEdge: 1496, center: 1280, screenLeft: 0,
        minimum: legacy.centeringMinimumWidth + padding, maximum: legacy.maximumWidth + padding,
        protectedMinimum: 6 + padding))
    let weather = try #require(FlexGeometry.solve(rightEdge: 1436, center: 1280, screenLeft: 0,
        minimum: legacy.centeringMinimumWidth + padding, maximum: legacy.maximumWidth + padding,
        protectedMinimum: 6 + padding))
    #expect(before.width - padding == 428)
    #expect(weather.width - padding == 308 && weather.isCentered && !weather.rightSideCrowded)
    #expect(1436 - weather.width / 2 == 1280)
    let returned = FlexGeometry.solve(rightEdge: 1496, center: 1280, screenLeft: 0,
        minimum: legacy.centeringMinimumWidth + padding, maximum: legacy.maximumWidth + padding,
        protectedMinimum: 6 + padding)
    #expect(returned == before)
}

@Test func protectedNotchAndChosenMinimumAreIndependent() throws {
    let chosenLimit = try #require(FlexGeometry.solve(rightEdge: 850, center: 720, screenLeft: 0,
        minimum: 300, maximum: 1400, protectedMinimum: 180))
    #expect(chosenLimit.width == 300 && chosenLimit.isMinimumLimited && !chosenLimit.rightSideCrowded)
    let notchCollision = try #require(FlexGeometry.solve(rightEdge: 800, center: 720, screenLeft: 0,
        minimum: 300, maximum: 1400, protectedMinimum: 180))
    #expect(notchCollision.rightSideCrowded)
    #expect(FlexGeometry.solve(rightEdge: 850, center: 720, screenLeft: 0,
        minimum: 6, maximum: 150, protectedMinimum: 180) == nil)
}

@Test func explicitMinimumGapRoundTripsAndRejectsInvalidValues() throws {
    var settings = FlexSettings()
    settings.minimumGap = 96
    try settings.validate()
    let decoded = try JSONDecoder().decode(FlexSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings && decoded.centeringMinimumWidth == 96)
    for invalid in [Double.nan, .infinity, 5, 1601] {
        settings.minimumGap = invalid
        #expect(throws: (any Error).self) { try settings.validate() }
    }
}

@Test func crowdedFlexRegainsCenterAfterStableSpaceReturns() throws {
    var gate = FlexRecoveryGate()
    let centered = try #require(FlexGeometry.solve(rightEdge: 900, center: 720, screenLeft: 0, minimum: 6, maximum: 1400))
    let crowded = try #require(FlexGeometry.solve(rightEdge: 718, center: 720, screenLeft: 0, minimum: 6, maximum: 1400))
    #expect(centered.isCentered && crowded.rightSideCrowded)
    gate.wait()
    #expect(gate.isWaiting)
    let firstReading = gate.canResume(rightEdge: 900, displayID: "main")
    let secondReading = gate.canResume(rightEdge: 901, displayID: "main")
    #expect(!firstReading && secondReading)
    let recovered = try #require(FlexGeometry.solve(rightEdge: 900, center: 720, screenLeft: 0, minimum: 6, maximum: 1400))
    #expect(!gate.isWaiting && recovered == centered)
}

@Test func secondaryDisplayMenuAllowsMainDisplayCompensation() throws {
    // Captured from the user's Sidecar-focused ChatGPT menu and M27Q spacer.
    let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let sidecar = CGRect(x: 1847, y: 1440, width: 1324, height: 993)
    let bar = CGRect(x: 1847, y: 1440, width: 1324, height: 30)
    let items = [(1857.0, 34.0), (1890, 79), (1968, 42), (2009, 44),
                 (2052, 50), (2101, 70), (2170, 49)].map { CGRect(x: $0.0, y: 1440, width: $0.1, height: 30) }
    let boundary = try #require(ApplicationMenuGeometry.rightEdge(menuBar: bar, items: items,
        targetDisplay: main, knownDisplays: [main, sidecar]))
    #expect(boundary == 372)
    let capacity = try #require(FlexSafety.maximumWidth(current: 276, leftmostIcon: 746, applicationMenuRight: boundary))
    let solution = try #require(FlexGeometry.solve(rightEdge: 1469, center: 1280, screenLeft: 0,
        minimum: 10, maximum: 1604, protectedMinimum: 10))
    #expect(solution.width == 378 && solution.width - 4 <= capacity && solution.isCentered)
    #expect(1469 - solution.width / 2 == 1280)
}

@Test func menuBoundaryWorksWithNegativeAndStackedDisplayOrigins() throws {
    let source = CGRect(x: -1728, y: 323, width: 1728, height: 1117)
    let target = CGRect(x: -518, y: 1440, width: 960, height: 540)
    let bar = CGRect(x: -1728, y: 323, width: 1728, height: 30)
    let items = [CGRect(x: -1718, y: 323, width: 34, height: 30), CGRect(x: -1684, y: 323, width: 280, height: 30)]
    #expect(ApplicationMenuGeometry.rightEdge(menuBar: bar, items: items,
        targetDisplay: target, knownDisplays: [source, target]) == -194)
    #expect(ApplicationMenuGeometry.rightEdge(menuBar: bar, items: items,
        targetDisplay: source, knownDisplays: [source, target]) == -1404)
}

@Test func menuBoundaryRejectsVirtualOrIncompleteGeometry() {
    let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let bar = CGRect(x: 0, y: 0, width: 1440, height: 30)
    let item = CGRect(x: 10, y: 0, width: 300, height: 30)
    #expect(ApplicationMenuGeometry.rightEdge(menuBar: bar, items: [], targetDisplay: display, knownDisplays: [display]) == nil)
    #expect(ApplicationMenuGeometry.rightEdge(menuBar: bar.offsetBy(dx: 100, dy: 100), items: [item], targetDisplay: display, knownDisplays: [display]) == nil)
    #expect(ApplicationMenuGeometry.rightEdge(menuBar: bar, items: [item.offsetBy(dx: 0, dy: 50)], targetDisplay: display, knownDisplays: [display]) == nil)
    #expect(ApplicationMenuGeometry.rightEdge(menuBar: bar, items: [CGRect(x: 10, y: 0, width: 900, height: 30)], targetDisplay: display, knownDisplays: [display]) == nil)
    #expect(ApplicationMenuGeometry.rightEdge(menuBar: bar, items: [CGRect(x: 10, y: 0, width: 1500, height: 30)], targetDisplay: display, knownDisplays: [display]) == nil)
}

@Test func dynamicIconsCanSettleWithoutDisablingCenter() {
    func icon(_ id: String, _ left: Double, _ width: Double) -> LayoutIcon {
        LayoutIcon(bundleID: "app", appName: "App", identifier: id, label: "", displayID: "main", left: left, top: 0, width: width, height: 30)
    }
    let before = [icon("left", 400, 20), icon("weather", 600, 20), icon("clock", 900, 80)]
    let widthChanged = [icon("left", 380, 20), icon("weather", 580, 40), icon("clock", 900, 80)]
    #expect(FlexResizeSafety.environmentChangedWithoutReordering(before: before, after: widthChanged))
    #expect(FlexResizeSafety.environmentChangedWithoutReordering(before: before, after: [before[0], before[2]]))
    #expect(!FlexResizeSafety.environmentChangedWithoutReordering(before: before, after: before))
    #expect(!FlexResizeSafety.environmentChangedWithoutReordering(before: before, after: []))
    let reordered = [icon("weather", 400, 40), icon("left", 600, 20), icon("clock", 900, 80)]
    #expect(!FlexResizeSafety.environmentChangedWithoutReordering(before: before, after: reordered))
}

@Test func ambiguousIconChangesDoNotAuthorizeAutomaticResizeRetry() {
    let first = LayoutIcon(bundleID: "ambiguous", appName: "App", identifier: "", label: "", displayID: "main", left: 400, top: 0, width: 16, height: 30)
    var second = first; second.left = 500; second.width = 24
    #expect(!FlexResizeSafety.environmentChangedWithoutReordering(before: [first, second], after: [first]))
    var changed = second; changed.width = 32
    #expect(!FlexResizeSafety.environmentChangedWithoutReordering(before: [first, second], after: [first, changed]))
}

@Test func newSystemProxyDoesNotImplyExistingIconsWereReordered() {
    func icon(_ bundle: String, _ id: String, _ left: Double, _ width: Double) -> LayoutIcon {
        LayoutIcon(bundleID: bundle, appName: "App", identifier: id, label: "", displayID: "main", left: left, top: 0, width: width, height: 30)
    }
    let before = [icon("app", "left", 646, 24), icon("system", "clock", 2431, 109)]
    // Captured failure: a new anonymous MenuBarAgent proxy at x=588, width17.5.
    let after = [icon("com.apple.MenuBarAgent", "", 588, 17.5),
                 icon("app", "left", 548, 24), before[1]]
    #expect(FlexResizeSafety.visibleItemsPreserved(before: before, after: after))
    #expect(!FlexResizeSafety.visibleItemsPreserved(before: before, after: [after[0], before[1]]))
    #expect(!FlexResizeSafety.visibleItemsPreserved(before: before, after: [icon("system", "clock", 500, 109), before[0]]))
    #expect(!FlexResizeSafety.visibleItemsPreserved(before: before, after: [icon("app", "left", 548, 32), before[1]]))
    let anonymous = [icon("same", "", 500, 16), icon("same", "", 600, 24)]
    #expect(!FlexResizeSafety.visibleItemsPreserved(before: anonymous, after: [anonymous[0]]))
    #expect(!FlexResizeSafety.visibleItemsPreserved(before: anonymous, after: anonymous + [icon("same", "", 700, 16)]))
}

@Test func recoveryWaitsForConsistentGeometryAndRejectsStaleDisplays() {
    var gate = FlexRecoveryGate()
    gate.wait()
    var readings: [Bool] = []
    for (edge, display) in [(900.0, "main"), (940, "main"), (940, "new-main"),
                            (.nan, "new-main"), (940, "new-main"), (940, "new-main")] {
        readings.append(gate.canResume(rightEdge: edge, displayID: display))
    }
    #expect(readings == [false, false, false, false, false, true])
    gate.wait()
    gate.reset() // Manual Pause/Arrange cancels the pending recovery.
    #expect(!gate.isWaiting)
}

@Test func addingFlexKeepsLegacyItemsUnchangedAndRoundTripsItsLimits() throws {
    let original = ItemConfiguration(kind: .spacer)
    var flexible = ItemConfiguration(kind: .flexSpacer)
    flexible.flex?.isEnabled = true
    flexible.flex?.minimumWidth = 240
    flexible.flex?.maximumWidth = 1500
    var config = Configuration(items: [original, flexible]); config.version = 2
    try config.validate()
    let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
    #expect(decoded == config && decoded.items.first == original)
    var invalid = config
    invalid.items[1].flex?.maximumWidth = 200
    #expect(throws: (any Error).self) { try invalid.validate() }
    invalid = config; invalid.items.append(ItemConfiguration(kind: .flexSpacer))
    #expect(throws: (any Error).self) { try invalid.validate() }
}

private func icon(identifier: String = "stable", label: String = "Old title", left: Double = 800, bundle: String = "app.test", display: String = "screen") -> LayoutIcon {
    LayoutIcon(bundleID: bundle, appName: "Test", identifier: identifier, label: label,
               displayID: display, left: left, top: 0, width: 24, height: 24)
}

@Test func layoutMatchingUsesStableIdentityAndNeverGuessesAmbiguousIcons() {
    let saved = icon()
    var changed = saved; changed.id = UUID(); changed.label = "New title"; changed.left = 600
    #expect(LayoutMatching.match(saved, in: [changed]) == changed)
    var invalid = saved; invalid.occurrence = 1
    #expect(LayoutMatching.match(invalid, in: [changed]) == nil)
    #expect(LayoutMatching.match(saved, in: [icon(bundle: "other.app")]) == nil)
    #expect(LayoutMatching.match(saved, in: [icon(display: "other.screen")]) == nil)
    #expect(LayoutMatching.match(saved, in: [changed, icon(left: 700)]) == nil)
    #expect(LayoutMatching.match(icon(identifier: "", label: ""), in: [icon(identifier: "", label: "")]) == nil)
    let noIdentifier = icon(identifier: "", label: "An icon")
    #expect(LayoutMatching.match(noIdentifier, in: [icon(identifier: "", label: "Changed")]) == nil)
    #expect(LayoutMatching.match(noIdentifier, in: [noIdentifier]) == noIdentifier)
}

@Test func layoutsSaveSeparatelyAndRejectDamageWithoutOverwriting() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let configurationStore = ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
    let original = Configuration(items: [ItemConfiguration(kind: .divider)])
    try configurationStore.save(original)
    let originalBytes = try Data(contentsOf: configurationStore.url)
    let store = LayoutStore(url: folder.appendingPathComponent("layouts.json"))
    #expect(try store.load().layouts.isEmpty)
    var library = LayoutLibrary()
    library.layouts.append(MenuBarLayout(name: "Work", configuration: original,
        displays: [LayoutDisplay(id: "screen", name: "Display", width: 1440, height: 900)], icons: [icon()]))
    try store.save(library)
    #expect(try store.load() == library)
    #expect(try Data(contentsOf: configurationStore.url) == originalBytes)
    let bytes = try Data(contentsOf: store.url)
    var invalid = library; invalid.layouts[0].icons[0].left = .infinity
    #expect(throws: (any Error).self) { try store.save(invalid) }
    #expect(try Data(contentsOf: store.url) == bytes)
    let damaged = Data("not json".utf8); try damaged.write(to: store.url)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try Data(contentsOf: store.url) == damaged)
}

@Test func flexCapacityLeavesRoomForApplicationMenusAndExistingIcons() throws {
    let capacity = try #require(FlexSafety.maximumWidth(current: 200, leftmostIcon: 700, applicationMenuRight: 400))
    #expect(capacity == 476)
    #expect(500 > capacity) // growing to 500 would hide the leftmost icon
    #expect(FlexSafety.maximumWidth(current: 200, leftmostIcon: 410, applicationMenuRight: 400) == 200)
    #expect(FlexSafety.maximumWidth(current: 200, leftmostIcon: -700, applicationMenuRight: -1000) == 476)
}

@Test func flexCapacityRejectsUnusableMeasurements() {
    #expect(FlexSafety.maximumWidth(current: 200, leftmostIcon: .nan, applicationMenuRight: 400) == nil)
    #expect(FlexSafety.maximumWidth(current: 5, leftmostIcon: 700, applicationMenuRight: 400) == nil)
    #expect(FlexSafety.maximumWidth(current: 200, leftmostIcon: 700, applicationMenuRight: 400, margin: -1) == nil)
}
