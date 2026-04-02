import Foundation

enum WishizSharePayloadConfiguration {
  static let appGroupIdentifier = "group.com.wishiz.beta.shared"
  static let pendingPayloadFilename = "wishiz-pending-share.json"
}

struct WishizSharePayloadNormalizer {
  private static let urlPattern = try! NSRegularExpression(
    pattern: #"(?:https?://|wishiz://)[^\s]+"#,
    options: [.caseInsensitive]
  )

  static func normalize(subject: String?, text: String?) -> String? {
    normalize(rawSegments: [subject, text].compactMap { $0 })
  }

  static func normalize(rawSharedText: String) -> String? {
    normalize(rawSegments: [rawSharedText])
  }

  static func normalize(rawSegments: [String]) -> String? {
    let trimmedSegments = rawSegments
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !trimmedSegments.isEmpty else {
      return nil
    }

    let productURL = trimmedSegments.lazy.compactMap { extractProductURL(from: $0) }.first
    guard let productURL else {
      return nil
    }

    var lines: [String] = []
    var seenLines = Set<String>()

    for segment in trimmedSegments {
      for rawLine in segment.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line != productURL, seenLines.insert(line).inserted else {
          continue
        }
        lines.append(line)
      }
    }

    lines.append(productURL)
    return lines.joined(separator: "\n")
  }

  static func extractProductURL(from text: String) -> String? {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = urlPattern.firstMatch(in: text, options: [], range: range),
      let swiftRange = Range(match.range, in: text)
    else {
      return nil
    }

    let candidate = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased() else {
      return nil
    }

    if scheme == "wishiz", url.host?.lowercased() == "lists", url.path.isEmpty == false {
      return candidate
    }

    guard (scheme == "http" || scheme == "https"), url.host?.isEmpty == false else {
      return nil
    }

    return candidate
  }
}

final class WishizSharePayloadStore {
  private let fileURL: URL
  private let fileManager: FileManager

  init(containerURL: URL, fileManager: FileManager = .default) {
    self.fileURL = containerURL.appendingPathComponent(
      WishizSharePayloadConfiguration.pendingPayloadFilename,
      isDirectory: false
    )
    self.fileManager = fileManager
  }

  static func appGroupStore() -> WishizSharePayloadStore? {
    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: WishizSharePayloadConfiguration.appGroupIdentifier
    ) else {
      return nil
    }

    return WishizSharePayloadStore(containerURL: containerURL)
  }

  @discardableResult
  func storePendingSharedText(_ rawSharedText: String) -> Bool {
    guard let normalized = WishizSharePayloadNormalizer.normalize(rawSharedText: rawSharedText) else {
      return false
    }

    let envelope = PendingShareEnvelope(version: 1, sharedText: normalized)

    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
      )
      let data = try JSONEncoder().encode(envelope)
      try data.write(to: fileURL, options: .atomic)
      return true
    } catch {
      return false
    }
  }

  func consumePendingSharedText() -> String? {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }

    defer {
      clearPendingSharedText()
    }

    guard let data = try? Data(contentsOf: fileURL),
      let envelope = try? JSONDecoder().decode(PendingShareEnvelope.self, from: data),
      envelope.version == 1,
      let normalized = WishizSharePayloadNormalizer.normalize(rawSharedText: envelope.sharedText)
    else {
      return nil
    }

    return normalized
  }

  func clearPendingSharedText() {
    try? fileManager.removeItem(at: fileURL)
  }
}

private struct PendingShareEnvelope: Codable {
  let version: Int
  let sharedText: String
}
