import Foundation

/// Native overflow keeps hidden status objects in the host, stacked behind a
/// small system control. Their invisible order cannot be read from those
/// overlapping frames. Accept only a leading hidden group, retaining every
/// verified object and checking the order/positions that remain visible.
public enum FlexNativeOverflow {
    private struct View {
        let control: UUID?
        let hidden: Set<UUID>
    }

    public static func isRecognized(spacer: LayoutIcon, others: [LayoutIcon]) -> Bool {
        view(spacer: spacer, others: others)?.control != nil
    }

    public static func hiddenCount(spacer: LayoutIcon, others: [LayoutIcon]) -> Int {
        view(spacer: spacer, others: others)?.hidden.count ?? 0
    }

    private static func view(spacer: LayoutIcon, others: [LayoutIcon]) -> View? {
        let all = [spacer] + others
        guard Set(all.map(\.id)).count == all.count,
              all.allSatisfy({ $0.displayID == spacer.displayID &&
                  [$0.left, $0.top, $0.width, $0.height].allSatisfy(\.isFinite) && $0.width > 0 && $0.height > 0 }) else { return nil }
        if FlexResizeSafety.isCoherent(all) { return View(control: nil, hidden: []) }
        var candidates: [View] = []
        for control in others where control.bundleID == "com.apple.MenuBarAgent" &&
            control.width <= 32 && control.height <= spacer.height - 1 && control.height >= spacer.height - 8 &&
            control.top >= spacer.top - 1 && control.top + control.height <= spacer.top + spacer.height + 1 &&
            control.left + control.width < spacer.left {
            let end = control.left + control.width
            let hidden = Set(others.filter { icon in
                icon.id != control.id && abs(icon.left + icon.width - end) <= 2 &&
                min(icon.left + icon.width, end) - max(icon.left, control.left) > 1
            }.map(\.id))
            guard !hidden.isEmpty else { continue }
            let visible = others.filter { $0.id != control.id && !hidden.contains($0.id) }
            guard visible.allSatisfy({ $0.left >= end - 1 }),
                  FlexResizeSafety.isCoherent([spacer, control] + visible) else { continue }
            candidates.append(View(control: control.id, hidden: hidden))
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    public static func verifyGrowth(originalLength: Double, requestedLength: Double,
        before: LayoutIcon, after: LayoutIcon?, othersBefore: [LayoutIcon], othersAfter: [LayoutIcon],
        matches: [UUID: UUID]) -> FlexResizeResult {
        guard let after, after.displayID == before.displayID,
              originalLength.isFinite, requestedLength.isFinite, requestedLength > originalLength,
              abs(after.width - before.width - requestedLength + originalLength) <= 2,
              abs(after.left + after.width - before.left - before.width) <= 2,
              let oldView = view(spacer: before, others: othersBefore),
              let newView = view(spacer: after, others: othersAfter),
              oldView.control != nil || newView.control != nil else { return .retry }
        let old = othersBefore.filter { $0.id != oldView.control }.sorted { $0.left < $1.left }
        let new = othersAfter.filter { $0.id != newView.control }.sorted { $0.left < $1.left }
        let newByID = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        let destinations = old.compactMap { matches[$0.id] }
        // Every pre-existing object must be accounted for, including hidden
        // anonymous objects. Only the native overflow control may appear/go.
        guard !old.isEmpty, old.count == new.count, destinations.count == old.count,
              Set(destinations).count == old.count, Set(destinations) == Set(newByID.keys) else { return .retry }
        var paired: [UUID: LayoutIcon] = [:]
        for item in old {
            guard let id = matches[item.id], let other = newByID[id],
                  other.bundleID == item.bundleID, other.displayID == item.displayID,
                  abs(other.width - item.width) <= 2 else { return .retry }
            paired[item.id] = other
        }
        let growth = requestedLength - originalLength
        let oldLeft = old.filter { $0.left + $0.width <= before.left + 1 }
        let oldRight = old.filter { $0.left >= before.left + before.width - 1 }
        guard oldLeft.count + oldRight.count == old.count else { return .retry }
        let common = old.filter { !oldView.hidden.contains($0.id) && !newView.hidden.contains(paired[$0.id]!.id) }
        let commonAfterIDs = Set(common.map { paired[$0.id]!.id })
        guard common.map({ paired[$0.id]!.id }) == new.filter({ commonAfterIDs.contains($0.id) }).map(\.id) else { return .unsafeOrder }
        for item in oldRight {
            let other = paired[item.id]!
            guard !newView.hidden.contains(other.id), other.left >= after.left + after.width - 1 else { return .unsafeOrder }
            guard abs(other.left - item.left) <= 2 else { return .retry }
        }
        let oldVisibleLeft = oldLeft.filter { !oldView.hidden.contains($0.id) }
        var visibleStarted = false
        for item in oldVisibleLeft {
            let other = paired[item.id]!
            if newView.hidden.contains(other.id) {
                if visibleStarted { return .unsafeOrder }
            } else {
                visibleStarted = true
                guard other.left + other.width <= after.left + 1 else { return .unsafeOrder }
                guard abs(other.left - item.left + growth) <= 2 else { return .retry }
            }
        }
        // Previously hidden objects may reappear only as a leading left group.
        let newlyVisible = Set(oldLeft.filter { oldView.hidden.contains($0.id) && !newView.hidden.contains(paired[$0.id]!.id) }.map { paired[$0.id]!.id })
        var existingVisibleStarted = false
        for item in new where !newView.hidden.contains(item.id) && item.left + item.width <= after.left + 1 {
            if newlyVisible.contains(item.id) {
                if existingVisibleStarted { return .unsafeOrder }
            } else { existingVisibleStarted = true }
        }
        for item in oldLeft {
            let other = paired[item.id]!
            guard other.left + other.width <= after.left + 1 else { return .unsafeOrder }
        }
        return .applied
    }
}
