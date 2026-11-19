import Foundation

/// The URL the extension uses to hand the selection to the app (passarc://archive?path=...&path=...)
public enum ArchiveURL {
  public static func make(items: [URL]) -> URL {
    var c = URLComponents()
    c.scheme = "passarc"
    c.host = "archive"
    c.queryItems = items.map { URLQueryItem(name: "path", value: $0.path) }
    // URLComponents leaves "+" as is; encode it so it is not read as a space
    c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return c.url!
  }

  public static func parse(_ url: URL) -> [URL]? {
    guard url.scheme == "passarc", url.host == "archive",
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return nil }
    let paths = items.filter { $0.name == "path" }.compactMap(\.value)
    guard !paths.isEmpty, paths.allSatisfy({ $0.hasPrefix("/") }) else { return nil }
    return paths.map { URL(filePath: $0) }
  }
}
