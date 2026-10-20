import AppKit
import OSLog
import SwiftUI

@MainActor
private final class WidtgetAppDelegate: NSObject, NSApplicationDelegate {
    let github = GitHubAccountModel()
    private var refreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sync belongs to the app lifetime, including when its window is closed.
        refreshTask = Task {
            await github.bootstrap()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                await github.handleActivation()
            }
        }

        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else { return }

        NSApplication.shared.applicationIconImage = icon
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await github.handleActivation() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }
}

struct WidtgetHostApp: App {
    @NSApplicationDelegateAdaptor(WidtgetAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Gitlines", id: "settings") {
            WidgetSettingsView(github: appDelegate.github)
        }
        .defaultSize(width: 980, height: 760)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: ["refresh"])
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

@main
enum GitlinesMain {
    @MainActor
    static func main() async {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--enable-background-refresh") {
            do {
                try GitHubBackgroundRefresh.enable()
                print("Background refresh status: \(GitHubBackgroundRefresh.service.status.rawValue)")
                exit(GitHubBackgroundRefresh.service.status == .enabled ? 0 : 2)
            } catch {
                print("Background refresh registration failed: \(error.localizedDescription)")
                exit(1)
            }
        }
        if arguments.contains("--background-refresh") {
            let logger = Logger(subsystem: "com.yjay18.widtget", category: "BackgroundRefresh")
            logger.notice("Scheduled widget refresh started")
            let github = GitHubAccountModel()
            await github.bootstrap(waitForSyncAccess: false)
            logger.notice("Scheduled widget refresh finished; phase: \(String(describing: github.phase), privacy: .public)")
            exit(github.phase == .failed ? 1 : 0)
        }
        WidtgetHostApp.main()
    }
}
