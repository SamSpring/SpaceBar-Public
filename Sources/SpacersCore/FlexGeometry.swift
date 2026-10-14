import Foundation
import CoreGraphics

public struct FlexSettings: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var minimumWidth: Double = 220
    public var maximumWidth: Double = 1600
    // Older builds used minimumWidth for both manual width and the auto floor.
    // Keep it for compatible snapshots; only this distinct field sets the floor.
    public var minimumGap: Double?
    public var centeringMinimumWidth: Double { minimumGap ?? 6 }
    public init() {}
    public func validate() throws {
        guard minimumWidth.isFinite, maximumWidth.isFinite,
              (6...3000).contains(minimumWidth), (minimumWidth...3000).contains(maximumWidth),
              centeringMinimumWidth.isFinite, (6...maximumWidth).contains(centeringMinimumWidth) else {
            throw ConfigurationError.invalidValue("Flex gap limits")
        }
    }
}

public struct FlexSolution: Equatable, Sendable {
    public let width: Double
    public let isCentered: Bool
    public let rightSideCrowded: Bool
    public let isMinimumLimited: Bool
}

public enum FlexGeometry {
    /// The right edge follows the right-hand icon group. Changing width moves
    /// only the left edge: R - width / 2 = the fixed display center.
    public static func solve(rightEdge: Double, center: Double, screenLeft: Double,
                             minimum: Double, maximum: Double, protectedMinimum: Double = 6) -> FlexSolution? {
        guard [rightEdge, center, screenLeft, minimum, maximum, protectedMinimum].allSatisfy(\.isFinite),
              rightEdge > screenLeft, minimum >= 6, protectedMinimum >= 6,
              maximum >= max(minimum, protectedMinimum) else { return nil }
        let wanted = 2 * (rightEdge - center)
        let available = min(maximum, rightEdge - screenLeft)
        let lower = max(minimum, protectedMinimum)
        guard available >= lower else { return nil }
        let width = min(available, max(lower, wanted)).rounded()
        return FlexSolution(width: width, isCentered: abs(wanted - width) <= 1,
                            rightSideCrowded: wanted < protectedMinimum,
                            isMinimumLimited: wanted < lower)
    }
}

/// A blocked spacer stays enabled, but waits for two consistent, visible
/// measurements before resizing again. This avoids reacting to a transient host.
public struct FlexRecoveryGate: Sendable {
    public private(set) var isWaiting = false
    private var candidateEdge: Double?
    private var candidateDisplay: String?
    public init() {}
    public mutating func wait() {
        isWaiting = true; candidateEdge = nil; candidateDisplay = nil
    }
    public mutating func reset() { self = FlexRecoveryGate() }
    public mutating func canResume(rightEdge: Double, displayID: String) -> Bool {
        guard rightEdge.isFinite, !displayID.isEmpty else { wait(); return false }
        guard isWaiting else { return true }
        if candidateDisplay == displayID, let previous = candidateEdge, abs(previous - rightEdge) <= 2 {
            reset(); return true
        }
        candidateEdge = rightEdge; candidateDisplay = displayID
        return false
    }
}

/// Conservative capacity: consume only the presently empty space between the
/// application menus and the leftmost visible status item, leaving a margin.
public enum FlexSafety {
    public static func maximumWidth(current: Double, leftmostIcon: Double,
                                    applicationMenuRight: Double, margin: Double = 24) -> Double? {
        guard [current, leftmostIcon, applicationMenuRight, margin].allSatisfy(\.isFinite),
              current >= 6, margin >= 0 else { return nil }
        return current + max(0, leftmostIcon - applicationMenuRight - margin)
    }
}

/// An application's AX menu bar follows the focused display. Measure its menu
/// extent relative to that verified bar, then express it on the spacer display.
/// Never accept virtual/off-screen bars or a partial set of menu item frames.
public enum ApplicationMenuGeometry {
    public static func rightEdge(menuBar: CGRect, items: [CGRect], targetDisplay: CGRect,
                                 knownDisplays: [CGRect]) -> Double? {
        func valid(_ rect: CGRect) -> Bool {
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
        }
        guard valid(menuBar), valid(targetDisplay), !items.isEmpty, items.count <= 32,
              knownDisplays.contains(where: { display in
                  valid(display) && abs(menuBar.minX - display.minX) <= 2 &&
                  abs(menuBar.minY - display.minY) <= 8 && abs(menuBar.width - display.width) <= 2
              }), items.allSatisfy({ item in
                  valid(item) && item.minX >= menuBar.minX && item.maxX <= menuBar.maxX &&
                  abs(item.minY - menuBar.minY) <= 8 && item.height <= menuBar.height + 8
              }), let extent = items.map({ $0.maxX - menuBar.minX }).max() else { return nil }
        let right = targetDisplay.minX + extent
        guard right > targetDisplay.minX, right < targetDisplay.midX else { return nil }
        return right
    }
}

public enum FlexResizeSafety {
    /// Additional items do not invalidate growth when every pre-existing item
    /// remains visible, in the same order and at the same width. For anonymous
    /// groups, preserve the full count/width sequence rather than guessing IDs.
    public static func visibleItemsPreserved(before: [LayoutIcon], after: [LayoutIcon]) -> Bool {
        let before = before.sorted { $0.left < $1.left }, after = after.sorted { $0.left < $1.left }
        guard !before.isEmpty else { return false }
        let keys = Set(before.map(\.identityKey))
        let retained = after.filter { keys.contains($0.identityKey) }
        return before.map(\.identityKey) == retained.map(\.identityKey) &&
            before.map(\.width) == retained.map(\.width)
    }

    /// A width/count change in other apps is a reason to roll back and wait,
    /// rather than permanently disable Center. Existing identifiable items must
    /// keep their order; ambiguous groups must keep their counts/width sequence.
    public static func environmentChangedWithoutReordering(before: [LayoutIcon], after: [LayoutIcon]) -> Bool {
        let before = before.sorted { $0.left < $1.left }, after = after.sorted { $0.left < $1.left }
        let oldKeys = before.map(\.identityKey), newKeys = after.map(\.identityKey)
        let common = Set(oldKeys).intersection(newKeys)
        guard !common.isEmpty, oldKeys.filter({ common.contains($0) }) == newKeys.filter({ common.contains($0) }) else { return false }
        for key in common {
            let old = before.filter { $0.identityKey == key }, new = after.filter { $0.identityKey == key }
            guard old.count == new.count else { return false }
            if old.count > 1, old.map(\.width) != new.map(\.width) { return false }
        }
        return oldKeys != newKeys || before.map(\.width) != after.map(\.width)
    }
}
