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

  private static func firstFree(in dir: URL, stem: String, suffix: String, exists: (URL) -> Bool)
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
}
