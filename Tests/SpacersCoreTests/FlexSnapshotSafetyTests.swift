import Foundation
import Testing
@testable import SpacersCore

private func proxy(_ bundle: String, _ x: Double, _ width: Double, display: String = "main") -> LayoutIcon {
    LayoutIcon(bundleID: bundle, appName: "Test", identifier: "", label: "",
        displayID: display, left: x, top: 0, width: width, height: 30)
}

@Test func capturedOverlappingHostReadingsWaitInsteadOfReportingReordering() {
    // Read-only native capture: two successive snapshots contained 26/17 pt
    // overlaps at the left and a 16 pt overlap among system proxies. Later
    // snapshots settled without overlaps. No resize or drag produced this.
    let first = [proxy("A", 495, 33), proxy("B", 502, 26), proxy("C", 511, 17)]
    let second = [proxy("system", 2098, 20), proxy("system", 2102, 22)]
    #expect(!FlexResizeSafety.isCoherent(first))
    #expect(!FlexResizeSafety.isCoherent(second))
    let own = proxy("own", 1195, 268)
    let grown = proxy("own", 1097, 366)
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 264, requestedLength: 362,
        before: own, after: grown, othersBefore: first, othersAfter: second) == .retry)
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 264, requestedLength: 362,
        before: own, after: grown, othersBefore: second, othersAfter: first) == .retry)
}

@Test func coherenceAllowsSeparateDisplaysAndRoundingButRejectsInvalidGeometry() {
    let left = proxy("A", -100, 20)
    #expect(FlexResizeSafety.isCoherent([left, proxy("B", -81, 25)])) // 1 pt tolerance
    #expect(!FlexResizeSafety.isCoherent([left, proxy("B", -82, 25)]))
    #expect(FlexResizeSafety.isCoherent([left, proxy("B", -100, 20, display: "other")]))
    #expect(!FlexResizeSafety.isCoherent([proxy("A", .nan, 20)]))
    #expect(!FlexResizeSafety.isCoherent([proxy("A", 10, .infinity)]))
    #expect(!FlexResizeSafety.isCoherent([proxy("A", 10, 0)]))
}

@Test func verifiedAnonymousProxiesCanChangeWidthWithoutPermanentlyDisablingCenter() {
    let own = proxy("own", 1195, 268), grown = proxy("own", 1097, 366)
    let old = [proxy("system", 1800, 22), proxy("system", 1900, 21)]
    let new = [proxy("system", 1800, 22), proxy("system", 1900, 20)]
    // The old anonymous-group check cannot distinguish a changing width from
    // swapped items. Native proxy equality provides the missing evidence.
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 264, requestedLength: 362,
        before: own, after: grown, othersBefore: old, othersAfter: new) == .unsafeOrder)
    let paired = FlexResizeSafety.withProxyContinuity(before: old, after: new,
        matches: [old[0].id: new[0].id, old[1].id: new[1].id])
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 264, requestedLength: 362,
        before: own, after: grown, othersBefore: paired.before, othersAfter: paired.after) == .retry)
    let settled = [proxy("system", 1800, 22), proxy("system", 1900, 20)]
    let fresh = FlexResizeSafety.withProxyContinuity(before: new, after: settled,
        matches: [new[0].id: settled[0].id, new[1].id: settled[1].id])
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 264, requestedLength: 362,
        before: own, after: grown, othersBefore: fresh.before, othersAfter: fresh.after) == .applied)
    #expect(old.allSatisfy { $0.identifier.isEmpty } && new.allSatisfy { $0.identifier.isEmpty })
}

@Test func equalWidthAnonymousProxySwapStillTriggersTheOrderSafetyStop() {
    let own = proxy("own", 1195, 268), grown = proxy("own", 1097, 366)
    let old = [proxy("same", 1800, 22), proxy("same", 1900, 22)]
    let new = [proxy("same", 1900, 22), proxy("same", 1800, 22)]
    let paired = FlexResizeSafety.withProxyContinuity(before: old, after: new,
        matches: [old[0].id: new[0].id, old[1].id: new[1].id])
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 264, requestedLength: 362,
        before: own, after: grown, othersBefore: paired.before, othersAfter: paired.after) == .unsafeOrder)
}

@Test func continuityRefusesDuplicateForeignAndWrongDisplayPairings() {
    let old = [proxy("same", 1800, 22), proxy("same", 1900, 22)]
    let new = [proxy("same", 1800, 22)]
    let duplicate = FlexResizeSafety.withProxyContinuity(before: old, after: new,
        matches: [old[0].id: new[0].id, old[1].id: new[0].id])
    #expect(duplicate.before == old && duplicate.after == new)
    let foreign = [proxy("foreign", 1800, 22)]
    let foreignPair = FlexResizeSafety.withProxyContinuity(before: old, after: foreign,
        matches: [old[0].id: foreign[0].id])
    #expect(foreignPair.before == old && foreignPair.after == foreign)
    let secondary = [proxy("same", 1800, 22, display: "secondary")]
    let displayPair = FlexResizeSafety.withProxyContinuity(before: old, after: secondary,
        matches: [old[0].id: secondary[0].id])
    #expect(displayPair.before == old && displayPair.after == secondary)
}

@Test func partialAnonymousContinuityDoesNotAuthorizeMissingGroupMembers() {
    let own = proxy("own", 1195, 268), grown = proxy("own", 1097, 366)
    let old = [proxy("same", 1800, 16), proxy("same", 1900, 24)]
    let missing = [proxy("same", 1800, 16)]
    let paired = FlexResizeSafety.withProxyContinuity(before: old, after: missing,
        matches: [old[0].id: missing[0].id])
    #expect(paired.before == old && paired.after == missing)
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 264, requestedLength: 362,
        before: own, after: grown, othersBefore: paired.before, othersAfter: paired.after) == .unsafeOrder)
    let replaced = [proxy("same", 1800, 16), proxy("same", 1900, 32)]
    let ambiguous = FlexResizeSafety.withProxyContinuity(before: old, after: replaced,
        matches: [old[0].id: replaced[0].id])
    #expect(ambiguous.before == old && ambiguous.after == replaced)
    #expect(FlexResizeSafety.verifyGrowth(originalLength: 264, requestedLength: 362,
        before: own, after: grown, othersBefore: ambiguous.before, othersAfter: ambiguous.after) == .unsafeOrder)
}
