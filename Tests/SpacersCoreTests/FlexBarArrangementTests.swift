import Foundation
import Testing
@testable import SpacersCore

private func barIcon(_ bundle: String, _ x: Double, _ width: Double, identifier: String = "") -> LayoutIcon {
    LayoutIcon(bundleID: bundle, appName: "Test", identifier: identifier, label: "",
        displayID: "main", left: x, top: 0, width: width, height: 30)
}

@Test func rejectedArrangementSurvivesOwnGrowthRollbackAndMetricWidthJitter() {
    let spacer = barIcon("spacebar", 1171, 316, identifier: "own")
    let before = [barIcon("codex", 532, 26), barIcon("stats", 558, 123), spacer,
                  barIcon("right", 1487, 26)]
    let reference = FlexBarArrangement(spacer: spacer, icons: before)
    var grown = spacer; grown.left -= 98; grown.width += 98
    let after = [barIcon("codex", 434, 26), barIcon("stats", 460, 123), grown,
                 barIcon("right", 1487, 26)]
    #expect(reference == FlexBarArrangement(spacer: grown, icons: after))
    #expect(reference == FlexBarArrangement(spacer: spacer, icons: before))
    var fluctuating = before
    fluctuating[0].left -= 2; fluctuating[1].left -= 2; fluctuating[1].width += 2
    fluctuating[1].label = "A changing numeric reading"
    #expect(reference == FlexBarArrangement(spacer: spacer, icons: fluctuating))
}

@Test func changedIconSetInvalidatesAnOldRefusalEvenAtTheSameLeftEdge() {
    let spacer = barIcon("spacebar", 1171, 316)
    let first = barIcon("codex", 532, 26), oldItem = barIcon("old-app", 558, 26)
    let reference = FlexBarArrangement(spacer: spacer, icons: [first, oldItem, spacer])
    let replaced = barIcon("new-app", 558, 26)
    #expect(reference != FlexBarArrangement(spacer: spacer, icons: [first, replaced, spacer]))
    #expect(reference != FlexBarArrangement(spacer: spacer, icons: [first, spacer]))
    #expect(reference != FlexBarArrangement(spacer: spacer, icons: [first, oldItem, replaced, spacer]))
}

@Test func externalOrderAndMovingTheSpacerAcrossAnIconInvalidateOldLimits() {
    let spacer = barIcon("spacebar", 1171, 316)
    let left = barIcon("left", 532, 26), right = barIcon("right", 1487, 26)
    let reference = FlexBarArrangement(spacer: spacer, icons: [left, spacer, right])
    var switchedLeft = left, switchedRight = right
    switchedLeft.left = right.left; switchedRight.left = left.left
    #expect(reference != FlexBarArrangement(spacer: spacer, icons: [switchedLeft, spacer, switchedRight]))
    var moved = spacer; moved.left = 100
    #expect(reference != FlexBarArrangement(spacer: moved, icons: [left, moved, right]))
}

@Test func restartedOwnersAndChangedExplicitIdentifiersInvalidateOldLimits() {
    let spacer = barIcon("spacebar", 1171, 316)
    let item = barIcon("app", 532, 26, identifier: "one")
    let reference = FlexBarArrangement(spacer: spacer, icons: [item, spacer], owners: [item.id: 100])
    #expect(reference != FlexBarArrangement(spacer: spacer, icons: [item, spacer], owners: [item.id: 101]))
    var changed = item; changed.identifier = "two"
    #expect(reference != FlexBarArrangement(spacer: spacer, icons: [changed, spacer], owners: [changed.id: 100]))
}

@Test func OtherDisplayItemsCannotRearmALocalGrowthRefusal() {
    let spacer = barIcon("spacebar", 1171, 316), item = barIcon("app", 532, 26)
    var remote = barIcon("remote", 100, 26); remote.displayID = "other"
    let reference = FlexBarArrangement(spacer: spacer, icons: [item, spacer])
    #expect(reference == FlexBarArrangement(spacer: spacer, icons: [item, spacer, remote]))
}

@Test func capturedOctoberGapNeedsOneFullTargetRatherThanAStaircase() throws {
    let solution = try #require(FlexGeometry.solve(rightEdge: 1487, center: 1280, screenLeft: 0,
        minimum: 10, maximum: 3004, protectedMinimum: 10))
    #expect(solution.isCentered && solution.width == 414)
    let nativeTarget = solution.width - 4
    #expect(nativeTarget == 410 && nativeTarget - 312 == 98)
    let room = try #require(FlexSafety.maximumWidth(current: 312, leftmostIcon: 532, applicationMenuRight: 372))
    #expect(room == 448 && nativeTarget <= room)
    // Nominal room is not a promise of native acceptance. Existing growth
    // verification and rollback still decide whether the target is safe.
}
