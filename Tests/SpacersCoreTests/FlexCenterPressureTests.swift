import Foundation
import Testing
@testable import SpacersCore

@Test func capturedCenterCrossingCollapsesToOnePointWithoutChangingSavedLimits() throws {
    var settings = FlexSettings()
    settings.minimumWidth = 428; settings.minimumGap = 6; settings.maximumWidth = 3000
    let saved = settings
    // Native capture: length 424, frame [756, 0, 428, 30], center 1280.
    let padding = 4.0
    let result = try #require(FlexGeometry.solve(rightEdge: 1184, center: 1280, screenLeft: 0,
        minimum: settings.centeringMinimumWidth + padding, maximum: settings.maximumWidth + padding,
        protectedMinimum: 6 + padding, emergencyMinimum: FlexGeometry.emergencyWidth + padding))
    #expect(result.width - padding == 1)
    #expect(result.rightSideCrowded && !result.isCentered)
    #expect(1184 - result.width == 1179) // Reclaims 423 points on the left.
    #expect(settings == saved)
}

@Test func emergencyThresholdIsTheActualCenterAndNormalMinimumReturnsAfterward() throws {
    for edge in [1279.0, 1280] {
        let result = try #require(FlexGeometry.solve(rightEdge: edge, center: 1280, screenLeft: 0,
            minimum: 100, maximum: 3004, protectedMinimum: 10, emergencyMinimum: 5))
        #expect(result.width == 5 && result.rightSideCrowded && !result.isCentered)
    }
    let returned = try #require(FlexGeometry.solve(rightEdge: 1300, center: 1280, screenLeft: 0,
        minimum: 100, maximum: 3004, protectedMinimum: 10, emergencyMinimum: 5))
    #expect(returned.width == 100 && returned.isMinimumLimited && !returned.rightSideCrowded)
    let centered = try #require(FlexGeometry.solve(rightEdge: 1494, center: 1280, screenLeft: 0,
        minimum: 100, maximum: 3004, protectedMinimum: 10, emergencyMinimum: 5))
    #expect(centered.width - 4 == 424 && centered.isCentered)
}

@Test func emergencySizingIncludesNativePaddingAndWorksWithNegativeDisplayOrigins() throws {
    for padding in [0.0, 4, 16] {
        let result = try #require(FlexGeometry.solve(rightEdge: -800, center: -720, screenLeft: -1440,
            minimum: 220 + padding, maximum: 1600 + padding, protectedMinimum: 180 + padding,
            emergencyMinimum: 1 + padding))
        #expect(result.width - padding == 1 && result.rightSideCrowded)
        // A notch or large normal floor must not preserve an oversized gap
        // after right-hand icons already cross the actual display midpoint.
    }
    #expect(FlexGeometry.solve(rightEdge: 100, center: 720, screenLeft: 0,
        minimum: 220, maximum: 500, emergencyMinimum: .nan) == nil)
    #expect(FlexGeometry.solve(rightEdge: 100, center: 720, screenLeft: 0,
        minimum: 220, maximum: 500, emergencyMinimum: 0) == nil)
}

@Test func emergencyWidthDoesNotStrandGrowthCapacityWhenIconsMoveBack() throws {
    let capacity = try #require(FlexSafety.maximumWidth(current: 1, leftmostIcon: 900, applicationMenuRight: 400))
    #expect(capacity == 477)
    let limit = try #require(FlexGrowthLimit(current: 1, leftmostIcon: 900, rightEdge: 1494))
    #expect(limit.maximumWidth(current: 1, leftmostIcon: 950) == 51)
    var recovery = FlexRecoveryGate(); recovery.wait()
    let first = recovery.canResume(rightEdge: 1494, displayID: "main")
    let second = recovery.canResume(rightEdge: 1494, displayID: "main")
    #expect(!first && second)
}

@Test func pausingAndLayoutSnapshotsKeepValidSettingsAfterEmergencyCollapse() throws {
    var item = ItemConfiguration(kind: .flexSpacer)
    item.flex?.isEnabled = true; item.flex?.minimumGap = 6
    let id = item.id, autosave = item.autosaveName, settings = item.flex
    // Appearance refresh must leave the one-point live item under Center's
    // control; saving a snapshot or pausing uses the valid manual minimum.
    #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 1) == nil)
    item.width = StatusItemSizing.savedFlexWidth(from: 1)
    try item.validate()
    #expect(item.width == 6 && item.flex == settings)
    item.flex?.isEnabled = false
    try item.validate()
    #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 1) == 6)
    #expect(StatusItemSizing.savedFlexWidth(from: 424) == 424)
    #expect(item.id == id && item.autosaveName == autosave && item.flex?.minimumGap == 6)
}

@Test func onePointRuntimeStillResolvesItsExistingNativeStatusItem() throws {
    let id = UUID(), bundle = "local.samuelaviv.MenuBarSpacers"
    let own = LayoutIcon(bundleID: bundle, appName: "SpaceBar", identifier: "", label: "",
        displayID: "main", left: 1179, top: 0, width: 5, height: 30)
    let padding = try #require(MenuBarHostPadding.measure(lengths: [1], hostWidths: [5]))
    let resolution = OwnMenuBarMatching.resolve(lengths: [id: 1], icons: [own],
        bundleID: bundle, displayID: "main", expectedPadding: padding)
    #expect(resolution.matches[id] == own.id)
    #expect(resolution.padding?.points == 4)
}
