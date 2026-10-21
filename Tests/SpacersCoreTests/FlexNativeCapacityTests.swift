import Foundation
import Testing
@testable import SpacersCore

private func capacityIcon(_ bundle: String, _ x: Double, _ width: Double) -> LayoutIcon {
    LayoutIcon(bundleID: bundle, appName: "Test", identifier: "", label: "",
        displayID: "main", left: x, top: 0, width: width, height: 30)
}

private func capturedClamp() -> (LayoutIcon, LayoutIcon, [LayoutIcon], [LayoutIcon]) {
    let own = capacityIcon("own", 1192, 268), grown = capacityIcon("own", 1100, 360)
    let old = [capacityIcon("A", 523, 33), capacityIcon("B", 556, 26), capacityIcon("C", 582, 26),
               capacityIcon("D", 624, 123), capacityIcon("D", 747, 35), capacityIcon("E", 1529, 16)]
    let new = [capacityIcon("A", 491, 33), capacityIcon("B", 498, 26), capacityIcon("C", 498, 26),
               capacityIcon("D", 532, 123), capacityIcon("D", 655, 35), capacityIcon("E", 1529, 16)]
    return (own, grown, old, new)
}

@Test func capturedNativeClampingLimitsGrowthWithoutAnotherProbe() throws {
    let (own, grown, old, new) = capturedClamp()
    let matches = Dictionary(uniqueKeysWithValues: zip(old, new).map { ($0.id, $1.id) })
    let paired = FlexResizeSafety.withProxyContinuity(before: old, after: new, matches: matches)
    let boundary = try #require(FlexResizeSafety.observedLeftBoundary(before: own, after: grown,
        growth: 92, othersBefore: paired.before, othersAfter: paired.after))
    #expect(boundary == 491)
    let nominal = try #require(FlexSafety.maximumWidth(current: 264, leftmostIcon: 523, applicationMenuRight: 372))
    let actual = try #require(FlexSafety.maximumWidth(current: 264, leftmostIcon: 523, applicationMenuRight: max(372, boundary)))
    #expect(nominal == 391 && actual == 272)
    #expect(356 <= nominal && 356 > actual)
    // Removing an icon on the left frees usable room without forgetting the
    // native boundary. A returning right-hand icon instead needs no growth.
    let freed = try #require(FlexSafety.maximumWidth(current: 264, leftmostIcon: 623, applicationMenuRight: boundary))
    #expect(356 <= freed)
    let returned = try #require(FlexGeometry.solve(rightEdge: 1414, center: 1280, screenLeft: 0,
        minimum: 10, maximum: 3004, protectedMinimum: 10))
    #expect(returned.isCentered && returned.width - 4 == 264)
}

@Test func clampingCannotBeLearnedWithoutNativeProxyContinuity() {
    let (own, grown, old, new) = capturedClamp()
    #expect(FlexResizeSafety.observedLeftBoundary(before: own, after: grown,
        growth: 92, othersBefore: old, othersAfter: new) == nil)
}

@Test func movingAnchorOrUnappliedSizeCannotTeachANativeBoundary() {
    let (own, grown, old, new) = capturedClamp()
    let paired = FlexResizeSafety.withProxyContinuity(before: old, after: new,
        matches: Dictionary(uniqueKeysWithValues: zip(old, new).map { ($0.id, $1.id) }))
    var moving = grown; moving.left += 8
    #expect(FlexResizeSafety.observedLeftBoundary(before: own, after: moving,
        growth: 92, othersBefore: paired.before, othersAfter: paired.after) == nil)
    #expect(FlexResizeSafety.observedLeftBoundary(before: own, after: own,
        growth: 92, othersBefore: paired.before, othersAfter: paired.after) == nil)
    var different = grown; different.displayID = "other"
    #expect(FlexResizeSafety.observedLeftBoundary(before: own, after: different,
        growth: 92, othersBefore: paired.before, othersAfter: paired.after) == nil)
}

@Test func rejectedGrowthDoesNotBecomeSafeAfterItsOwnRollback() throws {
    let limit = try #require(FlexGrowthLimit(current: 264, leftmostIcon: 525))
    // Captured compression at x=612 must not be treated as a boundary that
    // expires as soon as rollback puts the first icon back at x=525.
    #expect(limit.maximumWidth(current: 264, leftmostIcon: 525) == 264)
    #expect(limit.maximumWidth(current: 240, leftmostIcon: 549) == 264)
    #expect(limit.maximumWidth(current: 264, leftmostIcon: 525) == 264)
}

@Test func externalRoomReturnsWithoutDiscardingARejectedGrowthLimit() throws {
    let limit = try #require(FlexGrowthLimit(current: 264, leftmostIcon: 525))
    // An icon removed from the left frees 33 pt. A verified 24 pt growth then
    // consumes that room, leaving the same absolute accepted ceiling.
    #expect(limit.maximumWidth(current: 264, leftmostIcon: 558) == 297)
    #expect(limit.maximumWidth(current: 288, leftmostIcon: 534) == 297)
    // Enough external room for the captured full centered target.
    #expect(limit.maximumWidth(current: 264, leftmostIcon: 625) == 364)
}

@Test func lessRoomCannotAuthorizeMoreGrowthOrForceShrinkage() throws {
    let limit = try #require(FlexGrowthLimit(current: 264, leftmostIcon: 525))
    #expect(limit.maximumWidth(current: 264, leftmostIcon: 495) == 264)
    #expect(limit.maximumWidth(current: 168, leftmostIcon: 573) == 216)
    // A small dynamic metric-width change cannot permit another 24 pt step.
    #expect(try #require(limit.maximumWidth(current: 264, leftmostIcon: 527)) < 288)
}

@Test func rejectedGrowthLimitsRefuseInvalidGeometry() {
    #expect(FlexGrowthLimit(current: 5, leftmostIcon: 525) == nil)
    #expect(FlexGrowthLimit(current: .infinity, leftmostIcon: 525) == nil)
    #expect(FlexGrowthLimit(current: 264, leftmostIcon: .nan) == nil)
    let limit = FlexGrowthLimit(current: 264, leftmostIcon: 525)
    #expect(limit?.maximumWidth(current: .nan, leftmostIcon: 525) == nil)
    #expect(limit?.maximumWidth(current: 264, leftmostIcon: .infinity) == nil)
}

@Test func oneClippedIconAndANativeOverflowControlAlsoStopsRepeatedGrowth() throws {
    let own = capacityIcon("own", 1194, 268), grown = capacityIcon("own", 1170, 292)
    let old = [capacityIcon("docker", 525, 33), capacityIcon("codex", 558, 26),
               capacityIcon("launchie", 584, 26), capacityIcon("right", 1462, 24)]
    let moved = [capacityIcon("docker", 493, 33), capacityIcon("codex", 534, 26),
                 capacityIcon("launchie", 560, 26), capacityIcon("right", 1462, 24)]
    let overflow = capacityIcon("com.apple.MenuBarAgent", 509, 17.5)
    let paired = FlexResizeSafety.withProxyContinuity(before: old, after: moved + [overflow],
        matches: Dictionary(uniqueKeysWithValues: zip(old, moved).map { ($0.id, $1.id) }))
    #expect(FlexResizeSafety.observedLeftBoundary(before: own, after: grown, growth: 24,
        othersBefore: paired.before, othersAfter: paired.after) == 493)
    let limit = try #require(FlexGrowthLimit(current: 264, leftmostIcon: 525))
    #expect(limit.maximumWidth(current: 264, leftmostIcon: 525) == 264)
    #expect(FlexResizeSafety.observedLeftBoundary(before: own, after: grown, growth: 24,
        othersBefore: paired.before, othersAfter: Array(paired.after.dropLast())) == nil)
}
