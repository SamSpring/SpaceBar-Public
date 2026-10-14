import Foundation

public struct LayoutDisplay: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var width: Double
    public var height: Double
    public init(id: String, name: String, width: Double, height: Double) {
        self.id = id; self.name = name; self.width = width; self.height = height
    }
}

public struct LayoutIcon: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var bundleID: String
    public var appName: String
    public var identifier: String
    public var label: String
    public var occurrence: Int
    public var matchingCount: Int
    public var displayID: String
    public var left: Double
    public var top: Double
    public var width: Double
    public var height: Double
    public init(bundleID: String, appName: String, identifier: String, label: String,
                occurrence: Int = 0, matchingCount: Int = 1, displayID: String,
                left: Double, top: Double, width: Double, height: Double) {
        self.bundleID = bundleID; self.appName = appName; self.identifier = identifier
        self.label = label; self.occurrence = occurrence; self.matchingCount = matchingCount
        self.displayID = displayID; self.left = left; self.top = top
        self.width = width; self.height = height
    }
    public var identityKey: String { bundleID + "\u{0}" + (identifier.isEmpty ? "label:" + label : "id:" + identifier) }
    public var title: String { label.isEmpty ? appName : "\(appName) — \(label)" }
}

public struct MenuBarLayout: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var createdAt = Date()
    public var configuration: Configuration
    public var displays: [LayoutDisplay]
    public var icons: [LayoutIcon]
    public init(name: String, configuration: Configuration, displays: [LayoutDisplay], icons: [LayoutIcon]) {
        self.name = name; self.configuration = configuration; self.displays = displays; self.icons = icons
    }
    public func validate() throws {
        try configuration.validate()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              Set(displays.map(\.id)).count == displays.count, Set(icons.map(\.id)).count == icons.count,
              displays.allSatisfy({ !$0.id.isEmpty && $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 }),
              icons.allSatisfy({ icon in
                  !icon.bundleID.isEmpty && displays.contains { $0.id == icon.displayID } &&
                  [icon.left, icon.top, icon.width, icon.height].allSatisfy(\.isFinite) &&
                  icon.left >= 0 && icon.top >= 0 && icon.width > 0 && icon.height > 0 &&
                  icon.matchingCount > 0 && (0..<icon.matchingCount).contains(icon.occurrence)
              }) else { throw ConfigurationError.invalidValue("Saved layout") }
    }
}

public enum LayoutMatching {
    /// Never guess when indistinguishable icons have appeared or disappeared.
    public static func match(_ saved: LayoutIcon, in live: [LayoutIcon]) -> LayoutIcon? {
        guard !saved.identifier.isEmpty || !saved.label.isEmpty else { return nil }
        let matches = live.filter { $0.identityKey == saved.identityKey && $0.displayID == saved.displayID }
            .sorted { $0.left < $1.left }
        guard matches.count == 1, saved.matchingCount == 1, saved.occurrence == 0 else { return nil }
        return matches[saved.occurrence]
    }
    public static func stampOccurrences(_ icons: [LayoutIcon]) -> [LayoutIcon] {
        var result = icons
        for index in result.indices {
            let group = icons.filter { $0.identityKey == icons[index].identityKey && $0.displayID == icons[index].displayID }
                .sorted { $0.left < $1.left }
            result[index].matchingCount = group.count
            result[index].occurrence = group.firstIndex { $0.id == icons[index].id } ?? 0
        }
        return result
    }
}

public struct LayoutLibrary: Codable, Equatable, Sendable {
    public var version = 1
    public var layouts: [MenuBarLayout] = []
    public init() {}
    public func validate() throws {
        guard version == 1 else { throw ConfigurationError.unsupportedVersion(version) }
        guard Set(layouts.map(\.id)).count == layouts.count else { throw ConfigurationError.duplicateIdentity }
        try layouts.forEach { try $0.validate() }
    }
}

public struct LayoutStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> LayoutLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else { return LayoutLibrary() }
        let library = try JSONDecoder().decode(LayoutLibrary.self, from: Data(contentsOf: url))
        try library.validate()
        return library
    }
    public func save(_ library: LayoutLibrary) throws {
        try library.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(library).write(to: url, options: .atomic)
    }
}
