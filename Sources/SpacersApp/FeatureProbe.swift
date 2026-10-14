import AppKit
import SpacersCore

@MainActor
extension AppDelegate {
    /// This entry point and restore scope are restricted to the isolated QA app.
    func runFeatureProbe() async {
        precondition(isUITest)
        do {
            if let screen = NSScreen.screens.first, let window = NSApp.windows.first(where: { $0.title == "SpaceBar — Test" }) {
                window.setFrameOrigin(NSPoint(x: screen.frame.midX - window.frame.width / 2, y: screen.frame.midY - window.frame.height / 2))
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(for: .milliseconds(300))
            }
            print("QA initial buttons: \(NSEvent.pressedMouseButtons), access \(MenuBarAccess.isTrusted), post \(MenuBarAccess.canPostEvents)")
            let spacer = add(.spacer)!
            let flexible = add(.flexSpacer)!
            let identity = controllers[flexible]!.statusItem
            await setFlexLimits(flexible, minimum: 20, maximum: 3000)
            try await Task.sleep(for: .milliseconds(500))
            if MenuBarAccess.isTrusted {
                await menuGeometry.resolveOwnItems()
                await menuGeometry.resolveOwnItems()
                var readout = await menuGeometry.read(apps: MenuBarAccess.apps(qaOnly: true), screens: MenuBarAccess.screens())
                print("QA arrangement initial: \(readout.icons.map { ($0.label, $0.left, $0.identifier) })")
                if let icon = readout.icons.first(where: { $0.identifier == "SpaceBar.Item.\(spacer.uuidString)" }),
                   let handle = readout.targets[icon.id], let screen = MenuBarAccess.screens().first(where: { $0.display.id == icon.displayID }),
                   let source = screen.usablePoint(in: handle.rect) {
                    print("QA arrange normal source \(source)")
                    try await MenuBarAccess.drag(from: source, to: CGPoint(x: screen.bounds.midX + 300, y: handle.rect.midY), target: handle)
                    try await Task.sleep(for: .milliseconds(400))
                    await menuGeometry.resolveOwnItems()
                    readout = await menuGeometry.read(apps: MenuBarAccess.apps(qaOnly: true), screens: MenuBarAccess.screens())
                    print("QA arrangement after normal: \(readout.icons.map { ($0.label, $0.left, $0.identifier) })")
                    if let normal = readout.icons.first(where: { $0.identifier == "SpaceBar.Item.\(spacer.uuidString)" }),
                       let flex = readout.icons.first(where: { $0.identifier == "SpaceBar.Item.\(flexible.uuidString)" }),
                       let handle = readout.targets[flex.id], let source = screen.usablePoint(in: handle.rect) {
                        print("QA arrange flex source \(source), destination \(normal.left - 2)")
                        try await MenuBarAccess.drag(from: source,
                            to: CGPoint(x: screen.bounds.minX + normal.left - 2, y: handle.rect.midY), target: handle)
                        try await Task.sleep(for: .milliseconds(400))
                    }
                }
            }
            print("QA after arrangement buttons: \(NSEvent.pressedMouseButtons)")
            toggleFlex(flexible)
            print("QA flex enabled: \(configuration.items.first { $0.id == flexible }!.flex!.isEnabled)")
            let stored = try Data(contentsOf: store.url)
            try await Task.sleep(for: .seconds(6))
            fflush(stdout)
            precondition(controllers[flexible]!.statusItem === identity)
            let afterSampling = try Data(contentsOf: store.url)
            fflush(stdout)
            precondition(afterSampling == stored, "Automatic flex updates wrote settings")
            print("Flex native status: \(flexCoordinator.status); width \(identity.length)")
            if let frame = flexCoordinator.lastFrame, let screen = flexCoordinator.lastScreen,
               flexCoordinator.status.hasPrefix("Centered") {
                fflush(stdout)
            precondition(abs(frame.midX - screen.bounds.midX) <= 2)
                let before = identity.length
                set(.width, value: 44, for: spacer)
                try await Task.sleep(for: .seconds(2))
                if let after = flexCoordinator.lastFrame, flexCoordinator.status.hasPrefix("Centered") {
                    fflush(stdout)
            precondition(abs(after.midX - screen.bounds.midX) <= 2)
                    print("PASS: Native flex remains centered after its right-hand neighbor changes width (\(before) → \(identity.length)).")
                }
            } else { print("LIMIT: Current placement cannot center a QA gap; compensation and clamping tests passed.") }
            toggleFlex(flexible)
            remove(flexible)
            print("PASS: Live flex sampling keeps identity and does not repeatedly write configuration.")
            guard MenuBarAccess.isTrusted else {
                print("SKIP: Live Accessibility capture/drag/restore needs QA permission. No access prompt was requested.")
                NSApp.terminate(nil); return
            }
            remove(spacer)
            let layoutSpacer = add(.spacer)!
            let second = add(.spacer)!
            try await Task.sleep(for: .milliseconds(400))
            print("QA before capture buttons: \(NSEvent.pressedMouseButtons)")
            let snapshot = try await layoutManager.capture(name: "QA Original Order")
            print("QA visible capture: \(String(decoding: try JSONEncoder().encode(snapshot.icons), as: UTF8.self))")
            fflush(stdout)
            precondition(snapshot.icons.allSatisfy { $0.bundleID == Bundle.main.bundleIdentifier })
            try layoutManager.addSnapshot(snapshot)
            let candidates = snapshot.icons.filter { icon in
                [layoutSpacer, second].contains { icon.identifier == "SpaceBar.Item.\($0.uuidString)" }
            }.sorted { $0.left < $1.left }
            guard candidates.count == 2, let screen = MenuBarAccess.screens().first(where: { $0.display.id == candidates[0].displayID }),
                  let _ = MenuBarAccess.apps(qaOnly: true).first else { throw LayoutOperationError.emptyCapture }
            let left = candidates[0], right = candidates[1]
            let rect = CGRect(x: screen.bounds.minX + left.left, y: screen.bounds.minY + left.top, width: left.width, height: left.height)
            guard let source = screen.usablePoint(in: rect) else { throw LayoutOperationError.iconMoved }
            let target = CGPoint(x: screen.bounds.minX + right.left + right.width + 2, y: source.y)
            print("QA drag: \(source) → \(target) on \(screen.display.name)")
            let live = await menuGeometry.read(apps: MenuBarAccess.apps(qaOnly: true), screens: MenuBarAccess.screens())
            let liveIcon = try requireIcon(left, in: live.icons)
            guard let handle = live.targets[liveIcon.id] else { throw LayoutOperationError.iconMoved }
            try await MenuBarAccess.drag(from: source, to: target, target: handle)
            try await Task.sleep(for: .milliseconds(500))
            let moved = try await layoutManager.capture(name: "QA Moved")
            let movedLeft = try requireIcon(left, in: moved.icons), movedRight = try requireIcon(right, in: moved.icons)
            fflush(stdout)
            precondition(movedLeft.left > movedRight.left, "QA Command-drag did not change order")
            layoutManager.restore(snapshot.id, qaProbe: true)
            while layoutManager.isBusy { try await Task.sleep(for: .milliseconds(100)) }
            let restored = try await layoutManager.capture(name: "QA Restored")
            let restoredLeft = try requireIcon(left, in: restored.icons), restoredRight = try requireIcon(right, in: restored.icons)
            fflush(stdout)
            precondition(restoredLeft.left < restoredRight.left, "QA restore did not restore order")
            fflush(stdout)
            precondition(layoutManager.library.layouts.contains { $0.name.hasPrefix("Before Restore") })
            print("PASS: Accessibility capture, verified QA-only Command-drag, recovery snapshot, and real restore pipeline. \(layoutManager.status)")
            NSApp.terminate(nil)
        } catch {
            FileHandle.standardError.write(Data("FAIL: Feature probe: \(error)\n".utf8)); exit(1)
        }
    }

    private func requireIcon(_ saved: LayoutIcon, in icons: [LayoutIcon]) throws -> LayoutIcon {
        guard let icon = LayoutMatching.match(saved, in: icons) else { throw LayoutOperationError.iconMoved }
        return icon
    }
}
