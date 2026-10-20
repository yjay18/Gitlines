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
    @Published private(set) var currentDate = Date()
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
    private let isSampleSession: Bool
    private var didBootstrap = false
    private var lastRefreshAttempt: Date?
    private var syncLease: GitHubHostSyncLease?
    @Published private(set) var isWaitingForSyncAccess = false
    private var storedConnections: [GitHubStoredConnection] = []

    init(service: GitHubActivityService = GitHubActivityService()) {
        self.service = service
        isSampleSession = ProcessInfo.processInfo.arguments.contains("--sample-data")
        guard !isSampleSession else { return }
        isWaitingForSyncAccess = true
        username = SharedPreferences.defaults.string(forKey: SharedPreferences.Key.githubUsername) ?? ""
        lastRefresh = SharedPreferences.defaults.object(
            forKey: SharedPreferences.Key.lastSuccessfulRefresh
        ) as? Date
    }

    var isBusy: Bool {
        phase == .connecting || phase == .refreshing || isSyncingHistory || isWaitingForSyncAccess
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

    func bootstrap(waitForSyncAccess: Bool = true) async {
        guard !didBootstrap else { return }
        didBootstrap = true

        // Keeps App Store screenshots and demos free of the owner's private repository data.
        // A normal first launch reaches the same disconnected sample state without this flag.
        guard !isSampleSession else {
            phase = .disconnected
            return
        }

        do {
            while syncLease == nil {
                syncLease = try GitHubHostSyncLease.acquire()
                if syncLease == nil {
                    guard waitForSyncAccess else {
                        isWaitingForSyncAccess = false
                        return
                    }
                    message = "Finishing background refresh…"
                    try await Task.sleep(for: .seconds(1))
                }
            }
            isWaitingForSyncAccess = false
            message = nil
            currentDate = Date()
            lastRefreshAttempt = SharedPreferences.defaults.object(forKey: SharedPreferences.Key.githubLastRefreshAttempt) as? Date
            historyRetryAt = SharedPreferences.defaults.object(forKey: SharedPreferences.Key.githubRefreshRetryAt) as? Date
            let refreshRequested = SharedPreferences.defaults.bool(forKey: SharedPreferences.Key.githubRefreshRequested)
            SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRequested)
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
            let accountOwner = loadedConnections.first(where: { $0.kind == .account })?.owner
                ?? loadedConnections[0].owner
            if let cached = try? DashboardHistoryStore.read(),
               cached.username.caseInsensitiveCompare(accountOwner) == .orderedSame {
                dashboardHistory = cached
            }
            phase = .connected

            username = accountOwner
            let archive = try ActivitySnapshotStore.read().flatMap { cached in
                cached.username.caseInsensitiveCompare(accountOwner) == .orderedSame ? cached : nil
            }
            lastRefresh = archive?.savedAt
            if let archive {
                activityArchive = archive
                username = archive.username
                lastRefresh = archive.savedAt
                reloadWidgets()
            }

            if refreshRequested || automaticRefreshIsDue {
                await refreshConnections(scope: .recentBranches)
            }
        } catch {
            isWaitingForSyncAccess = false
            phase = .failed
            message = error.localizedDescription
        }
    }

    func handleActivation() async {
        currentDate = Date()
        guard !isSampleSession else { return }
        guard didBootstrap else {
            await bootstrap()
            return
        }
        guard hasStoredToken else {
            SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRequested)
            return
        }
        guard !isBusy else { return }
        let requested = SharedPreferences.defaults.bool(forKey: SharedPreferences.Key.githubRefreshRequested)
        guard requested || automaticRefreshIsDue else { return }

        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRequested)
        await refresh(scope: .recentBranches)
    }

    private var automaticRefreshIsDue: Bool {
        Self.shouldAutomaticallyRefresh(lastRefresh: lastRefresh, historyDate: dashboardHistory?.asOf,
            lastAttempt: lastRefreshAttempt, retryAt: historyRetryAt, now: currentDate,
            interval: TimeInterval(SharedPreferences.refreshInterval.minutes * 60))
    }

    static func shouldAutomaticallyRefresh(lastRefresh: Date?, historyDate: Date?, lastAttempt: Date?,
                                           retryAt: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard retryAt.map({ now >= $0 }) ?? true,
              lastAttempt.map({ now.timeIntervalSince($0) >= interval }) ?? true else { return false }
        return [lastRefresh, historyDate].contains { date in
            date.map { now.timeIntervalSince($0) >= interval } ?? true
        }
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
        guard isSigningIn else { return }
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
        guard canConnect, !hasStoredToken else { return }
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        phase = .connecting
        message = nil
        notice = nil

        do {
            let inspection = try await service.inspectToken(token: token)
            let archive = try await service.fetchSnapshots(tokens: [token], scope: .allBranches, existingHistory: dashboardHistory)
            let connection = GitHubStoredConnection(
                id: UUID(),
                owner: inspection.username,
                kind: .account,
                token: token,
                repositoryCount: inspection.repositoryCount,
                privateRepositoryCount: inspection.privateRepositoryCount,
                validatedAt: .now
            )
            try Task.checkCancellation()
            try GitHubTokenStore.replace(with: [connection])
            storedConnections = [connection]
            syncConnectionState()
            username = archive.username
            try persist(archive)
            tokenInput = ""
            phase = .connected
            await refreshConnections(scope: .allBranches)
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func addOrganization() async {
        guard !isBusy, hasStoredToken else { return }
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
            let archive = try await service.fetchSnapshots(tokens: tokens, scope: .allBranches, existingHistory: dashboardHistory)
            try Task.checkCancellation()
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
            await refreshConnections(scope: .allBranches)
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func replaceAccountToken() async {
        guard canReplaceAccountToken, hasStoredToken else { return }
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
                scope: .allBranches,
                existingHistory: dashboardHistory
            )

            try Task.checkCancellation()
            try GitHubTokenStore.replace(with: updatedConnections)
            storedConnections = updatedConnections
            syncConnectionState()
            try persist(archive)
            replacementAccountTokenInput = ""
            phase = .connected
            notice = "Account token replaced. \(inspection.repositoryCount) repositories, including \(inspection.privateRepositoryCount) private, are available to Gitlines."
            await refreshConnections(scope: .allBranches)
        } catch {
            phase = .failed
            message = error.localizedDescription
        }
    }

    func removeOrganization(id: UUID) async {
        guard !isBusy, let connection = storedConnections.first(where: { $0.id == id }),
              connection.kind == .organization else { return }

        phase = .refreshing
        message = nil
        notice = nil

        do {
            let remaining = storedConnections.filter { $0.id != id }
            try GitHubTokenStore.replace(with: remaining)
            storedConnections = remaining
            syncConnectionState()
            let cacheErrors = removeCachedActivity()
            reloadWidgets()
            guard cacheErrors.isEmpty else {
                phase = .failed
                message = "Organization removed, but cached activity could not be cleared: \(cacheErrors.joined(separator: "; "))"
                return
            }
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
        startHistorySync(range: range, scope: .allBranches, incremental: false)
    }

    private func startHistorySync(range: DateInterval, scope: GitHubRefreshScope, incremental: Bool) {
        currentDate = Date()
        lastRefreshAttempt = currentDate
        SharedPreferences.defaults.set(currentDate, forKey: SharedPreferences.Key.githubLastRefreshAttempt)
        historyRetryTask?.cancel()
        historyRetryTask = nil
        historyRetryAt = nil
        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRetryAt)
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
                    tokens: connections.map(\.token), range: range, existing: dashboardHistory,
                    incremental: incremental
                ) { [weak self] history, status, completed, total in
                    await self?.acceptHistoryProgress(history, syncID: syncID, status: status, completed: completed, total: total)
                }
                try Task.checkCancellation()
                guard historySyncID == syncID else { return }
                dashboardHistory = result
                try DashboardHistoryStore.write(result)
                let failed = result.coverage.values.filter { $0.error != nil }.count
                historyProgress = failed == 0 ? "Sync complete" : "Sync finished with \(failed) repository errors"
                await refreshSnapshots(scope: scope, through: range.end)
            } catch is CancellationError {
                guard historySyncID == syncID else { return }
                phase = .connected
                historyProgress = "Sync stopped. Completed repositories are saved."
            } catch {
                guard historySyncID == syncID else { return }
                historyError = error.localizedDescription
                phase = .failed
                message = error.localizedDescription
                historyProgress = "Sync incomplete"
                if case GitHubActivityError.rateLimited(let reset) = error, let reset {
                    let retryAt = max(reset.addingTimeInterval(3), Date().addingTimeInterval(5))
                    historyRetryAt = retryAt
                    SharedPreferences.defaults.set(retryAt, forKey: SharedPreferences.Key.githubRefreshRetryAt)
                    historyProgress = "Sync paused. It will resume after GitHub's API limit resets."
                    historyRetryTask = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(max(1, retryAt.timeIntervalSinceNow))) }
                        catch { return }
                        guard let self else { return }
                        while self.isBusy {
                            do { try await Task.sleep(for: .seconds(5)) } catch { return }
                        }
                        guard self.hasStoredToken, !Task.isCancelled else { return }
                        self.startHistorySync(range: range, scope: scope, incremental: incremental)
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
        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRetryAt)
    }

    func disconnect() {
        guard !isBusy else { return }
        cancelHistorySync()
        historySyncID = nil
        isSyncingHistory = false
        do {
            try GitHubTokenStore.remove()
        } catch {
            phase = .failed
            message = error.localizedDescription
            return
        }

        let cacheRemovalErrors = removeCachedActivity()

        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubUsername)
        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubRefreshRequested)
        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.githubLastRefreshAttempt)
        lastRefreshAttempt = nil
        username = ""
        signInStatus = nil
        historyProgress = ""
        historyCompleted = 0
        historyTotal = 0
        historyError = nil
        storedConnections = []
        syncConnectionState()
        tokenInput = ""
        replacementAccountTokenInput = ""
        organizationInput = ""
        additionalTokenInput = ""
        phase = cacheRemovalErrors.isEmpty ? .disconnected : .failed
        message = cacheRemovalErrors.isEmpty ? nil : cacheRemovalErrors.joined(separator: "\n")
        notice = nil
        reloadWidgets()
    }

    private func refreshConnections(scope: GitHubRefreshScope) async {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -91, to: Calendar.current.startOfDay(for: now))!
        phase = .connected
        message = nil
        startHistorySync(range: DateInterval(start: start, end: now), scope: scope, incremental: true)
        await historyTask?.value
    }

    private func refreshSnapshots(scope: GitHubRefreshScope, through date: Date) async {
        phase = .refreshing
        message = nil

        do {
            let archive: ActivitySnapshotArchive
            if let history = dashboardHistory, let saved = service.snapshots(from: history, now: date) {
                // A second recent-branch scan would drop commits discovered on new branches.
                archive = saved
            } else {
                let fresh = try await renewCredentialsIfNeeded()
                archive = try await service.fetchSnapshots(tokens: fresh.map(\.token),
                    scope: .allBranches, existingHistory: dashboardHistory)
            }
            try Task.checkCancellation()
            if case .allBranches = scope {
                await refreshConnectionMetadata()
            }
            try persist(archive)
            phase = .connected
        } catch is CancellationError {
            phase = .connected
            historyProgress = "Sync stopped. Completed repositories are saved."
        } catch {
            let userMessage = error.localizedDescription
            if let archive = activityArchive {
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
        if let account = storedConnections.first(where: { $0.kind == .account }) {
            username = account.owner
            SharedPreferences.defaults.set(account.owner, forKey: SharedPreferences.Key.githubUsername)
        }
    }

    // Any change that removes repository access must clear every derived cache, even
    // when one removal fails. A failed refresh must not restore the removed activity.
    private func removeCachedActivity() -> [String] {
        var errors: [String] = []
        for removeCache in [ActivitySnapshotStore.remove, DashboardHistoryStore.remove] {
            do { try removeCache() }
            catch { errors.append(error.localizedDescription) }
        }
        GitHubBranchCache.remove()
        SharedPreferences.defaults.removeObject(forKey: SharedPreferences.Key.lastSuccessfulRefresh)
        activityArchive = nil
        dashboardHistory = nil
        lastRefresh = nil
        return errors
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
