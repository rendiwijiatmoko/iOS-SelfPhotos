import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private var host: UIHostingController<ShareUploadView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareExtensionModel(extensionContext: extensionContext)
        let host = UIHostingController(rootView: ShareUploadView(model: model))
        self.host = host

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
    }
}
