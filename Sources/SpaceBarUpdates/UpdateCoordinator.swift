import AppKit
import SpacersCore
#if SPACEBAR_SPARKLE_UPDATES
import Sparkle
#endif

@MainActor
public protocol UpdateHost: AnyObject {
    var updateBlockingReason: String? { get }
    var updateInstallBlockingReason: String? { get }
    func showManagement()
    func showError(_ title: String, detail: String)
    func stopForUpdate()
    func updateStateDidChange()
}

@MainActor
public final class UpdateCoordinator: NSObject {
    private weak var owner: (any UpdateHost)?
    public let availability: UpdatePolicy.Availability
    public private(set) var installing = false
    public private(set) var waitingMessage: String?
    #if SPACEBAR_SPARKLE_UPDATES
    private var controller: SPUStandardUpdaterController?
    private var checkObservation: NSKeyValueObservation?
    private var pendingInstall: (() -> Void)?
    private var resumeTimer: Timer?
    #endif

    public init(owner: any UpdateHost) {
        self.owner = owner
        let info = Bundle.main.infoDictionary ?? [:]
        #if SPACEBAR_SPARKLE_UPDATES
        let compiled = true
        #else
        let compiled = false
        #endif
        availability = UpdatePolicy.availability(channel: info["SpaceBarUpdateChannel"] as? String,
            compiledWithUpdater: compiled, bundleIdentifier: Bundle.main.bundleIdentifier,
            localTest: info["SpaceBarLocalUpdaterTest"] as? Bool == true,
            feed: info["SUFeedURL"] as? String, publicKey: info["SUPublicEDKey"] as? String)
        super.init()
    }

    public var canCheck: Bool {
        guard owner != nil, owner?.updateBlockingReason == nil, !installing else { return false }
        #if SPACEBAR_SPARKLE_UPDATES
        return controller?.updater.canCheckForUpdates ?? true
        #else
        return true
        #endif
    }

    public var updateDescription: String {
        availability == .development
            ? "Development build: public updates are off so they cannot replace ongoing work."
            : "Check manually, review release notes, then choose whether to install. Automatic checks and downloads are off."
    }

    public func check() {
        guard let owner else { return }
        owner.showManagement()
        if let reason = owner.updateBlockingReason {
            owner.showError("Finish the current change first.", detail: reason)
            return
        }
        guard canCheck else { return }
        switch availability {
        case .development:
            owner.showError("This is your development build.", detail:
                "Public updates are off to protect ongoing development. This copy is updated from the project. The public release will let users check, install and relaunch here.")
        case .unconfigured:
            owner.showError("Updates aren’t available yet.", detail:
                "This build has no valid signed-update configuration. Please use a configured public release of SpaceBar.")
        case .ready:
            #if SPACEBAR_SPARKLE_UPDATES
            if controller == nil {
                let created = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
                // Manual-only is deliberate, even if an older build stored different defaults.
                created.updater.automaticallyChecksForUpdates = false
                created.updater.automaticallyDownloadsUpdates = false
                created.updater.sendsSystemProfile = false
                created.startUpdater()
                controller = created
                checkObservation = created.updater.observe(\.canCheckForUpdates) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.owner?.updateStateDidChange() }
                }
            }
            controller?.checkForUpdates(nil)
            #endif
        }
    }
}

#if SPACEBAR_SPARKLE_UPDATES
extension UpdateCoordinator: SPUUpdaterDelegate {
    public func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    public func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard availability == .ready, updateCheck == .updates else {
            throw NSError(domain: "SpaceBar.Updates", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "SpaceBar checks only when you choose Check for Updates."])
        }
        if let reason = owner?.updateBlockingReason {
            throw NSError(domain: "SpaceBar.Updates", code: 2, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }

    public func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                        untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        installing = true
        guard let reason = owner?.updateInstallBlockingReason else { return false }
        pendingInstall = installHandler
        waitingMessage = "Update waiting: \(reason)"
        owner?.updateStateDidChange()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeWhenReady() }
        }
        resumeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    private func resumeWhenReady() {
        guard owner != nil, owner?.updateInstallBlockingReason == nil, let pendingInstall else { return }
        self.pendingInstall = nil
        resumeTimer?.invalidate(); resumeTimer = nil
        waitingMessage = nil
        pendingInstall()
    }

    public func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        installing = true
        owner?.stopForUpdate()
    }

    public func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        installing = false
        pendingInstall = nil
        waitingMessage = nil
        resumeTimer?.invalidate(); resumeTimer = nil
        owner?.updateStateDidChange()
    }
}
#endif
