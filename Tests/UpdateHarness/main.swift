import AppKit
import SpaceBarUpdates

// No status items, Accessibility calls, production configuration, or login items.
@MainActor
final class Harness: NSObject, NSApplicationDelegate, UpdateHost {
    var updateBlockingReason: String? {
        guard let path = ProcessInfo.processInfo.environment["SPACEBAR_HARNESS_BLOCK_FILE"] ?? Bundle.main.object(forInfoDictionaryKey: "SpaceBarTestBlockFile") as? String,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return "Finish the synthetic test adjustment before updating."
    }
    lazy var updates = UpdateCoordinator(owner: self)
    var updateInstallBlockingReason: String? { updateBlockingReason }
    private let waiting = NSTextField(labelWithString: "")
    func updateStateDidChange() { waiting.stringValue = updates.waitingMessage ?? "" }
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 520, height: 210)
        let window = NSWindow(contentRect: frame, styleMask: [.titled,.closable], backing: .buffered, defer: false)
        window.title = "SpaceBar Update Test — isolated"
        self.window = window
        let label = NSTextField(labelWithString: "Updater test build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?")")
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.frame = NSRect(x: 30, y: 135, width: 460, height: 30)
        let note = NSTextField(labelWithString: "This test never opens SpaceBar’s settings or menu bar items.")
        note.frame = NSRect(x: 30, y: 100, width: 460, height: 22)
        waiting.frame = NSRect(x: 30, y: 76, width: 460, height: 22)
        let button = NSButton(title: "Check for Updates…", target: self, action: #selector(check))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 30, y: 40, width: 185, height: 34)
        let quit = NSButton(title: "Quit Test", target: self, action: #selector(quit))
        quit.bezelStyle = .rounded; quit.frame = NSRect(x: 340, y: 40, width: 140, height: 34)
        for view in [label,note,waiting,button,quit] { window.contentView?.addSubview(view) }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate()
        if let log = ProcessInfo.processInfo.environment["SPACEBAR_HARNESS_LAUNCH_LOG"] ?? Bundle.main.object(forInfoDictionaryKey: "SpaceBarTestLaunchLog") as? String {
            let entry = "launched build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?")\n"
            let url = URL(fileURLWithPath: log)
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(entry.utf8)); try? handle.close()
            } else { try? Data(entry.utf8).write(to: url) }
        }
    }
    func showManagement() { window?.makeKeyAndOrderFront(nil); NSApp.activate() }
    func showError(_ title: String, detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.runModal()
    }
    func stopForUpdate() {}
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        sender.setActivationPolicy(.accessory)
        return .terminateNow
    }
    @objc private func check() { updates.check() }
    @objc private func quit() { NSApp.terminate(nil) }
}
let app = NSApplication.shared
let delegate = Harness()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
