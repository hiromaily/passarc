import Foundation
import Testing

@testable import PassArcCore

@Suite struct SettingsStoreTests {
  private func freshDefaults() -> UserDefaults {
    let name = "passarc-tests-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
  }

  @Test func settings_defaults() {
    let s = SettingsStore(defaults: freshDefaults()).load()
    #expect(s.format == .sevenZip)
    #expect(s.level == .normal)
    #expect(s.usePassword)
    #expect(s.password == "")
  }

  @Test func settings_roundTripWithoutPassword() {
    let defaults = freshDefaults()
    let store = SettingsStore(defaults: defaults)
    var state = DialogState(format: .zip, level: .maximum, usePassword: true)
    state.password = "x-secret"
    state.confirmation = "x-secret"
    store.save(state)

    let loaded = store.load()
    #expect(loaded.format == .zip)
    #expect(loaded.level == .maximum)
    #expect(loaded.usePassword)
    #expect(loaded.password == "")
    let stored = defaults.dictionaryRepresentation().values.map { "\($0)" }
    #expect(!stored.contains { $0.contains("x-secret") })
  }

  @Test func settings_remembersPasswordOff() {
    let store = SettingsStore(defaults: freshDefaults())
    store.save(DialogState(format: .tarZst, level: .fast, usePassword: false))
    let loaded = store.load()
    #expect(loaded.usePassword == false)
    #expect(loaded.format == .tarZst)
  }
}

@Suite struct ArchiveURLTests {
  @Test func url_roundTrip() {
    let items = [URL(filePath: "/x/売上 2026"), URL(filePath: "/x/a&b=c#d+e")]
    let url = ArchiveURL.make(items: items)
    #expect(url.scheme == "passarc")
    #expect(ArchiveURL.parse(url)?.map(\.path) == items.map(\.path))
  }

  @Test func extractionURL_roundTrip() {
    let archive = URL(filePath: "/x/売上 + #.TAR.ZST")
    let url = ArchiveURL.makeExtraction(item: archive)
    #expect(ArchiveURL.parseExtraction(url)?.path == archive.path)
    #expect(ArchiveURL.parse(url) == nil)
    #expect(ArchiveURL.parseExtraction(URL(string: "passarc://extract?path=/a.zip&path=/b.zip")!) == nil)
    #expect(ArchiveURL.parseExtraction(URL(string: "passarc://extract?path=/a.txt")!) == nil)
  }

  @Test func url_rejectsOtherScheme() {
    #expect(ArchiveURL.parse(URL(string: "https://archive?path=/x")!) == nil)
  }

  @Test func url_rejectsRelativePath() {
    #expect(ArchiveURL.parse(URL(string: "passarc://archive?path=x")!) == nil)
  }

  @Test func url_rejectsMissingPath() {
    #expect(ArchiveURL.parse(URL(string: "passarc://archive")!) == nil)
  }
}
