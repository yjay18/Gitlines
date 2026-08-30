import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class GitHubAccountModel: ObservableObject {
    enum Phase: Equatable {
        case disconnected
        case connecting
        case refreshing
        case connected
        case failed
    }

    @Published var tokenInput = ""
    @Published var replacementAccountTokenInput = ""
    @Published var organizationInput = ""
    @Published var additionalTokenInput = ""
    @Published private(set) var username = ""
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var phase: Phase = .disconnected
    @Published private(set) var message: String?
    @Published private(set) var notice: String?
    @Published private(set) var hasStoredToken = false
    @Published private(set) var tokenCount = 0
    @Published private(set) var connections: [GitHubConnectionSummary] = []
    @Published private(set) var activityArchive: ActivitySnapshotArchive?

    private let service: GitHubActivityService
    private var didBootstrap = false
    private var storedConnections: [GitHubStoredConnection] = []

    init(service: GitHubActivityService = GitHubActivityService()) {
        self.service = service
        username = SharedPreferences.defaults.string(forKey: SharedPreferences.Key.githubUsername) ?? ""
        lastRefresh = SharedPreferences.defaults.object(
            forKey: SharedPreferences.Key.lastSuccessfulRefresh
        ) as? Date
    }

    var isBusy: Bool {
        phase == .connecting || phase == .refreshing
    }

    var canConnect: Bool {
        !tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    var canAddToken: Bool {
        GitHubOrganizationName.isValid(organizationInput)
            && !additionalTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }

    var canReplaceAccountToken: Bool {
        !replacementAccountTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }

    var canCreateOrganizationToken: Bool {
        GitHubOrganizationName.isValid(organizationInput) && !isBusy
    }

    var organizationTokenURL: URL {
        GitHubTokenTemplate.url(
            resourceOwner: GitHubOrganizationName.normalized(organizationInput)
        )
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        let refreshRequested = SharedPreferences.defaults.bool(
            forKey: SharedPreferences.Key.githubRefreshRequested
        )
        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRequested)

        do {
            let loadedConnections = try GitHubTokenStore.readConnections(defaultUsername: username)
            guard !loadedConnections.isEmpty else {
                phase = .disconnected
                if !username.isEmpty {
                    message = "Reconnect GitHub once to upgrade secure token storage."
                }
                return
            }
            // Rewriting is intentional: it upgrades legacy raw-token and token-array entries
            // to named connection records with stable identifiers.
            try GitHubTokenStore.replace(with: loadedConnections)
            storedConnections = loadedConnections
            syncConnectionState()
            phase = .connected

            let archive = try ActivitySnapshotStore.read()
            if let archive {
                activityArchive = archive
                username = archive.username
                lastRefresh = archive.savedAt
                reloadWidgets()
            }

            let refreshAge = lastRefresh.map { Date().timeIntervalSince($0) } ?? .infinity
            let cachedRefreshFailed = archive.map {
                $0.daily.state == .error || $0.weekly.state == .error
            } ?? false
            if refreshRequested || cachedRefreshFailed || refreshAge > 15 * 60 {
                await refresh(using: loadedConnections.map(\.token), scope: .recentBranches)
            }
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func handleActivation() async {
        guard didBootstrap else {
            await bootstrap()
            return
        }
        guard SharedPreferences.defaults.bool(forKey: SharedPreferences.Key.githubRefreshRequested) else {
            return
        }

        guard hasStoredToken else {
            SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRequested)
            return
        }
        guard !isBusy else { return }

        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRequested)
        await refresh(scope: .recentBranches)
    }

    func connect() async {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        phase = .connecting
        message = nil
        notice = nil

        do {
            let inspection = try await service.inspectToken(token: token)
            let archive = try await service.fetchSnapshots(tokens: [token], scope: .allBranches)
            let connection = GitHubStoredConnection(
                id: UUID(),
                owner: inspection.username,
                kind: .account,
                token: token,
                repositoryCount: inspection.repositoryCount,
                privateRepositoryCount: inspection.privateRepositoryCount,
                validatedAt: .now
            )
            try GitHubTokenStore.replace(with: [connection])
            storedConnections = [connection]
            syncConnectionState()
            username = archive.username
            try persist(archive)
            tokenInput = ""
            phase = .connected
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func addOrganization() async {
        let organization = GitHubOrganizationName.normalized(organizationInput)
        let token = additionalTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubOrganizationName.isValid(organization), !token.isEmpty else {
            message = GitHubActivityError.invalidOrganizationName.localizedDescription
            return
        }

        phase = .connecting
        message = nil
        notice = nil

        do {
            let existing = storedConnections.isEmpty
                ? try GitHubTokenStore.readConnections(defaultUsername: username)
                : storedConnections
            guard !existing.contains(where: { $0.token == token }) else {
                phase = .connected
                message = "This token is already connected."
                return
            }
            guard !existing.contains(where: {
                $0.kind == .organization
                    && $0.owner.caseInsensitiveCompare(organization) == .orderedSame
            }) else {
                phase = .connected
                message = "\(organization) is already connected. Remove it before replacing its token."
                return
            }

            let inspection = try await service.inspectToken(
                token: token,
                resourceOwner: organization
            )
            if !username.isEmpty,
               username.caseInsensitiveCompare(inspection.username) != .orderedSame {
                throw GitHubActivityError.tokenAccountMismatch
            }
            let connection = GitHubStoredConnection(
                id: UUID(),
                owner: inspection.owner,
                kind: .organization,
                token: token,
                repositoryCount: inspection.repositoryCount,
                privateRepositoryCount: inspection.privateRepositoryCount,
                validatedAt: .now
            )
            let updatedConnections = existing + [connection]
            let tokens = updatedConnections.map(\.token)
            let archive = try await service.fetchSnapshots(tokens: tokens, scope: .allBranches)
            try GitHubTokenStore.replace(with: updatedConnections)
            storedConnections = updatedConnections
            syncConnectionState()
            try persist(archive)
            organizationInput = ""
            additionalTokenInput = ""
            phase = .connected
            if inspection.privateRepositoryCount == 0 {
                notice = "\(inspection.owner) connected, but this token currently exposes no private repositories. It may still be awaiting organization approval."
            }
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func replaceAccountToken() async {
        let token = replacementAccountTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        phase = .connecting
        message = nil
        notice = nil

        do {
            let existing = storedConnections.isEmpty
                ? try GitHubTokenStore.readConnections(defaultUsername: username)
                : storedConnections
            guard let currentAccount = existing.first(where: { $0.kind == .account }) else {
                phase = .disconnected
                message = "Connect a GitHub account before replacing its token."
                return
            }
            guard !existing.contains(where: { $0.id != currentAccount.id && $0.token == token }) else {
                phase = .connected
                message = "This token is already connected."
                return
            }

            let inspection = try await service.inspectToken(token: token)
            guard inspection.username.caseInsensitiveCompare(currentAccount.owner) == .orderedSame else {
                throw GitHubActivityError.tokenAccountMismatch
            }

            let updatedConnections = existing.map { connection in
                guard connection.id == currentAccount.id else { return connection }
                return GitHubStoredConnection(
                    id: connection.id,
                    owner: inspection.username,
                    kind: .account,
                    token: token,
                    repositoryCount: inspection.repositoryCount,
                    privateRepositoryCount: inspection.privateRepositoryCount,
                    validatedAt: .now
                )
            }
            let archive = try await service.fetchSnapshots(
                tokens: updatedConnections.map(\.token),
                scope: .allBranches
            )

            try GitHubTokenStore.replace(with: updatedConnections)
            storedConnections = updatedConnections
            syncConnectionState()
            try persist(archive)
            replacementAccountTokenInput = ""
            phase = .connected
            notice = "Account token replaced. \(inspection.repositoryCount) repositories, including \(inspection.privateRepositoryCount) private, are available to Gitlines."
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func removeOrganization(id: UUID) async {
        guard let connection = storedConnections.first(where: { $0.id == id }),
              connection.kind == .organization else { return }

        phase = .refreshing
        message = nil
        notice = nil

        do {
            let remaining = storedConnections.filter { $0.id != id }
            try GitHubTokenStore.replace(with: remaining)
            storedConnections = remaining
            syncConnectionState()
            notice = "\(connection.owner) was removed."
            await refresh(using: remaining.map(\.token), scope: .allBranches)
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func refresh(scope: GitHubRefreshScope = .recentBranches) async {
        do {
            let loadedConnections = storedConnections.isEmpty
                ? try GitHubTokenStore.readConnections(defaultUsername: username)
                : storedConnections
            guard !loadedConnections.isEmpty else {
                storedConnections = []
                syncConnectionState()
                phase = .disconnected
                return
            }
            storedConnections = loadedConnections
            syncConnectionState()
            await refresh(using: loadedConnections.map(\.token), scope: scope)
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func disconnect() {
        do {
            try GitHubTokenStore.remove()
        } catch {
            phase = .failed
            message = error.localizedDescription
            return
        }

        let cacheRemovalError: Error?
        do {
            try ActivitySnapshotStore.remove()
            cacheRemovalError = nil
        } catch {
            cacheRemovalError = error
        }

        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubUsername)
        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.lastSuccessfulRefresh)
        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRequested)
        GitHubBranchCache.remove()
        username = ""
        lastRefresh = nil
        activityArchive = nil
        storedConnections = []
        syncConnectionState()
        tokenInput = ""
        replacementAccountTokenInput = ""
        organizationInput = ""
        additionalTokenInput = ""
        phase = cacheRemovalError == nil ? .disconnected : .failed
        message = cacheRemovalError?.localizedDescription
        notice = nil
        reloadWidgets()
    }

    private func refresh(using tokens: [String], scope: GitHubRefreshScope) async {
        phase = .refreshing
        message = nil

        do {
            let archive = try await service.fetchSnapshots(tokens: tokens, scope: scope)
            if case .allBranches = scope {
                await refreshConnectionMetadata()
            }
            try persist(archive)
            phase = .connected
        } catch {
            let userMessage = error.localizedDescription
            if let archive = try? ActivitySnapshotStore.read() {
                let failedArchive = archive.markingRefreshError(userMessage)
                try? ActivitySnapshotStore.write(failedArchive)
                activityArchive = failedArchive
                reloadWidgets()
            }
            phase = .failed
            message = userMessage
        }
    }

    private func refreshConnectionMetadata() async {
        var refreshed: [GitHubStoredConnection] = []

        for connection in storedConnections {
            let requestedOwner = connection.kind == .organization ? connection.owner : nil
            guard let inspection = try? await service.inspectToken(
                token: connection.token,
                resourceOwner: requestedOwner
            ) else {
                refreshed.append(connection)
                continue
            }

            refreshed.append(
                GitHubStoredConnection(
                    id: connection.id,
                    owner: connection.kind == .account ? inspection.username : inspection.owner,
                    kind: connection.kind,
                    token: connection.token,
                    repositoryCount: inspection.repositoryCount,
                    privateRepositoryCount: inspection.privateRepositoryCount,
                    validatedAt: .now
                )
            )
        }

        guard refreshed.count == storedConnections.count else { return }
        do {
            try GitHubTokenStore.replace(with: refreshed)
        } catch {
            return
        }
        storedConnections = refreshed
        syncConnectionState()
    }

    private func syncConnectionState() {
        connections = storedConnections.map(GitHubConnectionSummary.init(connection:))
        tokenCount = storedConnections.count
        hasStoredToken = !storedConnections.isEmpty
    }

    private func persist(_ archive: ActivitySnapshotArchive) throws {
        try ActivitySnapshotStore.write(archive)
        activityArchive = archive
        username = archive.username
        lastRefresh = archive.savedAt
        SharedPreferences.defaults.set(archive.username, forKey: SharedPreferences.Key.githubUsername)
        SharedPreferences.defaults.set(archive.savedAt, forKey: SharedPreferences.Key.lastSuccessfulRefresh)
        reloadWidgets()
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidtgetWidgetKind.value)
    }
}
