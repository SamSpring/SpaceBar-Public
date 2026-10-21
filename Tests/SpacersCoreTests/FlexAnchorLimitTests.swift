import Testing
@testable import SpacersCore

@Test func caughtRejectedWidthBelongsToItsOffCenterAnchor() throws {
    let limit = try #require(FlexGrowthLimit(current: 330, leftmostIcon: 549, rightEdge: 1496))
    #expect(limit.applies(toRightEdge: 1496))
    #expect(limit.maximumWidth(current: 330, leftmostIcon: 549) == 330)
    let offCenter = try #require(FlexGeometry.solve(rightEdge: 1496, center: 1280, screenLeft: 0,
        minimum: 10, maximum: 3004, protectedMinimum: 10))
    #expect(offCenter.width - 4 == 428)
    // The actual 49 pt anchor movement makes the unchanged width centered.
    let returned = try #require(FlexGeometry.solve(rightEdge: 1447, center: 1280, screenLeft: 0,
        minimum: 10, maximum: 3004, protectedMinimum: 10))
    #expect(returned.isCentered && returned.width - 4 == 330)
    #expect(!limit.applies(toRightEdge: 1447))
    // The coordinator removes this refusal on that cheap centered read, so a
    // later return to 1496 must be verified afresh rather than inherit it.
}

@Test func ownResizeAndRollbackDoNotInvalidateAnAnchorScopedRefusal() throws {
    let limit = try #require(FlexGrowthLimit(current: 330, leftmostIcon: 549, rightEdge: 1496))
    // The native host's four-point padding stays outside its length.
    #expect(limit.applies(toRightEdge: 1162 + 334))
    #expect(limit.applies(toRightEdge: 1064 + 432))
    #expect(limit.applies(toRightEdge: 1162 + 334))
    #expect(limit.maximumWidth(current: 330, leftmostIcon: 549) == 330)
}

@Test func nativeRoundingDoesNotRepeatedlyRearmARefusedGrowth() throws {
    let limit = try #require(FlexGrowthLimit(current: 330, leftmostIcon: 549, rightEdge: 1496))
    #expect(limit.applies(toRightEdge: 1494))
    #expect(limit.applies(toRightEdge: 1497.5))
    #expect(!limit.applies(toRightEdge: 1499))
    #expect(!limit.applies(toRightEdge: .nan))
    #expect(!limit.applies(toRightEdge: .infinity))
}

@Test func invalidAnchorCannotCreateARememberedNativeLimit() {
    #expect(FlexGrowthLimit(current: 330, leftmostIcon: 549, rightEdge: .infinity) == nil)
    #expect(FlexGrowthLimit(current: 330, leftmostIcon: 549, rightEdge: .nan) == nil)
}
