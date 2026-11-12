import SwiftUI

@main
struct TexelMacApp: App {
    @StateObject private var model = MacModel()

    var body: some Scene {
        WindowGroup {
            MacRootView(model: model)
                .frame(minWidth: 940, minHeight: 640)
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 1160, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "mac.menu.import", defaultValue: "导入照片…")) {
                    model.isImportPresented = true
                }
                .keyboardShortcut("o")
            }
            CommandMenu(String(localized: "转换", defaultValue: "转换")) {
                Button(String(localized: "开始转换", defaultValue: "开始转换")) {
                    model.startConversion()
                }
                .keyboardShortcut("r")
                .disabled(model.isConverting)
                Button(String(localized: "取消", defaultValue: "取消")) {
                    model.cancelConversion()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.isConverting)
            }
        }

        Settings {
            MacSettingsView(model: model)
                .frame(width: 560)
        }
    }
}
