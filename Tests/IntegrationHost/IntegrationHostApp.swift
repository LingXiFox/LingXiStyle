import SwiftUI

@main
struct IntegrationHostApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Text("Texel Integration Host")
                    .font(.headline)
                Text("Hosts on-device conversion and PhotoKit tests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
