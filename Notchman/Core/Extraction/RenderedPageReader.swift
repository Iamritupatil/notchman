import Foundation
import WebKit

/// Reads pages that build their text with JavaScript (and LinkedIn's embed
/// page): the page is loaded in an invisible web view on the iPhone, like
/// Safari, and its article text is read once it settles. Nothing is signed in
/// and nothing is kept (a throwaway data store).
@MainActor
final class RenderedPageReader: NSObject {
    struct Result {
        let title: String?
        /// The AI's replies, oldest first.
        let replies: [String]
        /// Page text, when no replies were recognized.
        let pageText: String
    }

    /// LinkedIn's post text on its embed page; otherwise the article text.
    private static let script = """
    (() => {
      const texts = (selector) => Array.from(document.querySelectorAll(selector))
        .map(e => (e.innerText || '').trim()).filter(t => t.length > 0);
      const replies = texts('.attributed-text-segment-list__content');
      const main = document.querySelector('article') || document.querySelector('main') || document.body;
      return JSON.stringify({ title: document.title, replies, page: replies.length ? '' : (main ? main.innerText : '') });
    })()
    """

    private var webView: WKWebView?

    static func read(_ url: URL, timeout: TimeInterval = 12) async throws -> Result {
        let reader = RenderedPageReader()
        return try await reader.load(url, timeout: timeout)
    }

    private func load(_ url: URL, timeout: TimeInterval) async throws -> Result {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        self.webView = webView
        defer {
            webView.stopLoading()
            self.webView = nil
        }
        webView.load(URLRequest(url: url, timeoutInterval: timeout))

        let deadline = Date().addingTimeInterval(timeout)
        var last = Result(title: nil, replies: [], pageText: "")
        var previousLength = -1
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(500))
            guard let json = try? await webView.evaluateJavaScript(Self.script) as? String,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let replies = (object["replies"] as? [String]) ?? []
            last = Result(title: object["title"] as? String, replies: replies, pageText: object["page"] as? String ?? "")
            // Replies found and the page has settled (not still streaming in).
            if !replies.isEmpty, !webView.isLoading { return last }
            // An ordinary page: done once its text stops changing.
            let length = last.pageText.count
            if replies.isEmpty, !webView.isLoading, length >= 200, length == previousLength { return last }
            previousLength = length
        }
        if last.replies.isEmpty, last.pageText.count < 80 { throw ExtractionError.clientRenderedPage }
        return last
    }
}
