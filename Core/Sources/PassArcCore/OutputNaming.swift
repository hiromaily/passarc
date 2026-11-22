import Darwin
import Foundation

public enum OutputNaming {
  /// "name.ext" for one item, "Archive.ext" for several. If taken, "name N.ext" (N from 2).
  public static func outputURL(items: [URL], format: ArchiveFormat, exists: (URL) -> Bool) -> URL {
    let parent = items[0].deletingLastPathComponent()
    let stem = items.count == 1 ? items[0].lastPathComponent : "Archive"
    return firstFree(in: parent, stem: stem, suffix: "." + format.fileExtension, exists: exists)
  }

  /// "output.partial", or "output N.partial" if that already exists
  public static func partialURL(for output: URL, exists: (URL) -> Bool) -> URL {
    firstFree(
      in: output.deletingLastPathComponent(), stem: output.lastPathComponent, suffix: ".partial",
      exists: exists)
  }

  static func firstFree(in dir: URL, stem: String, suffix: String, exists: (URL) -> Bool)
    -> URL
  {
    var candidate = dir.appending(path: stem + suffix, directoryHint: .notDirectory)
    var n = 2
    while exists(candidate) {
      candidate = dir.appending(path: "\(stem) \(n)\(suffix)", directoryHint: .notDirectory)
      n += 1
    }
    return candidate
  }

  static func finalize(
    _ staged: URL, reservedDestination: URL? = nil,
    checkCancellation: () throws -> Void,
    nextDestination: (Set<URL>) -> URL
  ) throws -> URL {
    var destination = reservedDestination
    var occupied = Set<URL>()
    while true {
      let candidate = destination ?? nextDestination(occupied)
      try checkCancellation()
      // An exclusive rename also detects destinations missed by fileExists, such as dangling symlinks.
      if renamex_np(staged.path, candidate.path, UInt32(RENAME_EXCL)) == 0 { return candidate }
      let code = errno
      guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
      occupied.insert(candidate)
      destination = nil
    }
  }
}
