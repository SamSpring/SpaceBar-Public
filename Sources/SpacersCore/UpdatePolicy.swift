import Foundation

/// Public updates remain disabled until a real HTTPS feed and Ed25519 key exist.
public enum UpdatePolicy {
    public enum Availability: Equatable, Sendable {
        case development, unconfigured, ready
    }

    public static func availability(channel: String?, compiledWithUpdater: Bool,
                                    bundleIdentifier: String?, localTest: Bool,
                                    feed: String?, publicKey: String?) -> Availability {
        guard compiledWithUpdater else { return .development }
        if channel == "development" { return .development }
        let harness = channel == "test" && localTest &&
            bundleIdentifier?.hasSuffix(".UpdaterTests") == true
        guard channel == "public" || harness else { return .unconfigured }
        return isConfigured(feed: feed, publicKey: publicKey, allowLocalhost: harness)
            ? .ready : .unconfigured
    }

    public static func isConfigured(feed: String?, publicKey: String?, allowLocalhost: Bool = false) -> Bool {
        guard let feed, let url = URL(string: feed),
              url.scheme == "https" || (allowLocalhost && url.scheme == "http" && url.host == "127.0.0.1"),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil, url.path.hasSuffix(".xml"),
              let publicKey, let bytes = Data(base64Encoded: publicKey), bytes.count == 32 else { return false }
        let local = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
        return !local || allowLocalhost
    }

    public static func blockingReason(layoutBusy: Bool, previewing: Bool,
                                      resizing: Bool, saveFailed: Bool) -> String? {
        if layoutBusy { return "Finish or stop the layout operation before updating." }
        if previewing || resizing { return "Finish the current adjustment before updating." }
        if saveFailed { return "Resolve the settings save error before updating." }
        return nil
    }
}
