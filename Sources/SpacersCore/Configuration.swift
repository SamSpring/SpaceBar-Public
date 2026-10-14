import Foundation

public enum ItemKind: String, Codable, Sendable {
    case spacer, divider, flexSpacer
    public var title: String {
        switch self { case .spacer: "Spacer"; case .divider: "Divider"; case .flexSpacer: "Flex Spacer" }
    }
}

public enum ItemDimension: String, CaseIterable, Sendable {
    case width, height, thickness, opacity

    public var title: String { rawValue.capitalized }
    public var range: ClosedRange<Double> {
        switch self {
        case .width: 6...160
        case .height: 4...28
        case .thickness: 0.5...4
        case .opacity: 0.1...1
        }
    }
    public func label(for value: Double) -> String {
        self == .opacity ? "\(Int((value * 100).rounded()))%" : "\(value.formatted(.number.precision(.fractionLength(0...1)))) pt"
    }
}

public struct ItemConfiguration: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ItemKind
    public var width: Double
    public var height: Double
    public var thickness: Double
    public var opacity: Double
    public var isHighlighted: Bool
    public var flex: FlexSettings?

    public init(id: UUID = UUID(), kind: ItemKind) {
        self.id = id
        self.kind = kind
        width = kind == .divider ? 12 : 24
        height = 16
        thickness = 1
        opacity = 0.45
        isHighlighted = false
        flex = kind == .flexSpacer ? FlexSettings() : nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, width, height, thickness, opacity, isHighlighted, flex
    }

    // Additive settings must not discard existing identities or appearance.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(ItemKind.self, forKey: .kind)
        width = try values.decode(Double.self, forKey: .width)
        height = try values.decode(Double.self, forKey: .height)
        thickness = try values.decode(Double.self, forKey: .thickness)
        opacity = try values.decode(Double.self, forKey: .opacity)
        isHighlighted = try values.decodeIfPresent(Bool.self, forKey: .isHighlighted) ?? false
        flex = try values.decodeIfPresent(FlexSettings.self, forKey: .flex)
        if kind == .flexSpacer && flex == nil { flex = FlexSettings() }
    }

    // The name is tied to identity, never the array index or current dimensions.
    public var autosaveName: String { "Item.\(id.uuidString)" }
    public var dimensions: [ItemDimension] { kind == .spacer ? [.width] : [] }

    public subscript(dimension: ItemDimension) -> Double {
        get {
            switch dimension {
            case .width: width
            case .height: height
            case .thickness: thickness
            case .opacity: opacity
            }
        }
        set {
            switch dimension {
            case .width: width = newValue
            case .height: height = newValue
            case .thickness: thickness = newValue
            case .opacity: opacity = newValue
            }
        }
    }

    public func validate() throws {
        for dimension in ItemDimension.allCases {
            let value = self[dimension]
            let range = kind == .flexSpacer && dimension == .width ? 6.0...3000.0 : dimension.range
            guard value.isFinite, range.contains(value) else {
                throw ConfigurationError.invalidValue(dimension.title)
            }
        }
        if kind == .flexSpacer {
            guard let flex else { throw ConfigurationError.invalidValue("Missing flex settings") }
            try flex.validate()
        }
        else if flex != nil { throw ConfigurationError.invalidValue("Flex settings") }
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var items: [ItemConfiguration]
    public init(items: [ItemConfiguration] = []) { self.items = items }

    public func validate() throws {
        guard (1...2).contains(version) else { throw ConfigurationError.unsupportedVersion(version) }
        guard Set(items.map(\.id)).count == items.count else { throw ConfigurationError.duplicateIdentity }
        try items.forEach { try $0.validate() }
        guard items.filter({ $0.kind == .flexSpacer }).count <= 1 else {
            throw ConfigurationError.invalidValue("More than one active flex spacer")
        }
    }
}

public enum ConfigurationError: LocalizedError {
    case unsupportedVersion(Int), duplicateIdentity, invalidValue(String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "This settings file uses an unsupported version (\(version))."
        case .duplicateIdentity: "Two saved items have the same identity."
        case .invalidValue(let name): "The saved \(name.lowercased()) is outside its allowed range."
        }
    }
}

public struct ConfigurationStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static var standard: ConfigurationStore {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuBarSpacers", isDirectory: true)
        return ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
    }

    // nil means first launch. An explicitly empty file configuration stays empty.
    public func load() throws -> Configuration? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }

    public func save(_ configuration: Configuration) throws {
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
