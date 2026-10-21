import Foundation
import Testing
@testable import SpacersCore

private func overflowIcon(_ bundle: String, _ x: Double, _ width: Double, top: Double = 0, height: Double = 30) -> LayoutIcon {
    LayoutIcon(bundleID: bundle, appName: "Test", identifier: "", label: "",
        displayID: "main", left: x, top: top, width: width, height: height)
}

private struct OverflowFixture {
    var before = overflowIcon("own", 1179, 268)
    var after = overflowIcon("own", 1113, 334)
    var old = [overflowIcon("A", 566, 26), overflowIcon("B", 592, 33),
        overflowIcon("C", 625, 26), overflowIcon("D", 651, 26),
        overflowIcon("stats", 677, 125), overflowIcon("right", 1447, 24)]
    var new = [overflowIcon("A", 525, 26), overflowIcon("B", 518, 33),
        overflowIcon("C", 559, 26), overflowIcon("D", 585, 26),
        overflowIcon("stats", 611, 125), overflowIcon("right", 1447, 24),
        overflowIcon("com.apple.MenuBarAgent", 534, 17.5, top: 1, height: 27)]
    var matches: [UUID: UUID] { Dictionary(uniqueKeysWithValues: zip(old, new).map { ($0.id, $1.id) }) }
    func verify(matches explicit: [UUID: UUID]? = nil) -> FlexResizeResult {
        FlexNativeOverflow.verifyGrowth(originalLength: 264, requestedLength: 330,
            before: before, after: after, othersBefore: old, othersAfter: new, matches: explicit ?? matches)
    }
}

@Test func capturedNativeOverflowAllowsCenteringOnlyThroughTheSeparatePolicy() {
    let f = OverflowFixture()
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 264, requestedLength: 330,
        before: f.before, after: f.after, othersBefore: f.old, othersAfter: f.new) == .retry)
    #expect(FlexNativeOverflow.isRecognized(spacer: f.after, others: f.new))
    #expect(FlexNativeOverflow.hiddenCount(spacer: f.after, others: f.new) == 2)
    #expect(f.verify() == .applied)
}

@Test func nativeOverflowCanContinueGrowingWithoutNeedingACoherentHiddenGroup() {
    let f = OverflowFixture()
    var next = f.new
    // The hidden group and native control stay at the boundary. All visible
    // left neighbors move by the requested delta; right neighbors stay fixed.
    for i in 2...4 { next[i].left -= 8 }
    let own = overflowIcon("own", 1105, 342)
    let matches = Dictionary(uniqueKeysWithValues: zip(f.new, next).map { ($0.id, $1.id) })
    #expect(FlexNativeOverflow.verifyGrowth(originalLength: 330, requestedLength: 338,
        before: f.after, after: own, othersBefore: f.new, othersAfter: next, matches: matches) == .applied)
}

@Test func overflowMayResolveWhenTheNativeMenuBoundaryMovesLeft() {
    let f = OverflowFixture()
    var next = f.new.dropLast().map { $0 }
    next[0].left = 499; next[1].left = 525
    for i in 2...4 { next[i].left -= 1 }
    let own = overflowIcon("own", 1112, 335)
    let matches = Dictionary(uniqueKeysWithValues: zip(f.new, next).map { ($0.id, $1.id) })
    #expect(FlexResizeSafety.isCoherent([own] + next))
    #expect(FlexNativeOverflow.verifyGrowth(originalLength: 330, requestedLength: 331,
        before: f.after, after: own, othersBefore: f.new, othersAfter: next, matches: matches) == .applied)
}

@Test func actualVisibleReorderingIsStillAStopWithNativeOverflow() {
    var f = OverflowFixture()
    let original = f.matches
    let left = f.new[2].left
    f.new[2].left = f.new[3].left; f.new[3].left = left
    #expect(f.verify(matches: original) == .unsafeOrder)
}

@Test func overflowNeverAuthorizesMovingRightIconsOrTheSpacerAnchor() {
    var f = OverflowFixture()
    f.new[5].left += 8
    #expect(f.verify() == .retry)
    f = OverflowFixture(); f.after.left += 8
    #expect(f.verify() == .retry)
    f = OverflowFixture(); f.after = f.before
    #expect(f.verify() == .retry)
}

@Test func overflowRequiresEveryNativeObjectWithUniqueVerifiedOwnership() {
    let f = OverflowFixture()
    var partial = f.matches; partial.removeValue(forKey: f.old[0].id)
    #expect(f.verify(matches: partial) == .retry)
    var duplicate = f.matches; duplicate[f.old[0].id] = duplicate[f.old[1].id]
    #expect(f.verify(matches: duplicate) == .retry)
    var missing = f; missing.new.removeFirst()
    #expect(missing.verify(matches: f.matches) == .retry)
    var foreign = f; foreign.new[0].bundleID = "different-owner"
    #expect(foreign.verify() == .retry)
    var extra = f; extra.new.append(overflowIcon("new-app", 1800, 20))
    #expect(extra.verify(matches: f.matches) == .retry)
}

@Test func unrelatedOverlapsCannotBeMistakenForNativeOverflow() {
    var f = OverflowFixture()
    f.new[6].bundleID = "other-app"
    #expect(!FlexNativeOverflow.isRecognized(spacer: f.after, others: f.new))
    #expect(f.verify() == .retry)
    f = OverflowFixture(); f.new[6].height = 30
    #expect(f.verify() == .retry)
    f = OverflowFixture(); f.new.append(overflowIcon("nonleading", 400, 20))
    #expect(!FlexNativeOverflow.isRecognized(spacer: f.after, others: f.new))
    f = OverflowFixture(); f.new[3].left = f.new[2].left
    #expect(f.verify() == .retry)
    f = OverflowFixture(); f.new.append(f.new[0])
    #expect(f.verify() == .retry)
}

@Test func previousFlexSettingsRemainOptedOutUntilExplicitlyChanged() throws {
    let json = Data("{\"isEnabled\":true,\"minimumWidth\":428,\"maximumWidth\":3000,\"minimumGap\":6}".utf8)
    let previous = try JSONDecoder().decode(FlexSettings.self, from: json)
    #expect(previous.allowsLeftOverflow == nil)
    var item = ItemConfiguration(kind: .flexSpacer)
    item.flex = previous; item.width = 264
    let original = item
    item.flex?.allowsLeftOverflow = true
    let config = Configuration(items: [item])
    try config.validate()
    let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
    #expect(restored.items[0].id == original.id)
    #expect(restored.items[0].autosaveName == original.autosaveName)
    #expect(restored.items[0].width == 264)
    #expect(restored.items[0].flex?.allowsLeftOverflow == true)
    var roundTrip = restored.items[0]; roundTrip.flex?.allowsLeftOverflow = nil
    #expect(roundTrip == original)
}
