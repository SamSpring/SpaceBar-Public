import Foundation

public enum SpaceBarSupport {
    public static let url = URL(string: "https://ko-fi.com/samspring")!
    public static let buttonTitle = "Buy me a coffee"
}

/// Separate from item configuration and layouts. A successful launch of a
/// higher build is the receipt, so failed/cancelled installs cannot prompt.
public struct SupportNoticeState: Codable, Equatable, Sendable {
    public private(set) var highestBuild: String?
    public var showAfterUpdates = true
    public init() {}

    public mutating func recordLaunch(build: String, existingInstallation: Bool) -> Bool {
        guard build.range(of: #"\A[0-9]+(?:\.[0-9]+)*\z"#, options: .regularExpression) != nil else { return false }
        if let highestBuild {
            guard build.compare(highestBuild, options: .numeric) == .orderedDescending else { return false }
        }
        let hadPreviousBuild = highestBuild != nil
        highestBuild = build
        // Legacy users have settings but predate this receipt. Introduce the
        // thank-you once on adoption; genuinely new installations stay quiet.
        return showAfterUpdates && (hadPreviousBuild || existingInstallation)
    }
}

public struct SupportNoticeStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> SupportNoticeState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SupportNoticeState() }
        return try JSONDecoder().decode(SupportNoticeState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: SupportNoticeState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    public func recordLaunch(build: String, existingInstallation: Bool) throws -> Bool {
        var state = try load()
        let previous = state
        let show = state.recordLaunch(build: build, existingInstallation: existingInstallation)
        // Persist before presentation: quitting or crashing with the window
        // open must not show the same donation request again on every launch.
        if state != previous { try save(state) }
        return show
    }

    public func disablePrompts() throws {
        var state = try load(); state.showAfterUpdates = false; try save(state)
    }
}
