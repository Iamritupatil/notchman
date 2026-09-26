import Foundation
import os
import SafariServices

/// Native side of the Safari Web Extension. Receives a page payload from
/// background.js / popup.js, writes it to the shared inbox, and returns the
/// `notchman://listen?id=…` URL that the page navigates to (Safari asks the
/// user to confirm opening Notchman — that's the supported hand-off path).
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let log = Logger(subsystem: "com.notchman", category: "SafariExtension")

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any]

        guard let message, message["action"] as? String == "enqueue",
              let payloadDictionary = message["payload"] as? [String: Any] else {
            respond(context, ["ok": false, "error": "Unsupported message."])
            return
        }

        let action = PendingListen.Action(rawValue: message["listenAction"] as? String ?? "") ?? .read
        let payload = WebPagePayload(dictionary: payloadDictionary)

        Task {
            do {
                let content = try await SafariMessageExtractor().extract(.webPage(payload))
                let pending = PendingListen(action: action, content: content)
                try SharedInbox.write(pending)
                respond(context, ["ok": true, "id": pending.id.uuidString, "url": DeepLink.listen(id: pending.id).url.absoluteString])
            } catch {
                log.error("Enqueue failed: \(error.localizedDescription, privacy: .public)")
                respond(context, ["ok": false, "error": error.localizedDescription])
            }
        }
    }

    private func respond(_ context: NSExtensionContext, _ body: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: body]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
