import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testNormalizerReturnsURLOnlyPayload() {
    let payload = WishizSharePayloadNormalizer.normalize(
      rawSegments: ["https://example.com/products/kettle"]
    )

    XCTAssertEqual(payload, "https://example.com/products/kettle")
  }

  func testNormalizerReturnsTextAndURLPayload() {
    let payload = WishizSharePayloadNormalizer.normalize(
      rawSegments: ["Acme kettle", "https://example.com/products/kettle"]
    )

    XCTAssertEqual(payload, "Acme kettle\nhttps://example.com/products/kettle")
  }

  func testNormalizerRejectsPayloadWithoutURL() {
    let payload = WishizSharePayloadNormalizer.normalize(rawSegments: ["Just some notes"])

    XCTAssertNil(payload)
  }

  func testNormalizerPreservesWishizListLinkPayload() {
    let payload = WishizSharePayloadNormalizer.normalize(
      rawSegments: ["Open this list in Wishiz", "wishiz://lists/wishlist-42"]
    )

    XCTAssertEqual(
      payload,
      "Open this list in Wishiz\nwishiz://lists/wishlist-42"
    )
  }

  func testNormalizerPreservesHttpsWishizListLinkPayload() {
    let payload = WishizSharePayloadNormalizer.normalize(
      rawSegments: ["https://wishiz.app/lists/wishlist-42", "Open this list in Wishiz"]
    )

    XCTAssertEqual(
      payload,
      "Open this list in Wishiz\nhttps://wishiz.app/lists/wishlist-42"
    )
  }

  func testIncomingLinkHandlerStoresCustomSchemeLinks() {
    let store = makeStore()
    let handler = WishizIncomingLinkHandler(storeProvider: { store })

    XCTAssertTrue(handler.handle(url: URL(string: "wishiz://lists/wishlist-42")))
    XCTAssertEqual(store.consumePendingSharedText(), "wishiz://lists/wishlist-42")
  }

  func testIncomingLinkHandlerStoresUniversalLinks() {
    let store = makeStore()
    let handler = WishizIncomingLinkHandler(storeProvider: { store })

    XCTAssertTrue(handler.handle(webpageURL: URL(string: "https://wishiz.app/lists/wishlist-42")))
    XCTAssertEqual(store.consumePendingSharedText(), "https://wishiz.app/lists/wishlist-42")
  }

  func testStoreQueuesPayloadsInFifoOrder() {
    let store = makeStore()

    XCTAssertTrue(store.storePendingSharedText("https://example.com/old-item"))
    XCTAssertTrue(
      store.storePendingSharedText("Fresh link\nhttps://example.com/new-item")
    )

    XCTAssertEqual(
      store.consumePendingSharedTexts(),
      [
        "https://example.com/old-item",
        "Fresh link\nhttps://example.com/new-item",
      ]
    )
  }

  func testConsumePendingSharedTextsDrainsAllAndClears() {
    let store = makeStore()

    XCTAssertTrue(store.storePendingSharedText("https://example.com/products/a"))
    XCTAssertTrue(store.storePendingSharedText("https://example.com/products/b"))
    XCTAssertTrue(store.storePendingSharedText("https://example.com/products/c"))

    XCTAssertEqual(
      store.consumePendingSharedTexts(),
      [
        "https://example.com/products/a",
        "https://example.com/products/b",
        "https://example.com/products/c",
      ]
    )
    XCTAssertEqual(store.consumePendingSharedTexts(), [])
  }

  func testConsumePendingSharedTextsClearsCorruptedPayload() throws {
    let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: containerURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    let payloadURL = containerURL.appendingPathComponent(
      WishizSharePayloadConfiguration.pendingPayloadFilename
    )
    try Data("not-json".utf8).write(to: payloadURL, options: .atomic)

    let store = WishizSharePayloadStore(containerURL: containerURL)
    XCTAssertEqual(store.consumePendingSharedTexts(), [])
    XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
  }

  func testStoreConsumesPayloadOnlyOnce() {
    let store = makeStore()

    XCTAssertTrue(
      store.storePendingSharedText("Tea cup\nhttps://example.com/products/cup")
    )

    XCTAssertEqual(
      store.consumePendingSharedText(),
      "Tea cup\nhttps://example.com/products/cup"
    )
    XCTAssertNil(store.consumePendingSharedText())
  }

  func testStoreClearsCorruptedPayload() throws {
    let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: containerURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    let payloadURL = containerURL.appendingPathComponent(
      WishizSharePayloadConfiguration.pendingPayloadFilename
    )
    try Data("not-json".utf8).write(to: payloadURL, options: .atomic)

    let store = WishizSharePayloadStore(containerURL: containerURL)
    XCTAssertNil(store.consumePendingSharedText())
    XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
  }

  private func makeStore() -> WishizSharePayloadStore {
    let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    return WishizSharePayloadStore(containerURL: containerURL)
  }
}
