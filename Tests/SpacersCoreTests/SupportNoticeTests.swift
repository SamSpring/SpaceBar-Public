import Foundation
import Testing
@testable import SpacersCore

@Test func freshInstallAndRepeatedLaunchesDoNotAskForCoffee() {
    var state = SupportNoticeState()
    #expect(state.recordLaunch(build: "39", existingInstallation: false) == false)
    #expect(state.highestBuild == "39")
    #expect(state.recordLaunch(build: "39", existingInstallation: true) == false)
    #expect(state.recordLaunch(build: "39", existingInstallation: true) == false)
}

@Test func legacyUsersSeeTheNewThankYouOnlyOnceOnAdoption() {
    var state = SupportNoticeState()
    #expect(state.recordLaunch(build: "39", existingInstallation: true) == true)
    #expect(state.recordLaunch(build: "39", existingInstallation: true) == false)
}

@Test func successfulHigherBuildLaunchTriggersOnceButCancelledUpdatesDoNot() {
    var state = SupportNoticeState()
    _ = state.recordLaunch(build: "39", existingInstallation: false)
    // Finding/downloading/cancelling an update never changes the running build.
    #expect(state.recordLaunch(build: "39", existingInstallation: true) == false)
    #expect(state.recordLaunch(build: "40", existingInstallation: true) == true)
    #expect(state.recordLaunch(build: "40", existingInstallation: true) == false)
    // A rollback and returning to an already-thanked version must stay quiet.
    #expect(state.recordLaunch(build: "39", existingInstallation: true) == false)
    #expect(state.recordLaunch(build: "40", existingInstallation: true) == false)
    #expect(state.recordLaunch(build: "41", existingInstallation: true) == true)
}

@Test func supportBuildComparisonIsNumericAndInvalidVersionsStayQuiet() {
    var state = SupportNoticeState()
    _ = state.recordLaunch(build: "9", existingInstallation: false)
    #expect(state.recordLaunch(build: "10", existingInstallation: true) == true)
    #expect(state.recordLaunch(build: "2", existingInstallation: true) == false)
    #expect(state.recordLaunch(build: "10.1", existingInstallation: true) == true)
    #expect(state.recordLaunch(build: "10.10", existingInstallation: true) == true)
    for build in ["", "unknown", "-1", "11\n", "11 beta"] {
        #expect(state.recordLaunch(build: build, existingInstallation: true) == false)
        #expect(state.highestBuild == "10.10")
    }
}

@Test func supportReceiptsAndOptOutPersistIndependentlyOfUserLayouts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SupportNoticeStore(url: directory.appendingPathComponent("support-notice.json"))
    #expect(try !store.recordLaunch(build: "39", existingInstallation: false))
    #expect(try store.recordLaunch(build: "40", existingInstallation: true))
    // A second process sees the receipt even if the first was closed mid-popup.
    let relaunched = SupportNoticeStore(url: store.url)
    #expect(try !relaunched.recordLaunch(build: "40", existingInstallation: true))
    try relaunched.disablePrompts()
    #expect(try !store.recordLaunch(build: "41", existingInstallation: true))
    let saved = try store.load()
    #expect(saved.highestBuild == "41" && !saved.showAfterUpdates)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["support-notice.json"])
}

@Test func damagedSupportReceiptsDoNotGetOverwrittenOrCauseRepeatPrompts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = SupportNoticeStore(url: directory.appendingPathComponent("support-notice.json"))
    let bytes = Data("damaged".utf8); try bytes.write(to: store.url)
    #expect(throws: (any Error).self) { try store.recordLaunch(build: "40", existingInstallation: true) }
    #expect(try Data(contentsOf: store.url) == bytes)
}

@Test func bothSupportButtonsUseTheApprovedOptionalKoFiDestination() {
    #expect(SpaceBarSupport.url.absoluteString == "https://ko-fi.com/samspring")
    #expect(SpaceBarSupport.url.scheme == "https")
    #expect(SpaceBarSupport.buttonTitle == "Buy me a coffee")
}
