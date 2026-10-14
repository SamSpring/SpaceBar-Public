import Foundation

/// A measured, common difference between our requested lengths and the system's
/// visible host widths. The bound covers observed 0–16 pt host padding; it is
/// never used as a 16-point matching tolerance.
public struct MenuBarHostPadding: Equatable, Sendable {
    public let points: Double
    private static let precision = 0.5
    private static let maximum = 16.0

    public static func measure(lengths: [Double], hostWidths: [Double]) -> Self? {
        guard !lengths.isEmpty, lengths.count == hostWidths.count,
              (lengths + hostWidths).allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let difference = (hostWidths.reduce(0, +) - lengths.reduce(0, +)) / Double(lengths.count)
        guard difference.isFinite, difference >= -precision, difference <= maximum + precision else { return nil }
        let points = min(maximum, max(0, difference))
        // Compare multisets only to measure padding, never to assign identities
        // by sort order. Every visible own item must support the same offset.
        guard zip(lengths.sorted(), hostWidths.sorted()).allSatisfy({ length, width in
            abs(width - length - points) <= precision
        }) else { return nil }
        return Self(points: points)
    }

    public func fits(_ hostWidth: Double, length: Double) -> Bool {
        hostWidth.isFinite && length.isFinite && hostWidth > 0 && length > 0 &&
            abs(hostWidth - length - points) <= Self.precision
    }
}

public struct OwnMenuBarResolution: Sendable {
    public let padding: MenuBarHostPadding?
    /// Own configuration ID → transient ID of a uniquely matched visible proxy.
    public let matches: [UUID: UUID]
}

public enum OwnMenuBarMatching {
    public static func identifier(for id: UUID) -> String { "SpaceBar.Item.\(id.uuidString)" }

    /// The AppKit adapter must first verify delegated owner PIDs. Bundle/display
    /// checks here additionally prevent foreign or secondary-display geometry
    /// from calibrating an own-item width model.
    public static func resolve(lengths: [UUID: Double], icons: [LayoutIcon],
                               bundleID: String, displayID: String,
                               expectedPadding: MenuBarHostPadding? = nil) -> OwnMenuBarResolution {
        let own = icons.filter { $0.bundleID == bundleID && $0.displayID == displayID }
        guard !lengths.isEmpty, lengths.values.allSatisfy({ $0.isFinite && $0 > 0 }),
              Set(own.map(\.id)).count == own.count else {
            return OwnMenuBarResolution(padding: nil, matches: [:])
        }
        let expectedIDs = Set(lengths.keys.map { identifier(for: $0) })
        let measured = own.allSatisfy({ $0.identifier.isEmpty || expectedIDs.contains($0.identifier) })
            ? MenuBarHostPadding.measure(lengths: Array(lengths.values), hostWidths: own.map(\.width)) : nil
        let padding: MenuBarHostPadding?
        if let expectedPadding {
            // A requested resize cannot redefine host padding. A lagging width
            // could otherwise look like a different padding value and bind the
            // old frame to the resized item. Wait for the known model instead.
            padding = measured != nil && zip(lengths.values.sorted(), own.map(\.width).sorted()).allSatisfy({ length, width in
                expectedPadding.fits(width, length: length)
            }) ? expectedPadding : nil
        } else { padding = measured }
        var matches: [UUID: UUID] = [:]
        for (id, length) in lengths {
            let expectedID = identifier(for: id)
            let candidates = own.filter { icon in
                icon.identifier == expectedID ||
                    (icon.identifier.isEmpty && padding?.fits(icon.width, length: length) == true)
            }
            guard candidates.count == 1, let candidate = candidates.first else { continue }
            // An anonymous width must identify exactly one controller as well
            // as exactly one proxy. Identical dividers remain unbound.
            let possibleOwners = lengths.values.filter { padding?.fits(candidate.width, length: $0) == true }
            guard candidate.identifier == expectedID || possibleOwners.count == 1 else { continue }
            matches[id] = candidate.id
        }
        return OwnMenuBarResolution(padding: padding, matches: matches)
    }
}
