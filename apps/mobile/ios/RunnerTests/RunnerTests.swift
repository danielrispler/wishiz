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

  func testStoreOverwritesOlderPendingPayload() {
    let store = makeStore()

    XCTAssertTrue(store.storePendingSharedText("https://example.com/old-item"))
    XCTAssertTrue(
      store.storePendingSharedText("Fresh link\nhttps://example.com/new-item")
    )

    XCTAssertEqual(
      store.consumePendingSharedText(),
      "Fresh link\nhttps://example.com/new-item"
    )
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
