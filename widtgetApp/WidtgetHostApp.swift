import AppKit
import SwiftUI

private final class WidtgetAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else { return }

        NSApplication.shared.applicationIconImage = icon
    }
}

@main
struct WidtgetHostApp: App {
    @NSApplicationDelegateAdaptor(WidtgetAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Gitlines", id: "settings") {
            WidgetSettingsView()
        }
        .defaultSize(width: 980, height: 760)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: ["refresh"])
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
