import Flutter
import Foundation

final class ShareIntakeChannelBridge {
  private let methodChannelName = "wishiz/share_intake/methods"
  private let storeProvider: () -> WishizSharePayloadStore?

  init(storeProvider: @escaping () -> WishizSharePayloadStore? = WishizSharePayloadStore.appGroupStore) {
    self.storeProvider = storeProvider
  }

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [storeProvider] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "consumePendingSharedText", "getInitialSharedText":
        result(storeProvider()?.consumePendingSharedText())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}