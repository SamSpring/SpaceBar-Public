import Foundation
import Testing
@testable import SpacersCore

private let ownBundle = "local.samuelaviv.MenuBarSpacers"
private let mainDisplay = "main"
private func proxy(_ width: Double, left: Double = 0, identifier: String = "",
                   bundle: String = ownBundle, display: String = mainDisplay) -> LayoutIcon {
    LayoutIcon(bundleID: bundle, appName: "SpaceBar", identifier: identifier, label: "",
        displayID: display, left: left, top: 0, width: width, height: 30)
}

@Test func hostPaddingMeasuresOrdinaryAndPaddedWidthsWithoutWideningTolerance() throws {
    for points in [0.0, 4, 8, 16] {
        let model = try #require(MenuBarHostPadding.measure(lengths: [12, 61, 12],
            hostWidths: [61 + points, 12 + points, 12 + points]))
        #expect(model.points == points)
        #expect(model.fits(61 + points, length: 61))
        #expect(!model.fits(61 + points + 1, length: 61))
        #expect(!model.fits(61 + points - 1, length: 61))
    }
    let rounded = try #require(MenuBarHostPadding.measure(lengths: [12, 61], hostWidths: [28.25, 76.75]))
    #expect(rounded.points == 16)
    #expect(!rounded.fits(.nan, length: 61))
    #expect(!rounded.fits(77, length: .infinity))
}

@Test func hostPaddingRefusesIncompleteMixedAndInvalidMeasurements() {
    for (lengths, widths) in [([12.0, 61, 12], [28.0, 77]),
                             ([12, 61], [28, 77, 28]),
                             ([12, 61], [28, 65]),
                             ([12, 61], [28, 78.1]),
                             ([12, 61], [11, 60]),
                             ([12, 61], [32, 81]),
                             ([Double.nan], [28]),
                             ([12], [Double.infinity]),
                             ([0], [16]),
                             ([Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude],
                              [Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]),
                             ([], [])] {
        #expect(MenuBarHostPadding.measure(lengths: lengths, hostWidths: widths) == nil)
    }
}

@Test func vmWidthReceiptIdentifiesSpacerButRefusesIdenticalDividers() throws {
    // Geometry from the 14 October native VM receipt: requested 12/61/12,
    // anonymous host widths 28/77/28. No position or array-order assignment.
    let dividerA = UUID(), spacer = UUID(), dividerB = UUID()
    let lengths = [dividerA: 12.0, spacer: 61, dividerB: 12]
    let spacerProxy = proxy(77, left: 1110)
    let icons = [proxy(28, left: 1187), spacerProxy, proxy(28, left: 1082)]
    let result = OwnMenuBarMatching.resolve(lengths: lengths, icons: icons,
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(result.padding?.points == 16)
    #expect(result.matches == [spacer: spacerProxy.id])
    let reversed = OwnMenuBarMatching.resolve(lengths: lengths, icons: icons.reversed(),
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(reversed.matches == result.matches)
    let moved = icons.map { icon in var icon = icon; icon.left = 1400 - icon.left; return icon }
    #expect(OwnMenuBarMatching.resolve(lengths: lengths, icons: moved,
        bundleID: ownBundle, displayID: mainDisplay).matches == result.matches)
}

@Test func paddedFlexRebindsAfterRealWidthChangesAndKeepsItsCenter() throws {
    let dividerA = UUID(), spacer = UUID(), dividerB = UUID(), flex = UUID()
    var lengths = [dividerA: 12.0, spacer: 61, dividerB: 12, flex: 24]
    var icons = [proxy(28), proxy(77), proxy(28), proxy(40, left: 970)]
    var result = OwnMenuBarMatching.resolve(lengths: lengths, icons: icons,
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(result.matches[flex] == icons[3].id)
    let padding = try #require(result.padding).points
    let centered = try #require(FlexGeometry.solve(rightEdge: 1010, center: 720, screenLeft: 0,
        minimum: 6 + padding, maximum: 1600 + padding, protectedMinimum: 6 + padding))
    let width = centered.width - padding
    #expect(width == 564 && centered.isCentered)
    let capacity = try #require(FlexSafety.maximumWidth(current: 24, leftmostIcon: 970, applicationMenuRight: 400))
    #expect(width <= capacity)
    lengths[flex] = width
    icons[3] = proxy(width + padding, left: 1010 - width - padding) // The host replaces its proxy.
    result = OwnMenuBarMatching.resolve(lengths: lengths, icons: icons,
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(result.matches[flex] == icons[3].id && result.padding?.points == padding)
    #expect(icons[3].left + icons[3].width / 2 == 720)
    #expect(result.matches[dividerA] == nil && result.matches[dividerB] == nil)
    let shifted = try #require(FlexGeometry.solve(rightEdge: 1030, center: 720, screenLeft: 0,
        minimum: 6 + padding, maximum: 1600 + padding, protectedMinimum: 6 + padding))
    #expect(shifted.width - padding == width + 40 && shifted.isCentered)
}

@Test func paddingDoesNotConfuseAnOrdinaryFlexWidthWithAPaddedDivider() {
    let divider = UUID(), flex = UUID()
    let dividerProxy = proxy(28), flexProxy = proxy(40)
    let result = OwnMenuBarMatching.resolve(lengths: [divider: 12, flex: 24],
        icons: [flexProxy, dividerProxy], bundleID: ownBundle, displayID: mainDisplay)
    #expect(result.matches == [divider: dividerProxy.id, flex: flexProxy.id])
    // Simply widening the old tolerance to +16 would also match the 28-point
    // divider to the 24-point flex item; the measured model cannot do that.
    #expect(result.padding?.fits(28, length: 24) == false)
}

@Test func incompleteOwnSetCannotInventPaddingFromTheRemainingIcon() {
    let dividerA = UUID(), spacer = UUID(), dividerB = UUID()
    let result = OwnMenuBarMatching.resolve(lengths: [dividerA: 12, spacer: 61, dividerB: 12],
        icons: [proxy(77)], bundleID: ownBundle, displayID: mainDisplay)
    #expect(result.padding == nil && result.matches.isEmpty)
}

@Test func onlyOneOwnItemCanBeBoundFromItsOneVerifiedProxy() {
    let flex = UUID(), visible = proxy(40)
    let result = OwnMenuBarMatching.resolve(lengths: [flex: 24], icons: [visible],
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(result.padding?.points == 16 && result.matches == [flex: visible.id])
}

@Test func foreignAndOtherDisplayIconsCannotAffectOwnIdentity() {
    let divider = UUID(), spacer = UUID(), dividerProxy = proxy(28), spacerProxy = proxy(77)
    let result = OwnMenuBarMatching.resolve(lengths: [divider: 12, spacer: 61],
        icons: [proxy(77, bundle: "other.app"), proxy(77, display: "secondary"), spacerProxy, dividerProxy],
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(result.matches == [divider: dividerProxy.id, spacer: spacerProxy.id])
    #expect(OwnMenuBarMatching.resolve(lengths: [spacer: 61], icons: [proxy(77, bundle: "other.app")],
        bundleID: ownBundle, displayID: mainDisplay).matches.isEmpty)
}

@Test func identicalWidthsAndDuplicateProxiesRemainAmbiguous() {
    let first = UUID(), second = UUID()
    #expect(OwnMenuBarMatching.resolve(lengths: [first: 12, second: 12], icons: [proxy(28), proxy(28)],
        bundleID: ownBundle, displayID: mainDisplay).matches.isEmpty)
    let duplicate = proxy(77)
    #expect(OwnMenuBarMatching.resolve(lengths: [first: 61], icons: [duplicate, duplicate],
        bundleID: ownBundle, displayID: mainDisplay).matches.isEmpty)
    let near = OwnMenuBarMatching.resolve(lengths: [first: 12, second: 12.25], icons: [proxy(28), proxy(28.25)],
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(near.padding?.points == 16 && near.matches.isEmpty)
}

@Test func explicitIdentifiersStayAuthoritativeButDuplicatesAreRefused() {
    let first = UUID(), second = UUID()
    let firstProxy = proxy(28, identifier: OwnMenuBarMatching.identifier(for: first))
    let secondProxy = proxy(28, identifier: OwnMenuBarMatching.identifier(for: second))
    let result = OwnMenuBarMatching.resolve(lengths: [first: 12, second: 12], icons: [firstProxy, secondProxy],
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(result.matches == [first: firstProxy.id, second: secondProxy.id])
    let hiddenNeighbor = OwnMenuBarMatching.resolve(lengths: [first: 12, second: 12], icons: [firstProxy],
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(hiddenNeighbor.padding == nil && hiddenNeighbor.matches == [first: firstProxy.id])
    #expect(OwnMenuBarMatching.resolve(lengths: [first: 12],
        icons: [firstProxy, proxy(28, identifier: firstProxy.identifier)],
        bundleID: ownBundle, displayID: mainDisplay).matches.isEmpty)
}

@Test func laggingResizeCannotBeReinterpretedAsDifferentHostPadding() throws {
    let flex = UUID()
    let padding = try #require(MenuBarHostPadding.measure(lengths: [24], hostWidths: [40]))
    let stale = OwnMenuBarMatching.resolve(lengths: [flex: 32], icons: [proxy(40)],
        bundleID: ownBundle, displayID: mainDisplay, expectedPadding: padding)
    #expect(stale.padding == nil && stale.matches.isEmpty)
    let freshProxy = proxy(48)
    let fresh = OwnMenuBarMatching.resolve(lengths: [flex: 32], icons: [freshProxy],
        bundleID: ownBundle, displayID: mainDisplay, expectedPadding: padding)
    #expect(fresh.padding == padding && fresh.matches == [flex: freshProxy.id])
    // Without a resize expectation, a complete set can measure a genuine host
    // change after wake/display invalidation; no permanent hardcoded offset.
    let recalibrated = OwnMenuBarMatching.resolve(lengths: [flex: 32], icons: [proxy(36)],
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(recalibrated.padding?.points == 4)
}

@Test func freshSpacerIdentitySurvivesConfigurationWidthChangeAndLayoutRoundTrip() throws {
    var configuration = Configuration(items: [ItemConfiguration(kind: .spacer)])
    configuration.items[0].width = 61
    let id = configuration.items[0].id
    var saved = proxy(77, left: 1110)
    let resolution = OwnMenuBarMatching.resolve(lengths: [id: 61], icons: [saved],
        bundleID: ownBundle, displayID: mainDisplay)
    #expect(resolution.matches[id] == saved.id)
    saved.identifier = OwnMenuBarMatching.identifier(for: id)
    let layout = MenuBarLayout(name: "VM regression", configuration: configuration,
        displays: [LayoutDisplay(id: mainDisplay, name: "Test", width: 1440, height: 900)],
        icons: LayoutMatching.stampOccurrences([saved]))
    let decoded = try JSONDecoder().decode(MenuBarLayout.self, from: JSONEncoder().encode(layout))
    try decoded.validate()
    var live = proxy(103, left: 900, identifier: saved.identifier)
    live.label = "Spacer 1"
    #expect(LayoutMatching.match(decoded.icons[0], in: [live]) == live)
    // Old anonymous snapshots stay visual references; no retroactive ID guess.
    let anonymous = proxy(77, left: saved.left)
    #expect(LayoutMatching.match(anonymous, in: [live]) == nil)
}
