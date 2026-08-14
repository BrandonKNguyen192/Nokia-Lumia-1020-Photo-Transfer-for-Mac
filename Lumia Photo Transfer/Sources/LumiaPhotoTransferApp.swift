import SwiftUI

@main
struct LumiaPhotoTransferApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 750, minHeight: 550)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Device") {
                Button("Refresh Device") {
                    NotificationCenter.default.post(name: .refreshDevice, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Notification for refresh
extension Notification.Name {
    static let refreshDevice = Notification.Name("refreshDevice")
}

// MARK: - Settings View
struct SettingsView: View {
    @AppStorage("defaultDestination") private var defaultDestination = "~/Pictures/Lumia Photos"
    @AppStorage("autoImportLightroom") private var autoImportLightroom = false

    var body: some View {
        Form {
            Section("Import") {
                TextField("Default destination:", text: $defaultDestination)
                    .frame(width: 300)
                Toggle("Open in Lightroom after import", isOn: $autoImportLightroom)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 150)
    }
}
