import Foundation
import WebKit

/// Reads chat share links (chatgpt.com/share, claude.ai/share, g.co/gemini/share)
/// that build their page with JavaScript: the page is loaded in an invisible
/// web view on the iPhone, and the AI's replies are read from it once they
/// appear. Nothing is signed in and nothing is kept (a throwaway data store).
@MainActor
final class RenderedPageReader: NSObject {
    struct Result {
        let title: String?
        /// The AI's replies, oldest first.
        let replies: [String]
        /// Page text, when no replies were recognized.
        let pageText: String
    }

    /// Finds replies on ChatGPT, Claude and Gemini share pages; falls back to the page text.
    private static let script = """
    (() => {
      const texts = (selector) => Array.from(document.querySelectorAll(selector))
        .map(e => (e.innerText || '').trim()).filter(t => t.length > 0);
      let replies = texts('[data-message-author-role="assistant"]');
      if (!replies.length) replies = texts('.font-claude-message, .font-claude-response, [data-testid="assistant-message"]');
      if (!replies.length) replies = texts('message-content, .model-response-text');
      const main = document.querySelector('main') || document.body;
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
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(500))
            guard let json = try? await webView.evaluateJavaScript(Self.script) as? String,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let replies = (object["replies"] as? [String]) ?? []
            last = Result(title: object["title"] as? String, replies: replies, pageText: object["page"] as? String ?? "")
            // Replies found and the page has settled (not still streaming in).
            if !replies.isEmpty, !webView.isLoading { return last }
        }
        if last.replies.isEmpty, last.pageText.count < 80 { throw ExtractionError.clientRenderedPage }
        return last
    }
}
