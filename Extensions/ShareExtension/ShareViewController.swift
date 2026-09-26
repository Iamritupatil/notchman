import SwiftUI
import UIKit

/// Principal class of the "Listen with Notchman" share extension.
final class ShareViewController: UIViewController {
    private lazy var model = ShareViewModel(
        complete: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        },
        cancel: { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        },
        openURL: { [weak self] url, completion in
            self?.openContainingApp(url, completion: completion) ?? completion(false)
        })

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let host = UIHostingController(rootView: ShareView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await model.load(items) }
    }

    /// Opens Notchman from the extension.
    ///
    /// iOS offers no public API for a share extension to open its containing app.
    /// This walks the responder chain to the host `UIApplication` and calls
    /// `open(_:options:completionHandler:)` dynamically, a widely used approach
    /// that works on current iOS but is not officially documented. If it isn't
    /// available, `ShareViewModel` falls back to the supported path: the item
    /// stays in the shared inbox and a local notification offers to open it.
    private func openContainingApp(_ url: URL, completion: @escaping (Bool) -> Void) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector),
               let method = class_getInstanceMethod(type(of: current), selector) {
                typealias OpenFunction = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(method_getImplementation(method), to: OpenFunction.self)
                let handler: @convention(block) (Bool) -> Void = { success in
                    DispatchQueue.main.async { completion(success) }
                }
                open(current, selector, url as NSURL, NSDictionary(), handler as AnyObject)
                return
            }
            responder = current.next
        }
        completion(false)
    }
}
