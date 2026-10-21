import Foundation
import Testing
@testable import SpacersCore

private func host(_ id: String, left: Double, width: Double, bundle: String = "test") -> LayoutIcon {
    LayoutIcon(bundleID: bundle, appName: "Test", identifier: id, label: "",
               displayID: "main", left: left, top: 0, width: width, height: 30)
}

@Test(arguments: [0.0, 4.0, 16.0])
func delayedOwnSizeKeepsCenterRecoverable(padding: Double) throws {
    // A host still reporting its pre-resize width previously disabled Center,
    // even though every other icon kept its visible order and width.
    let before = host("flex", left: 1469 - 276 - padding, width: 276 + padding)
    let others = [host("left", left: 600, width: 24), host("right", left: 1500, width: 24)]
    func verify(_ after: LayoutIcon?) -> FlexResizeResult {
        FlexResizeSafety.verifyGrowth(originalLength: 276, requestedLength: 374,
            before: before, after: after, othersBefore: others, othersAfter: others)
    }
    #expect(verify(before) == .retry)
    #expect(verify(nil) == .retry)
    #expect(verify(host("flex", left: before.left - 40, width: before.width + 40)) == .retry)
    let settled = host("flex", left: before.left - 98, width: before.width + 98)
    #expect(verify(settled) == .applied)

    var recovery = FlexRecoveryGate()
    recovery.wait()
    let first = recovery.canResume(rightEdge: 1469, displayID: "main")
    let second = recovery.canResume(rightEdge: 1469, displayID: "main")
    #expect(!first && second)
    let centered = try #require(FlexGeometry.solve(rightEdge: 1469, center: 1280, screenLeft: 0,
        minimum: 6 + padding, maximum: 3000 + padding, protectedMinimum: 6 + padding))
    #expect(centered.isCentered && 1469 - centered.width / 2 == 1280)
}

@Test func movedRightAnchorAndDynamicIconSizeWaitRatherThanDisableCenter() {
    let before = host("flex", left: 1189, width: 280)
    let after = host("flex", left: 1081, width: 378) // right group moved 10 pt left
    let others = [host("left", left: 600, width: 24), host("weather", left: 1500, width: 40)]
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 276, requestedLength: 374,
        before: before, after: after, othersBefore: others, othersAfter: others) == .retry)
    let changed = [others[0], host("weather", left: 1490, width: 50)]
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 276, requestedLength: 374,
        before: before, after: before, othersBefore: others, othersAfter: changed) == .retry)
}

@Test func anUnsafeOtherIconOrderStillStopsEvenWhenOwnFrameLags() {
    let before = host("flex", left: 1189, width: 280)
    let others = [host("left", left: 600, width: 24), host("right", left: 1500, width: 24)]
    let swapped = [host("right", left: 600, width: 24), host("left", left: 1500, width: 24)]
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 276, requestedLength: 374,
        before: before, after: before, othersBefore: others, othersAfter: swapped) == .unsafeOrder)
    let anonymous = [host("", left: 600, width: 16), host("", left: 1500, width: 24)]
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 276, requestedLength: 374,
        before: before, after: before, othersBefore: anonymous, othersAfter: [anonymous[0]]) == .unsafeOrder)
}

@Test func addedSystemProxyAndExistingOrderRemainSafeAfterVerifiedGrowth() {
    let before = host("flex", left: 1189, width: 280)
    let after = host("flex", left: 1091, width: 378)
    let others = [host("left", left: 646, width: 24), host("clock", left: 2431, width: 109)]
    let added = [host("", left: 500, width: 17.5, bundle: "com.apple.MenuBarAgent"),
                 host("left", left: 548, width: 24), others[1]]
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 276, requestedLength: 374,
        before: before, after: after, othersBefore: others, othersAfter: added) == .applied)
}

@Test func foreignOrInvalidGrowthReadoutsCannotApproveAResize() {
    let before = host("flex", left: 1189, width: 280)
    var after = host("flex", left: 1091, width: 378)
    after.displayID = "other"
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 276, requestedLength: 374,
        before: before, after: after, othersBefore: [], othersAfter: []) == .retry)
    after.displayID = "main"; after.width = .nan
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 276, requestedLength: 374,
        before: before, after: after, othersBefore: [], othersAfter: []) == .retry)
}
