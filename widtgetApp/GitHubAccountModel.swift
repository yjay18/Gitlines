import AppKit
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
    @Published private(set) var dashboardHistory: DashboardHistory?
    @Published private(set) var isSyncingHistory = false
    @Published private(set) var historyProgress = ""
    @Published private(set) var historyCompleted = 0
    @Published private(set) var historyTotal = 0
    @Published private(set) var historyError: String?
    @Published private(set) var historyRetryAt: Date?
    private var historyRetryTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var historySyncID: UUID?


    @Published private(set) var deviceAuthorization: GitHubDeviceAuthorization?
    @Published private(set) var isSigningIn = false
    @Published private(set) var signInStatus: String?
    private var signInTask: Task<Void, Never>?
    private var signInID: UUID?
    private let signInService = GitHubSignInService()

    var usesGitHubSignIn: Bool {
        storedConnections.contains { $0.kind == .account && $0.oauth != nil }
    }

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
        phase == .connecting || phase == .refreshing || isSyncingHistory
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
            if let cached = try? DashboardHistoryStore.read(),
               cached.username.caseInsensitiveCompare(loadedConnections.first?.owner ?? "") == .orderedSame {
                dashboardHistory = cached
            }
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
                await refreshConnections(scope: .recentBranches)
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

    func beginSignIn() {
        guard !isBusy else { return }
        let id = UUID()
        signInID = id
        isSigningIn = true
        phase = .connecting
        message = nil
        notice = nil
        signInStatus = "Requesting a GitHub sign-in code…"
        signInTask = Task { [weak self] in
            await self?.performSignIn(id: id)
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        signInID = nil
        deviceAuthorization = nil
        isSigningIn = false
        signInStatus = "Sign-in cancelled."
        phase = hasStoredToken ? .connected : .disconnected
    }

    func openGitHubSignIn() {
        guard let device = deviceAuthorization else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(device.userCode, forType: .string)
        NSWorkspace.shared.open(device.verificationURL)
    }

    private func performSignIn(id: UUID) async {
        defer {
            if signInID == id {
                signInID = nil
                signInTask = nil
                deviceAuthorization = nil
                isSigningIn = false
            }
        }
        do {
            let device = try await signInService.begin(clientID: GitHubSignInConfiguration.clientID)
            try Task.checkCancellation()
            guard signInID == id else { return }
            deviceAuthorization = device
            signInStatus = "Waiting for approval on GitHub…"
            let credential = try await signInService.authorize(device, clientID: GitHubSignInConfiguration.clientID)
            try Task.checkCancellation()
            guard signInID == id else { return }
            deviceAuthorization = nil
            signInStatus = "GitHub approved sign-in. Verifying your account…"
            let identity = try await service.username(token: credential.accessToken)
            let existing = try GitHubTokenStore.readConnections(defaultUsername: username)
            if let account = existing.first(where: { $0.kind == .account }),
               identity.caseInsensitiveCompare(account.owner) != .orderedSame {
                throw GitHubActivityError.tokenAccountMismatch
            }
            // Repository discovery is a separate sync operation. A failed or empty
            // repository response must not discard an approved account sign-in.
            let connection = GitHubStoredConnection(
                id: existing.first(where: { $0.kind == .account })?.id ?? UUID(),
                owner: identity, kind: .account, token: credential.accessToken,
                repositoryCount: nil,
                privateRepositoryCount: nil,
                validatedAt: .now, oauth: credential.session
            )
            // Keep manually connected organizations until the user chooses to remove them.
            let updated = [connection] + existing.filter { $0.kind == .organization }
            try Task.checkCancellation()
            guard signInID == id else { return }
            try GitHubTokenStore.replace(with: updated)
            storedConnections = updated
            username = identity
            syncConnectionState()
            tokenInput = ""
            replacementAccountTokenInput = ""
            // Sign-in is committed. Refresh is a separate operation and cannot undo it.
            signInID = nil
            signInTask = nil
            isSigningIn = false
            signInStatus = "Connected to GitHub as @\(identity)."
            notice = "Signed in with GitHub. Repository access can be changed on GitHub at any time."
            await refreshConnectionMetadata()
            await refreshConnections(scope: .allBranches)
        } catch {
            guard signInID == id else { return }
            if error is CancellationError {
                phase = hasStoredToken ? .connected : .disconnected
            } else {
                phase = .failed
                message = error.localizedDescription
                signInStatus = "GitHub sign-in was not saved: \(error.localizedDescription)"
            }
        }
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
            let existing = try await renewCredentialsIfNeeded()
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
            let existing = try await renewCredentialsIfNeeded()
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
            await refreshConnections(scope: .allBranches)
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func refresh(scope: GitHubRefreshScope = .recentBranches) async {
        guard !isBusy else { return }
        phase = .refreshing
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
            await refreshConnections(scope: scope)
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func syncDashboardHistory(range: DateInterval) {
        guard !isBusy, hasStoredToken else { return }
        historyRetryTask?.cancel()
        historyRetryTask = nil
        historyRetryAt = nil
        let syncID = UUID()
        historySyncID = syncID
        isSyncingHistory = true
        historyError = nil
        historyProgress = "Loading repositories…"
        historyCompleted = 0
        historyTotal = 0
        historyTask = Task {
            defer { if historySyncID == syncID { isSyncingHistory = false; historyTask = nil; historySyncID = nil } }
            do {
                let connections = try await renewCredentialsIfNeeded()
                let result = try await service.fetchDashboardHistory(
                    tokens: connections.map(\.token), range: range, existing: dashboardHistory
                ) { [weak self] history, status, completed, total in
                    await self?.acceptHistoryProgress(history, syncID: syncID, status: status, completed: completed, total: total)
                }
                try Task.checkCancellation()
                guard historySyncID == syncID else { return }
                dashboardHistory = result
                try DashboardHistoryStore.write(result)
                let failed = result.coverage.values.filter { $0.error != nil }.count
                historyProgress = failed == 0 ? "Sync complete" : "Sync finished with \(failed) repository errors"
            } catch is CancellationError {
                historyProgress = "Sync stopped. Completed repositories are saved."
            } catch {
                historyError = error.localizedDescription
                historyProgress = "Sync incomplete"
                if case GitHubActivityError.rateLimited(let reset) = error, let reset {
                    let retryAt = max(reset.addingTimeInterval(3), Date().addingTimeInterval(5))
                    historyRetryAt = retryAt
                    historyProgress = "Sync paused. It will resume after GitHub's API limit resets."
                    historyRetryTask = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(max(1, retryAt.timeIntervalSinceNow))) }
                        catch { return }
                        guard let self else { return }
                        while self.isBusy {
                            do { try await Task.sleep(for: .seconds(5)) } catch { return }
                        }
                        guard self.hasStoredToken, !Task.isCancelled else { return }
                        self.syncDashboardHistory(range: range)
                    }
                }
            }
        }
    }

    private func acceptHistoryProgress(_ history: DashboardHistory, syncID: UUID, status: String, completed: Int, total: Int) {
        guard historySyncID == syncID, !Task.isCancelled else { return }
        dashboardHistory = history
        historyProgress = status
        historyCompleted = completed
        historyTotal = total
        do { try DashboardHistoryStore.write(history) }
        catch { historyError = "Could not save dashboard history: \(error.localizedDescription)" }
    }

    func cancelHistorySync() {
        historyTask?.cancel()
        historyRetryTask?.cancel()
        historyRetryTask = nil
        historyRetryAt = nil
    }

    func disconnect() {
        cancelHistorySync()
        historySyncID = nil
        isSyncingHistory = false
        if isSigningIn { cancelSignIn() }
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
            try DashboardHistoryStore.remove()
            cacheRemovalError = nil
        } catch {
            cacheRemovalError = error
        }

        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubUsername)
        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.lastSuccessfulRefresh)
        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRequested)
        GitHubBranchCache.remove()
        username = ""
        signInStatus = nil
        lastRefresh = nil
        activityArchive = nil
        dashboardHistory = nil
        historyError = nil
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

    private func refreshConnections(scope: GitHubRefreshScope) async {
        phase = .refreshing
        message = nil

        do {
            let fresh = try await renewCredentialsIfNeeded()
            let archive = try await service.fetchSnapshots(tokens: fresh.map(\.token), scope: scope)
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

    private func renewCredentialsIfNeeded() async throws -> [GitHubStoredConnection] {
        var fresh = try GitHubTokenStore.readConnections(defaultUsername: username)
        for index in fresh.indices {
            guard let oauth = fresh[index].oauth,
                  oauth.expiresAt.timeIntervalSinceNow < 60 else { continue }
            let credentials = try await signInService.refresh(oauth)
            let old = fresh[index]
            fresh[index] = GitHubStoredConnection(
                id: old.id, owner: old.owner, kind: old.kind, token: credentials.accessToken,
                repositoryCount: old.repositoryCount, privateRepositoryCount: old.privateRepositoryCount,
                validatedAt: old.validatedAt, oauth: credentials.session
            )
            // GitHub invalidates the old refresh token immediately. Save its replacement
            // before fetching anything else, even if a later API request fails.
            try GitHubTokenStore.replace(with: fresh)
            storedConnections = fresh
            let identity = try await service.username(token: credentials.accessToken)
            guard identity.caseInsensitiveCompare(old.owner) == .orderedSame else {
                throw GitHubActivityError.tokenAccountMismatch
            }
        }
        storedConnections = fresh
        syncConnectionState()
        return fresh
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
                    validatedAt: .now,
                    oauth: connection.oauth
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
