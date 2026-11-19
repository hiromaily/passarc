import Foundation

/// Remembers the last format, level and password checkbox. Never the password.
public struct SettingsStore {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func load() -> DialogState {
    let format = defaults.string(forKey: "format").flatMap(ArchiveFormat.init) ?? .sevenZip
    let level = defaults.string(forKey: "level").flatMap(CompressionLevel.init) ?? .normal
    let usePassword = defaults.object(forKey: "usePassword") as? Bool ?? true
    var state = DialogState(format: .sevenZip, level: level, usePassword: usePassword)
    state.format = state.isFormatEnabled(format) ? format : .sevenZip
    return state
  }

  public func save(_ state: DialogState) {
    defaults.set(state.format.rawValue, forKey: "format")
    defaults.set(state.level.rawValue, forKey: "level")
    defaults.set(state.usePassword, forKey: "usePassword")
  }
}
