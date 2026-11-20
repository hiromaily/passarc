import Foundation

/// The URL the extension uses to hand the selection to the app (passarc://archive?path=...&path=...)
public enum ArchiveURL {
  public static func make(items: [URL]) -> URL {
    make(items: items, host: "archive")
  }

  public static func makeExtraction(item: URL) -> URL {
    make(items: [item], host: "extract")
  }

  private static func make(items: [URL], host: String) -> URL {
    var c = URLComponents()
    c.scheme = "passarc"
    c.host = host
    c.queryItems = items.map { URLQueryItem(name: "path", value: $0.path) }
    // URLComponents leaves "+" as is; encode it so it is not read as a space
    c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return c.url!
  }

  public static func parse(_ url: URL) -> [URL]? {
    parse(url, host: "archive")
  }

  public static func parseExtraction(_ url: URL) -> URL? {
    guard let items = parse(url, host: "extract"), items.count == 1,
      ExtractionJob.format(of: items[0]) != nil
    else { return nil }
    return items[0]
  }

  private static func parse(_ url: URL, host: String) -> [URL]? {
    guard url.scheme == "passarc", url.host == host,
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return nil }
    let paths = items.filter { $0.name == "path" }.compactMap(\.value)
    guard !paths.isEmpty, paths.allSatisfy({ $0.hasPrefix("/") }) else { return nil }
    return paths.map { URL(filePath: $0) }
  }
}
