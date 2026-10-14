import Foundation
import Testing
@testable import SpacersCore

@Test func configurationRoundTripKeepsIndependentIdentitiesAndDimensions() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
    #expect(try store.load() == nil)
    var divider = ItemConfiguration(kind: .divider)
    divider.width = 17.5
    divider.height = 20
    divider.thickness = 0.5
    divider.opacity = 0.85
    divider.isHighlighted = true
    var spacer = ItemConfiguration(kind: .spacer)
    spacer.isHighlighted = true
    let configuration = Configuration(items: [divider, spacer, ItemConfiguration(kind: .spacer)])
    try store.save(configuration)
    #expect(try store.load() == configuration)
    var changed = divider
    changed.width = 40
    #expect(changed.autosaveName == divider.autosaveName)
    #expect(Set(configuration.items.map(\.autosaveName)).count == 3)
}

@Test func previousSettingsLoadWithoutChangingIdentityOrAppearance() throws {
    let id = UUID()
    let json = """
    {"version":1,"items":[{"id":"\(id.uuidString)","kind":"divider","width":17.5,"height":20,"thickness":1.5,"opacity":0.65}]}
    """
    let config = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
    try config.validate()
    let item = try #require(config.items.first)
    #expect(item.id == id)
    #expect(item.width == 17.5 && item.height == 20 && item.thickness == 1.5 && item.opacity == 0.65)
    #expect(!item.isHighlighted)
    #expect(item.autosaveName == "Item.\(id.uuidString)")
    #expect(item.dimensions.isEmpty)
    #expect(ItemConfiguration(kind: .spacer).dimensions == [.width])
    let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
    #expect(decoded == config)
}

@Test func explicitEmptyConfigurationDoesNotCreateADefaultItem() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
    try store.save(Configuration())
    #expect(try store.load()?.items == [])
}

@Test func malformedAndFutureSettingsRemainUntouched() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
    for text in ["not json", "{\"version\":999,\"items\":[]}"] {
        let original = Data(text.utf8)
        try original.write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try Data(contentsOf: store.url) == original)
    }
}

@Test func invalidDimensionsAndDuplicateIdentitiesAreRejectedBeforeWriting() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
    let valid = Configuration(items: [ItemConfiguration(kind: .divider)])
    try store.save(valid)
    for dimension in ItemDimension.allCases {
        for value in [Double.nan, .infinity, dimension.range.lowerBound - 1, dimension.range.upperBound + 1] {
            var invalid = valid
            invalid.items[0][dimension] = value
            #expect(throws: (any Error).self) { try store.save(invalid) }
            #expect(try store.load() == valid)
        }
    }
    #expect(throws: (any Error).self) {
        try store.save(Configuration(items: [valid.items[0], valid.items[0]]))
    }
    #expect(try store.load() == valid)
}

@Test func failedSavePreservesExistingFile() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ConfigurationStore(url: folder.appendingPathComponent("configuration.json"))
    try store.save(Configuration())
    let bytes = try Data(contentsOf: store.url)
    let inaccessible = ConfigurationStore(url: store.url.appendingPathComponent("cannot-write.json"))
    #expect(throws: (any Error).self) { try inaccessible.save(Configuration()) }
    #expect(try Data(contentsOf: store.url) == bytes)
}
