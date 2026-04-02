import Foundation

final class WishizIncomingLinkHandler {
  private let storeProvider: () -> WishizSharePayloadStore?

  init(storeProvider: @escaping () -> WishizSharePayloadStore? = WishizSharePayloadStore.appGroupStore) {
    self.storeProvider = storeProvider
  }

  @discardableResult
  func handle(url: URL?) -> Bool {
    guard let url else {
      return false
    }

    return storeProvider()?.storePendingSharedText(url.absoluteString) ?? false
  }

  @discardableResult
  func handle(webpageURL: URL?) -> Bool {
    handle(url: webpageURL)
  }
}
