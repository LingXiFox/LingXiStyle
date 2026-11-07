import SwiftUI

/// Minimal iOS host used only by the StoreKit purchase tests. It deliberately does not
/// create the production AppModel, so StoreKit is configured by SKTestSession before the
/// first product request.
@main
struct LingXiPurchaseHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("LingXiStyle Purchase Test Host")
        }
    }
}
