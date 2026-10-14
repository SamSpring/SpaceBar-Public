import Foundation
import Testing
@testable import SpacersCore

@Test func arrangeShrinksCenteredRuntimeEvenWhenSavedWidthIsAlready24() throws {
    // Build-23 VM: stored/manual 24, Center grew runtime to 510, Arrange
    // disabled Center and saved 24 again. The actual native item must shrink.
    var item = ItemConfiguration(kind: .flexSpacer)
    let id = item.id, autosave = item.autosaveName, settings = item.flex
    item.flex?.isEnabled = false
    item.isHighlighted = true
    let width = try #require(StatusItemSizing.widthToApply(for: item, currentWidth: 510))
    #expect(width == 24)
    #expect(item.width == 24 && item.id == id && item.autosaveName == autosave)
    #expect(item.flex?.minimumWidth == settings?.minimumWidth && item.flex?.maximumWidth == settings?.maximumWidth)
    #expect(StatusItemSizing.widthToApply(for: item, currentWidth: width) == nil)
    let model = try #require(MenuBarHostPadding.measure(lengths: [24], hostWidths: [40]))
    #expect(model.fits(width + 16, length: item.width)) // Host should be 40, not the stale 526.
}

@Test func activeCenterAppearanceRefreshNeverResetsTheRuntimeWidth() {
    var item = ItemConfiguration(kind: .flexSpacer)
    item.flex?.isEnabled = true
    #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 510) == nil)
    item.isHighlighted = true
    #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 510) == nil)
    item.isHighlighted = false
    item.opacity = 0.76
    #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 544) == nil)
}

@Test func ordinaryPauseKeepsTheCapturedRuntimeWidthAndShowsItsSavedValue() throws {
    var item = ItemConfiguration(kind: .flexSpacer)
    item.flex?.isEnabled = true
    let runtime = 510.0
    // toggleFlex already captures this runtime width before disabling Center.
    item.width = runtime
    item.flex?.isEnabled = false
    let decoded = try JSONDecoder().decode(ItemConfiguration.self, from: JSONEncoder().encode(item))
    try decoded.validate()
    #expect(decoded.width == runtime && decoded.flex?.isEnabled == false)
    #expect(StatusItemSizing.widthToApply(for: decoded, currentWidth: runtime) == nil)
}

@Test func pausedWidthsAreAppliedPreciselyAndUnchangedLengthsAreLeftAlone() {
    for kind in [ItemKind.spacer, .divider, .flexSpacer] {
        var item = ItemConfiguration(kind: kind)
        item.width = 18
        #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 24) == 18)
        #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 18) == nil)
        item.isHighlighted = true
        #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 18) == nil)
    }
}

@Test func repeatedArrangeAndReturningToCenterDoNotReplaceIdentityOrAutomaticLimits() {
    var item = ItemConfiguration(kind: .flexSpacer)
    item.flex?.minimumGap = 96
    item.flex?.maximumWidth = 1200
    let id = item.id, limits = item.flex
    #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 510) == 24)
    #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 24) == nil)
    item.flex?.isEnabled = true
    #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 24) == nil)
    #expect(StatusItemSizing.widthToApply(for: item, currentWidth: 510) == nil)
    #expect(item.id == id && item.flex?.minimumGap == limits?.minimumGap && item.flex?.maximumWidth == limits?.maximumWidth)
}
