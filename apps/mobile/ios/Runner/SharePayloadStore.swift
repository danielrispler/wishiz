import Foundation

enum WishizSharePayloadConfiguration {
  static let appGroupIdentifier = "group.com.wishiz.shared"
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

    var existingTexts: [String] = []
    if fileManager.fileExists(atPath: fileURL.path),
      let data = try? Data(contentsOf: fileURL),
      let existing = try? JSONDecoder().decode(PendingShareEnvelope.self, from: data),
      existing.version == 1
    {
      existingTexts = existing.sharedTexts
    }

    existingTexts.append(normalized)
    let envelope = PendingShareEnvelope(version: 1, sharedTexts: existingTexts)

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
    guard fileManager.fileExists(atPath: fileURL.path),
      let data = try? Data(contentsOf: fileURL),
      let envelope = try? JSONDecoder().decode(PendingShareEnvelope.self, from: data),
      envelope.version == 1,
      !envelope.sharedTexts.isEmpty
    else {
      return nil
    }

    let first = envelope.sharedTexts[0]
    let remaining = Array(envelope.sharedTexts.dropFirst())

    if remaining.isEmpty {
      clearPendingSharedText()
    } else {
      let newEnvelope = PendingShareEnvelope(version: 1, sharedTexts: remaining)
      if let newData = try? JSONEncoder().encode(newEnvelope) {
        try? newData.write(to: fileURL, options: .atomic)
      }
    }

    return WishizSharePayloadNormalizer.normalize(rawSharedText: first)
  }

  func consumePendingSharedTexts() -> [String] {
    defer { clearPendingSharedText() }

    guard fileManager.fileExists(atPath: fileURL.path),
      let data = try? Data(contentsOf: fileURL),
      let envelope = try? JSONDecoder().decode(PendingShareEnvelope.self, from: data),
      envelope.version == 1
    else {
      return []
    }

    return envelope.sharedTexts.compactMap {
      WishizSharePayloadNormalizer.normalize(rawSharedText: $0)
    }
  }

  func clearPendingSharedText() {
    try? fileManager.removeItem(at: fileURL)
  }
}

private struct PendingShareEnvelope: Codable {
  let version: Int
  let sharedTexts: [String]
}
