import Foundation
import CoreGraphics

public struct FlexSettings: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var minimumWidth: Double = 220
    public var maximumWidth: Double = 1600
    // Older builds used minimumWidth for both manual width and the auto floor.
    // Keep it for compatible snapshots; only this distinct field sets the floor.
    public var minimumGap: Double?
    public var allowsLeftOverflow: Bool?
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

/// A rejected native growth does not become safe merely because its rollback
/// restored the old positions. Retain the last accepted width, allowing extra
/// growth only when external reflow actually frees room on the left.
public struct FlexGrowthLimit: Sendable {
    public let acceptedWidth: Double
    public let normalizedLeft: Double
    public let referenceRightEdge: Double?
    public init?(current: Double, leftmostIcon: Double, rightEdge: Double? = nil) {
        guard current.isFinite, current >= 6, leftmostIcon.isFinite,
              (leftmostIcon + current).isFinite,
              rightEdge?.isFinite != false else { return nil }
        acceptedWidth = current
        normalizedLeft = leftmostIcon + current
        referenceRightEdge = rightEdge
    }
    /// A last accepted width is not a measured physical maximum. Do not carry
    /// that refusal across a different right-hand anchor, including a return
    /// to center followed by another icon-width change.
    public func applies(toRightEdge rightEdge: Double) -> Bool {
        guard rightEdge.isFinite else { return false }
        return referenceRightEdge.map { abs($0 - rightEdge) <= 2 } ?? true
    }
    public func maximumWidth(current: Double, leftmostIcon: Double) -> Double? {
        guard current.isFinite, current >= 6, leftmostIcon.isFinite else { return nil }
        let available = acceptedWidth + leftmostIcon + current - normalizedLeft
        guard available.isFinite else { return nil }
        return max(current, available)
    }
}

/// Describes which icons surround the spacer, independently of the positions
/// changed by resizing it or of frequently changing numeric icon widths.
/// A refused width belongs to this arrangement, not every future arrangement
/// that happens to have the same leftmost coordinate.
public struct FlexBarArrangement: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        let bundle: String
        let identifier: String
        let owner: Int32
        let side: Int
    }
    private let entries: [Entry]

    public init(spacer: LayoutIcon, icons: [LayoutIcon], owners: [UUID: Int32] = [:]) {
        entries = icons.filter { $0.displayID == spacer.displayID && $0.id != spacer.id }
            .sorted { $0.left < $1.left }.map { icon in
                let side = icon.left + icon.width <= spacer.left + 1 ? -1 :
                    (icon.left >= spacer.left + spacer.width - 1 ? 1 : 0)
                return Entry(bundle: icon.bundleID, identifier: icon.identifier,
                             owner: owners[icon.id] ?? 0, side: side)
            }
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

public enum FlexResizeResult: Equatable, Sendable {
    case applied
    case retry
    case unsafeOrder
}

public enum FlexResizeSafety {
    /// Witness native clipping during a rejected normal resize: our anchor is
    /// fixed and multiple neighbors moved correctly, but other identified left
    /// items overlap each other or a system overflow control. The returned
    /// position confirms repeated clipping; it is not a capacity estimate.
    public static func observedLeftBoundary(before: LayoutIcon, after: LayoutIcon?, growth: Double,
                                            othersBefore: [LayoutIcon], othersAfter: [LayoutIcon]) -> Double? {
        guard let after, after.displayID == before.displayID, growth.isFinite, growth > 2,
              abs(after.width - before.width - growth) <= 2,
              abs(after.left + after.width - before.left - before.width) <= 2,
              isCoherent([before] + othersBefore) else { return nil }
        var shifted = 0, fixedRight = 0
        var clamped: [LayoutIcon] = []
        var displaced: [LayoutIcon] = []
        for old in othersBefore where old.identifier.hasPrefix("SpaceBar.Resize.") {
            let matches = othersAfter.filter { $0.identityKey == old.identityKey }
            guard matches.count == 1, let new = matches.first,
                  abs(new.width - old.width) <= 0.5 else { continue }
            if old.left >= before.left + before.width - 1, abs(new.left - old.left) <= 2 { fixedRight += 1 }
            if old.left + old.width <= before.left + 1, new.left + new.width <= after.left + 1 {
                let expected = old.left - growth
                if abs(new.left - expected) <= 2 { shifted += 1 }
                else {
                    displaced.append(new)
                    if new.left > expected + 2 { clamped.append(new) }
                }
            }
        }
        guard shifted >= 2, fixedRight >= 1 else { return nil }
        if clamped.count >= 2, !isCoherent(clamped) { return clamped.map(\.left).min() }
        let clippedBySystemControl = displaced.filter { item in
            othersAfter.contains { control in
                control.bundleID == "com.apple.MenuBarAgent" &&
                control.left + control.width <= after.left + 1 &&
                min(item.left + item.width, control.left + control.width) - max(item.left, control.left) > 1
            }
        }
        return clippedBySystemControl.map(\.left).min()
    }

    /// MenuBarAgent's attributes are read one at a time. During reflow they can
    /// describe overlapping old/new positions, which cannot prove icon order.
    public static func isCoherent(_ icons: [LayoutIcon]) -> Bool {
        guard icons.allSatisfy({ $0.left.isFinite && $0.width.isFinite && $0.width > 0 }) else { return false }
        for group in Dictionary(grouping: icons, by: \.displayID).values {
            let sorted = group.sorted { $0.left < $1.left }
            for (left, right) in zip(sorted, sorted.dropFirst()) {
                if left.left + left.width > right.left + 1 { return false }
            }
        }
        return true
    }

    /// The adapter supplies only one-to-one equal native proxies with verified
    /// owner PIDs. These temporary IDs are for one resize comparison only;
    /// they never enter a saved layout or assign identities by width/position.
    public static func withProxyContinuity(before: [LayoutIcon], after: [LayoutIcon],
                                           matches: [UUID: UUID]) -> (before: [LayoutIcon], after: [LayoutIcon]) {
        var old = before, new = after
        let targetCounts = Dictionary(grouping: matches.values, by: { $0 }).mapValues(\.count)
        let valid = matches.filter { source, destination in
            let sources = before.filter { $0.id == source }, destinations = after.filter { $0.id == destination }
            return sources.count == 1 && destinations.count == 1 && targetCounts[destination] == 1 &&
                sources[0].bundleID == destinations[0].bundleID && sources[0].displayID == destinations[0].displayID
        }
        // Partial matching must not turn the disappearance of an ambiguous
        // group member into a supposedly identifiable removal. Retain the old
        // conservative count/width checks unless the entire group is paired.
        var excluded = Set<UUID>()
        let anonymousGroups = Dictionary(grouping: before.filter { $0.identifier.isEmpty }, by: {
            $0.bundleID + "\u{0}" + $0.displayID
        })
        for group in anonymousGroups.values {
            guard let first = group.first else { continue }
            let counterparts = after.filter {
                $0.identifier.isEmpty && $0.bundleID == first.bundleID && $0.displayID == first.displayID
            }
            let destinations = Set(group.compactMap { valid[$0.id] })
            if group.count != counterparts.count || destinations != Set(counterparts.map(\.id)) {
                excluded.formUnion(group.map(\.id))
            }
        }
        for (source, destination) in valid where !excluded.contains(source) {
            let sources = old.indices.filter { old[$0].id == source }
            let destinations = new.indices.filter { new[$0].id == destination }
            guard sources.count == 1, destinations.count == 1, targetCounts[destination] == 1,
                  let i = sources.first, let j = destinations.first,
                  old[i].bundleID == new[j].bundleID, old[i].displayID == new[j].displayID else { continue }
            let temporaryID = "SpaceBar.Resize.\(source.uuidString)"
            old[i].identifier = temporaryID; new[j].identifier = temporaryID
        }
        return (old, new)
    }

    /// A delayed own frame is not evidence of reordering. Keep the previous
    /// size and retry when the visible order is still verified. Missing or
    /// ambiguous OTHER items remain a safety stop, as before.
    public static func verifyGrowth(originalLength: Double, requestedLength: Double,
                                    before: LayoutIcon, after: LayoutIcon?,
                                    othersBefore: [LayoutIcon], othersAfter: [LayoutIcon]) -> FlexResizeResult {
        guard let after, after.displayID == before.displayID,
              originalLength.isFinite, requestedLength.isFinite, requestedLength > originalLength,
              [before, after].allSatisfy({ icon in
                  icon.left.isFinite && icon.width.isFinite && icon.width > 0
              }), (othersBefore + othersAfter).allSatisfy({ icon in
                  icon.displayID == before.displayID && icon.left.isFinite && icon.width.isFinite && icon.width > 0
              }), isCoherent([before] + othersBefore),
              isCoherent([after] + othersAfter) else { return .retry }
        func signature(_ icons: [LayoutIcon]) -> [String] {
            icons.sorted { $0.left < $1.left }.map {
                "\($0.bundleID)|\($0.identifier)|\(($0.width * 2).rounded())"
            }
        }
        let orderPreserved = signature(othersBefore) == signature(othersAfter) ||
            visibleItemsPreserved(before: othersBefore, after: othersAfter)
        guard orderPreserved else {
            return environmentChangedWithoutReordering(before: othersBefore, after: othersAfter)
                ? .retry : .unsafeOrder
        }
        let sizeApplied = abs(after.width - before.width - requestedLength + originalLength) <= 2
        let anchorStable = abs(after.left + after.width - before.left - before.width) <= 2
        return sizeApplied && anchorStable ? .applied : .retry
    }

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
