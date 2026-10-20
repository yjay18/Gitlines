import Darwin
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class GitHubBackgroundRefresh: ObservableObject {
    static let label = "com.yjay18.widtget.refresh"
    static var service: SMAppService { .agent(plistName: "\(label).plist") }

    static func enable() throws {
        SharedPreferences.defaults.set(true, forKey: SharedPreferences.Key.githubRefreshRequested)
        if service.status != .enabled && service.status != .requiresApproval {
            try service.register()
        }
    }

    @Published private(set) var status = SMAppService.Status.notRegistered
    @Published private(set) var errorMessage: String?

    init() { updateStatus() }

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }

    func updateStatus() { status = Self.service.status }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try Self.enable() }
            else { try Self.service.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        updateStatus()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

// The visible app owns the lease while open; a scheduled run exits if it is held.
// This also serializes OAuth renewal and cache writes when the app opens mid-sync.
final class GitHubHostSyncLease {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    deinit { close(descriptor) }

    static func acquire(at url: URL? = nil) throws -> GitHubHostSyncLease? {
        let location: URL
        if let url { location = url }
        else {
            guard let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: SharedPreferences.suiteName
            ) else { throw ActivitySnapshotStoreError.appGroupUnavailable }
            location = container.appendingPathComponent("github-host-sync.lock")
        }
        let descriptor = open(location.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return GitHubHostSyncLease(descriptor: descriptor)
    }
}
