import UIKit

final class ShareViewController: UIViewController {
  private let statusLabel = UILabel()
  private let activityIndicator = UIActivityIndicatorView(style: .medium)
  private let doneButton = UIButton(type: .system)
  private var hasProcessedShare = false

  override func viewDidLoad() {
    super.viewDidLoad()
    configureView()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    guard !hasProcessedShare else {
      return
    }

    hasProcessedShare = true
    processShare()
  }

  private func configureView() {
    view.backgroundColor = .systemBackground

    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.numberOfLines = 0
    statusLabel.textAlignment = .center
    statusLabel.text = "Saving this share for Wishiz..."

    activityIndicator.translatesAutoresizingMaskIntoConstraints = false
    activityIndicator.startAnimating()

    doneButton.translatesAutoresizingMaskIntoConstraints = false
    doneButton.setTitle("Done", for: .normal)
    doneButton.isHidden = true
    doneButton.addTarget(self, action: #selector(closeExtension), for: .touchUpInside)

    let stackView = UIStackView(arrangedSubviews: [activityIndicator, statusLabel, doneButton])
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.spacing = 16
    stackView.alignment = .center

    view.addSubview(stackView)

    NSLayoutConstraint.activate([
      stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  private func processShare() {
    extractSharedPayload { [weak self] payload in
      DispatchQueue.main.async {
        guard let self else {
          return
        }

        let stored = payload.flatMap { WishizSharePayloadStore.appGroupStore()?.storePendingSharedText($0) } ?? false

        self.activityIndicator.stopAnimating()
        self.activityIndicator.isHidden = true
        self.doneButton.isHidden = false

        if stored {
          self.statusLabel.text = "Saved to Wishiz. Open the app to finish importing."
        } else {
          self.statusLabel.text = "Wishiz couldn't find a product link in this share."
        }
      }
    }
  }

  private func extractSharedPayload(completion: @escaping (String?) -> Void) {
    let extensionItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    guard !extensionItems.isEmpty else {
      completion(nil)
      return
    }

    let group = DispatchGroup()
    let accumulationQueue = DispatchQueue(label: "com.wishiz.share-extension.accumulator")
    var rawSegments: [String] = []

    for item in extensionItems {
      if let title = item.attributedTitle?.string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        accumulationQueue.sync {
          rawSegments.append(title)
        }
      }

      if let text = item.attributedContentText?.string,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        accumulationQueue.sync {
          rawSegments.append(text)
        }
      }

      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier("public.url") {
          group.enter()
          provider.loadItem(forTypeIdentifier: "public.url", options: nil) { item, _ in
            if let stringValue = Self.stringValue(from: item) {
              accumulationQueue.sync {
                rawSegments.append(stringValue)
              }
            }
            group.leave()
          }
        }

        let textTypeIdentifier = provider.hasItemConformingToTypeIdentifier("public.plain-text")
          ? "public.plain-text" : (provider.hasItemConformingToTypeIdentifier("public.text") ? "public.text" : nil)
        guard let textTypeIdentifier else {
          continue
        }

        group.enter()
        provider.loadItem(forTypeIdentifier: textTypeIdentifier, options: nil) { item, _ in
          if let stringValue = Self.stringValue(from: item) {
            accumulationQueue.sync {
              rawSegments.append(stringValue)
            }
          }
          group.leave()
        }
      }
    }

    group.notify(queue: .global(qos: .userInitiated)) {
      let payload = accumulationQueue.sync {
        WishizSharePayloadNormalizer.normalize(rawSegments: rawSegments)
      }
      completion(payload)
    }
  }

  private static func stringValue(from item: NSSecureCoding?) -> String? {
    if let url = item as? URL {
      return url.absoluteString
    }
    if let string = item as? String {
      return string
    }
    if let attributedString = item as? NSAttributedString {
      return attributedString.string
    }
    return nil
  }

  @objc
  private func closeExtension() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
