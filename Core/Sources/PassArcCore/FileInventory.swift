import Darwin
import Foundation

/// How many files go into the archive and their total size (for verification and progress).
/// Counts regular files and symlinks (not followed). Skips directories, .DS_Store and ._*.
///
/// Walks the tree with readdir and lstat, because FileManager.enumerator silently skips ._* files.
public struct FileInventory: Sendable, Equatable {
  public let fileCount: Int
  public let totalBytes: Int64
  /// Names of excluded files that were found (.DS_Store, ._*)
  public let excludedNames: Set<String>

  static func isExcluded(_ name: String) -> Bool {
    name == ".DS_Store" || name.hasPrefix("._")
  }

  public static func immediateSubfolders(of folder: URL) throws -> [URL] {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
    let children = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: Array(keys))
    return try children.filter { child in
      guard !isExcluded(child.lastPathComponent) else { return false }
      let values = try child.resourceValues(forKeys: keys)
      return values.isDirectory == true && values.isSymbolicLink == false
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  public static func scan(items: [URL]) throws -> FileInventory {
    var count = 0
    var bytes: Int64 = 0
    var excluded = Set<String>()

    func visit(_ path: String) throws {
      var st = stat()
      guard lstat(path, &st) == 0 else {
        throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: path])
      }
      switch st.st_mode & S_IFMT {
      case S_IFLNK:
        count += 1
      case S_IFREG:
        count += 1
        bytes += Int64(st.st_size)
      case S_IFDIR:
        guard let dir = opendir(path) else {
          throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: path])
        }
        defer { closedir(dir) }
        while let entry = readdir(dir) {
          let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
          }
          if name == "." || name == ".." { continue }
          if isExcluded(name) {
            excluded.insert(name)
            continue
          }
          try visit(path + "/" + name)
        }
      default:
        break  // FIFOs, sockets and devices are not counted
      }
    }

    for item in items where !isExcluded(item.lastPathComponent) {
      try visit(item.path)
    }
    return FileInventory(fileCount: count, totalBytes: bytes, excludedNames: excluded)
  }
}
