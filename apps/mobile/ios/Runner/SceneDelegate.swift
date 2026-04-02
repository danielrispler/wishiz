import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let incomingLinkHandler = WishizIncomingLinkHandler()

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    if let url = connectionOptions.urlContexts.first?.url {
      incomingLinkHandler.handle(url: url)
      return
    }

    if let universalLink = connectionOptions.userActivities.lazy
      .first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb })?.webpageURL {
      incomingLinkHandler.handle(webpageURL: universalLink)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    incomingLinkHandler.handle(url: URLContexts.first?.url)
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb else {
      return
    }

    incomingLinkHandler.handle(webpageURL: userActivity.webpageURL)
  }
}
