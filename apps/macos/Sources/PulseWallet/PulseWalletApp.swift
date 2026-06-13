import SwiftUI

@main
struct PulseWalletApp: App {
    @State private var model = AppModel()
    @State private var keyStore = KeyStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(keyStore)
                .frame(minWidth: 880, minHeight: 560)
                .onOpenURL { model.handleURL($0) }
                .sheet(item: Binding(get: { model.pendingRequest },
                                     set: { model.pendingRequest = $0 })) { request in
                    DappRequestSheet(request: request)
                        .environment(model)
                        .environment(keyStore)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Wallet") {
                Button("Send…") { model.section = .send }
                    .keyboardShortcut("s", modifiers: [.command])
                Button("Receive…") { model.section = .receive }
                    .keyboardShortcut("r", modifiers: [.command])
                Divider()
                Button("Lock Wallet") { model.lock() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
