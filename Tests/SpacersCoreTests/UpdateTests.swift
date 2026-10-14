import Foundation
import Testing
@testable import SpacersCore

@Test func updateFeedRequiresHTTPSAndAValidEd25519PublicKey() {
    let key = Data(repeating: 1, count: 32).base64EncodedString()
    #expect(UpdatePolicy.isConfigured(feed: "https://downloads.example.org/SpaceBar/appcast.xml", publicKey: key))
    for feed in [nil, "", "http://downloads.example.org/appcast.xml", "file:///tmp/appcast.xml",
                 "https://user:password@downloads.example.org/appcast.xml", "https://downloads.example.org/not-a-feed"] {
        #expect(!UpdatePolicy.isConfigured(feed: feed, publicKey: key))
    }
    for badKey in [nil, "", "not base64", Data(repeating: 1, count: 31).base64EncodedString()] {
        #expect(!UpdatePolicy.isConfigured(feed: "https://downloads.example.org/appcast.xml", publicKey: badKey))
    }
}

@Test func updateRelaunchWaitsForRestoreAndUnsavedAdjustments() {
    #expect(UpdatePolicy.blockingReason(layoutBusy: false, previewing: false, resizing: false, saveFailed: false) == nil)
    // A completed resize does not make an ongoing restore or failed save safe.
    #expect(UpdatePolicy.blockingReason(layoutBusy: true, previewing: false, resizing: false, saveFailed: false) != nil)
    #expect(UpdatePolicy.blockingReason(layoutBusy: false, previewing: true, resizing: false, saveFailed: false) != nil)
    #expect(UpdatePolicy.blockingReason(layoutBusy: false, previewing: false, resizing: true, saveFailed: false) != nil)
    #expect(UpdatePolicy.blockingReason(layoutBusy: false, previewing: false, resizing: false, saveFailed: true) != nil)
}

@Test func developmentAndIncompleteBuildsCannotEnablePublicUpdates() {
    let key = Data(repeating: 1, count: 32).base64EncodedString()
    func availability(_ channel: String?, _ compiled: Bool = true, _ bundle: String? = "local.samuelaviv.MenuBarSpacers", _ test: Bool = false, _ feed: String? = "https://example.org/appcast.xml", _ publicKey: String? = nil) -> UpdatePolicy.Availability {
        UpdatePolicy.availability(channel: channel, compiledWithUpdater: compiled,
            bundleIdentifier: bundle, localTest: test, feed: feed, publicKey: publicKey ?? key)
    }
    #expect(availability("public") == .ready)
    #expect(availability("development") == .development)
    #expect(availability("public", false) == .development)
    #expect(availability(nil) == .unconfigured)
    #expect(availability("typo") == .unconfigured)
    #expect(availability("public", true, "local.samuelaviv.MenuBarSpacers", false, nil) == .unconfigured)
    #expect(availability("test", true, "local.samuelaviv.MenuBarSpacers", true, "http://127.0.0.1/appcast.xml") == .unconfigured)
    #expect(availability("test", true, "SpaceBar.UpdaterTests", false, "http://127.0.0.1/appcast.xml") == .unconfigured)
    #expect(availability("test", true, "SpaceBar.UpdaterTests", true, "http://127.0.0.1/appcast.xml") == .ready)
    #expect(!UpdatePolicy.isConfigured(feed: "https://127.0.0.1/appcast.xml", publicKey: key))
}
