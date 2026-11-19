import Foundation

public enum ProgressParser {
  /// The last "NN%" in 7zz -bsp1 output, as 0...1
  public static func fraction(from chunk: String) -> Double? {
    guard let match = chunk.matches(of: /(\d{1,3})%/).last, let value = Int(match.1) else {
      return nil
    }
    return Double(min(value, 100)) / 100
  }
}
