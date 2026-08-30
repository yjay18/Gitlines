import Foundation
import Security

enum GitHubTokenStoreError: LocalizedError {
    case invalidTokenData
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidTokenData:
            "The saved GitHub token could not be read."
        case .keychainStatus(let status):
            "Keychain returned error \(status)."
        }
    }
}

enum GitHubConnectionKind: String, Codable, Sendable {
    case account
    case organization
}

struct GitHubStoredConnection: Codable, Identifiable, Sendable {
    let id: UUID
    let owner: String
    let kind: GitHubConnectionKind
    let token: String
    let repositoryCount: Int?
    let privateRepositoryCount: Int?
    let validatedAt: Date?
}

struct GitHubConnectionSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let owner: String
    let kind: GitHubConnectionKind
    let repositoryCount: Int?
    let privateRepositoryCount: Int?

    init(connection: GitHubStoredConnection) {
        id = connection.id
        owner = connection.owner
        kind = connection.kind
        repositoryCount = connection.repositoryCount
        privateRepositoryCount = connection.privateRepositoryCount
    }
}

private struct GitHubTokenArchive: Codable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let connections: [GitHubStoredConnection]

    init(connections: [GitHubStoredConnection]) {
        schemaVersion = Self.currentSchemaVersion
        self.connections = connections
    }
}

enum GitHubTokenStore {
    private static let service = "com.yjay18.widtget.github"
    private static let account = "activity-token"

    static func readConnections(defaultUsername: String = "") throws -> [GitHubStoredConnection] {
        if let data = try readData(using: protectedLookup) {
            return try decodeConnections(data, defaultUsername: defaultUsername)
        }

        // Earlier development builds could write to the classic login Keychain. Migrate that
        // credential once into the app-scoped data-protection Keychain instead of making the user
        // reconnect after an update.
        guard let legacyData = try readData(using: legacyLookup) else { return [] }
        let connections = try decodeConnections(legacyData, defaultUsername: defaultUsername)
        try replace(with: connections)
        try removeData(using: legacyLookup)
        return connections
    }

    private static func decodeConnections(
        _ data: Data,
        defaultUsername: String
    ) throws -> [GitHubStoredConnection] {
        if let archive = try? JSONDecoder().decode(GitHubTokenArchive.self, from: data),
           archive.schemaVersion == GitHubTokenArchive.currentSchemaVersion {
            return normalized(archive.connections)
        }
        if let tokens = try? JSONDecoder().decode([String].self, from: data) {
            return legacyConnections(tokens: tokens, defaultUsername: defaultUsername)
        }
        if let legacyToken = String(data: data, encoding: .utf8), !legacyToken.isEmpty {
            return legacyConnections(tokens: [legacyToken], defaultUsername: defaultUsername)
        }
        throw GitHubTokenStoreError.invalidTokenData
    }

    static func readAll() throws -> [String] {
        try readConnections().map(\.token)
    }

    private static func readData(using lookup: [String: Any]) throws -> Data? {
        var query = lookup
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GitHubTokenStoreError.keychainStatus(status) }
        guard let data = result as? Data else {
            throw GitHubTokenStoreError.invalidTokenData
        }
        return data
    }

    static func replace(with connections: [GitHubStoredConnection]) throws {
        let values = normalized(connections)
        guard !values.isEmpty else {
            try remove()
            return
        }
        let data = try JSONEncoder().encode(GitHubTokenArchive(connections: values))
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(protectedLookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw GitHubTokenStoreError.keychainStatus(updateStatus)
        }

        var add = protectedLookup
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Gitlines GitHub activity token"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GitHubTokenStoreError.keychainStatus(addStatus)
        }
    }

    static func remove() throws {
        try removeData(using: protectedLookup)
        try removeData(using: legacyLookup)
    }

    private static func removeData(using lookup: [String: Any]) throws {
        let status = SecItemDelete(lookup as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubTokenStoreError.keychainStatus(status)
        }
    }

    private static var protectedLookup: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private static var legacyLookup: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func normalized(_ connections: [GitHubStoredConnection]) -> [GitHubStoredConnection] {
        var seen: Set<String> = []
        return connections.compactMap { connection in
            let token = connection.token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, seen.insert(token).inserted else { return nil }
            return GitHubStoredConnection(
                id: connection.id,
                owner: connection.owner,
                kind: connection.kind,
                token: token,
                repositoryCount: connection.repositoryCount,
                privateRepositoryCount: connection.privateRepositoryCount,
                validatedAt: connection.validatedAt
            )
        }
    }

    private static func legacyConnections(
        tokens: [String],
        defaultUsername: String
    ) -> [GitHubStoredConnection] {
        let values = tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.enumerated().map { index, token in
            GitHubStoredConnection(
                id: UUID(),
                owner: index == 0 && !defaultUsername.isEmpty
                    ? defaultUsername
                    : (index == 0 ? "GitHub account" : "Repository owner \(index + 1)"),
                kind: index == 0 ? .account : .organization,
                token: token,
                repositoryCount: nil,
                privateRepositoryCount: nil,
                validatedAt: nil
            )
        }
    }
}

enum GitHubActivityError: LocalizedError {
    case invalidToken
    case accessDenied
    case rateLimited(Date?)
    case notFound
    case tokenAccountMismatch
    case invalidOrganizationName
    case organizationNotAccessible(String)
    case api(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            "GitHub rejected this token. Check that it is active and try again."
        case .accessDenied:
            "This token needs read-only Contents access to the repositories you want to include."
        case .rateLimited(let resetAt):
            if let resetAt {
                "GitHub’s API limit was reached. Try again after \(resetAt.formatted(date: .omitted, time: .shortened))."
            } else {
                "GitHub’s API limit was reached. Try again later."
            }
        case .notFound:
            "A GitHub repository or branch is no longer available."
        case .tokenAccountMismatch:
            "Every connected token must belong to the same GitHub account."
        case .invalidOrganizationName:
            "Enter a valid GitHub organization name."
        case .organizationNotAccessible(let owner):
            "This token does not expose any repositories owned by \(owner). Check the resource owner, selected repositories, and organization approval."
        case .api(let message):
            message
        case .invalidResponse:
            "GitHub returned an unexpected response."
        }
    }
}

struct GitHubTokenInspection: Sendable {
    let username: String
    let owner: String
    let repositoryCount: Int
    let privateRepositoryCount: Int
}

enum GitHubTokenTemplate {
    static func url(resourceOwner: String? = nil) -> URL {
        var components = URLComponents(string: "https://github.com/settings/personal-access-tokens/new")!
        var query = [
            URLQueryItem(name: "name", value: "Gitlines activity"),
            URLQueryItem(
                name: "description",
                value: "Read-only repository activity for the Gitlines macOS widget"
            ),
            URLQueryItem(name: "expires_in", value: "90"),
            URLQueryItem(name: "contents", value: "read")
        ]
        if let resourceOwner, !resourceOwner.isEmpty {
            query.append(URLQueryItem(name: "target_name", value: resourceOwner))
        }
        components.queryItems = query
        return components.url!
    }
}

enum GitHubOrganizationName {
    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    }

    static func isValid(_ value: String) -> Bool {
        let name = normalized(value)
        guard !name.isEmpty, name.count <= 39,
              name.first != "-", name.last != "-" else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-"
        }
    }
}

enum GitHubRefreshScope: Sendable {
    case recentBranches
    case allBranches
}

struct GitHubActivityService: Sendable {
    private let session: URLSession
    private let calendar: Calendar

    init(session: URLSession = .shared, calendar: Calendar = .autoupdatingCurrent) {
        self.session = session
        self.calendar = calendar
    }

    func inspectToken(
        token: String,
        resourceOwner: String? = nil
    ) async throws -> GitHubTokenInspection {
        let user: UserResponse = try await get(path: "/user", token: token)
        let repositories = try await allRepositories(token: token)
        let requestedOwner = resourceOwner.map(GitHubOrganizationName.normalized)

        if let requestedOwner {
            guard GitHubOrganizationName.isValid(requestedOwner) else {
                throw GitHubActivityError.invalidOrganizationName
            }
            let ownedRepositories = repositories.filter {
                $0.ownerName.caseInsensitiveCompare(requestedOwner) == .orderedSame
            }
            guard !ownedRepositories.isEmpty else {
                throw GitHubActivityError.organizationNotAccessible(requestedOwner)
            }
            return GitHubTokenInspection(
                username: user.login,
                owner: requestedOwner,
                repositoryCount: ownedRepositories.count,
                privateRepositoryCount: ownedRepositories.filter(\.isPrivate).count
            )
        }

        return GitHubTokenInspection(
            username: user.login,
            owner: user.login,
            repositoryCount: repositories.count,
            privateRepositoryCount: repositories.filter(\.isPrivate).count
        )
    }

    func fetchSnapshots(
        token: String,
        now: Date = .now,
        scope: GitHubRefreshScope = .allBranches
    ) async throws -> ActivitySnapshotArchive {
        try await fetchSnapshots(tokens: [token], now: now, scope: scope)
    }

    func fetchSnapshots(
        tokens: [String],
        now: Date = .now,
        scope: GitHubRefreshScope = .allBranches
    ) async throws -> ActivitySnapshotArchive {
        guard !tokens.isEmpty else { throw GitHubActivityError.invalidToken }

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let rollingDayStart = now.addingTimeInterval(-24 * 60 * 60)
        let rollingWeekStart = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let rollingMonthStart = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let fetchStart = min(weekStart, rollingWeekStart, monthStart, rollingMonthStart)
        var username: String?
        var authorizedByRepository: [String: AuthorizedRepository] = [:]

        for token in tokens {
            let user: UserResponse = try await get(path: "/user", token: token)
            if let username, username.caseInsensitiveCompare(user.login) != .orderedSame {
                throw GitHubActivityError.tokenAccountMismatch
            }
            username = user.login

            let repositories = try await repositoriesActive(since: fetchStart, token: token)
            for repository in repositories {
                let key = repository.fullName.lowercased()
                if authorizedByRepository[key] == nil {
                    authorizedByRepository[key] = AuthorizedRepository(
                        repository: repository,
                        token: token
                    )
                }
            }
        }

        guard let username else { throw GitHubActivityError.invalidToken }
        let repositories = authorizedByRepository.values.sorted {
            $0.repository.fullName.localizedStandardCompare($1.repository.fullName) == .orderedAscending
        }
        let cachedBranches = scope == .recentBranches ? GitHubBranchCache.read() : [:]
        let scan = try await commitReferences(
            repositories: repositories,
            username: username,
            since: fetchStart,
            until: now,
            scope: scope,
            cachedBranches: cachedBranches
        )
        GitHubBranchCache.merge(scan.activeBranchesByRepository)
        let uniqueReferences = Dictionary(
            scan.references.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        .values
        .sorted {
            if $0.repositoryFullName != $1.repositoryFullName {
                return $0.repositoryFullName < $1.repositoryFullName
            }
            return $0.authoredAt < $1.authoredAt
        }
        let commits = try await commitDetails(references: uniqueReferences)

        let dayStart = calendar.startOfDay(for: now)
        let dailyCommits = commits.filter { $0.authoredAt >= dayStart && $0.authoredAt <= now }
        let weeklyCommits = commits.filter { $0.authoredAt >= weekStart && $0.authoredAt <= now }
        let rollingDailyCommits = commits.filter {
            $0.authoredAt >= rollingDayStart && $0.authoredAt <= now
        }
        let rollingWeeklyCommits = commits.filter {
            $0.authoredAt >= rollingWeekStart && $0.authoredAt <= now
        }
        let monthlyCommits = commits.filter { $0.authoredAt >= monthStart && $0.authoredAt <= now }
        let rollingMonthlyCommits = commits.filter {
            $0.authoredAt >= rollingMonthStart && $0.authoredAt <= now
        }

        return ActivitySnapshotArchive(
            username: username,
            daily: snapshot(
                commits: dailyCommits,
                intervalStart: dayStart,
                intervalEnd: calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now,
                cellCount: 12,
                now: now
            ),
            weekly: snapshot(
                commits: weeklyCommits,
                intervalStart: weekStart,
                intervalEnd: calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now,
                cellCount: 7,
                now: now
            ),
            rollingDaily: snapshot(
                commits: rollingDailyCommits,
                intervalStart: rollingDayStart,
                intervalEnd: now,
                cellCount: 12,
                now: now
            ),
            rollingWeekly: snapshot(
                commits: rollingWeeklyCommits,
                intervalStart: rollingWeekStart,
                intervalEnd: now,
                cellCount: 7,
                now: now
            ),
            monthly: snapshot(
                commits: monthlyCommits,
                intervalStart: monthStart,
                intervalEnd: calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now,
                cellCount: 5,
                now: now
            ),
            rollingMonthly: snapshot(
                commits: rollingMonthlyCommits,
                intervalStart: rollingMonthStart,
                intervalEnd: now,
                cellCount: 5,
                now: now
            ),
            savedAt: now
        )
    }

    private func repositoriesActive(since date: Date, token: String) async throws -> [RepositoryResponse] {
        var active: [RepositoryResponse] = []
        var page = 1

        while true {
            let pageItems: [RepositoryResponse] = try await get(
                path: "/user/repos",
                query: [
                    URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
                    URLQueryItem(name: "visibility", value: "all"),
                    URLQueryItem(name: "sort", value: "pushed"),
                    URLQueryItem(name: "direction", value: "desc"),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ],
                token: token
            )

            active.append(contentsOf: pageItems.filter { ($0.pushedAt ?? .distantPast) >= date })
            if pageItems.count < 100 || pageItems.allSatisfy({ ($0.pushedAt ?? .distantPast) < date }) {
                break
            }
            page += 1
        }

        return active
    }

    private func allRepositories(token: String) async throws -> [RepositoryResponse] {
        var repositories: [RepositoryResponse] = []
        var page = 1

        while true {
            let pageItems: [RepositoryResponse] = try await get(
                path: "/user/repos",
                query: [
                    URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
                    URLQueryItem(name: "visibility", value: "all"),
                    URLQueryItem(name: "sort", value: "full_name"),
                    URLQueryItem(name: "direction", value: "asc"),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ],
                token: token
            )

            repositories.append(contentsOf: pageItems)
            if pageItems.count < 100 { break }
            page += 1
        }

        return repositories
    }

    private func commitReferences(
        repositories: [AuthorizedRepository],
        username: String,
        since: Date,
        until: Date,
        scope: GitHubRefreshScope,
        cachedBranches: [String: Set<String>]
    ) async throws -> CommitReferenceScan {
        var scan = CommitReferenceScan()

        for batch in repositories.batches(of: 4) {
            let values = try await withThrowingTaskGroup(of: RepositoryCommitScan.self) { group in
                for authorized in batch {
                    group.addTask {
                        try await commitReferences(
                            repository: authorized.repository,
                            username: username,
                            since: since,
                            until: until,
                            token: authorized.token,
                            scope: scope,
                            cachedBranches: cachedBranches
                        )
                    }
                }

                var result: [RepositoryCommitScan] = []
                for try await value in group {
                    result.append(value)
                }
                return result
            }

            for value in values {
                scan.references.append(contentsOf: value.references)
                guard !value.activeBranches.isEmpty else { continue }
                scan.activeBranchesByRepository[
                    value.repositoryFullName.lowercased(),
                    default: []
                ].formUnion(value.activeBranches)
            }
        }

        return scan
    }

    private func commitReferences(
        repository: RepositoryResponse,
        username: String,
        since: Date,
        until: Date,
        token: String,
        scope: GitHubRefreshScope,
        cachedBranches: [String: Set<String>]
    ) async throws -> RepositoryCommitScan {
        let branchNames: [String]
        switch scope {
        case .allBranches:
            branchNames = try await branches(repository: repository, token: token).map(\.name)
        case .recentBranches:
            var recent = cachedBranches[repository.fullName.lowercased(), default: []]
            recent.insert(repository.defaultBranch)
            branchNames = recent.sorted()
        }

        var references: [CommitReference] = []
        var activeBranches: Set<String> = []

        for batch in branchNames.batches(of: 6) {
            let values = try await withThrowingTaskGroup(of: BranchCommitScan.self) { group in
                for branch in batch {
                    group.addTask {
                        do {
                            return BranchCommitScan(
                                branch: branch,
                                references: try await commitReferences(
                                    repository: repository,
                                    branch: branch,
                                    username: username,
                                    since: since,
                                    until: until,
                                    token: token
                                )
                            )
                        } catch GitHubActivityError.notFound {
                            return BranchCommitScan(branch: branch, references: [])
                        }
                    }
                }

                var result: [BranchCommitScan] = []
                for try await value in group {
                    result.append(value)
                }
                return result
            }

            for value in values {
                references.append(contentsOf: value.references)
                if !value.references.isEmpty {
                    activeBranches.insert(value.branch)
                }
            }
        }

        return RepositoryCommitScan(
            repositoryFullName: repository.fullName,
            references: references,
            activeBranches: activeBranches
        )
    }

    private func branches(
        repository: RepositoryResponse,
        token: String
    ) async throws -> [BranchResponse] {
        var branches: [BranchResponse] = []
        var page = 1

        while true {
            let pageItems: [BranchResponse] = try await get(
                path: "/repos/\(repository.fullName)/branches",
                query: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ],
                token: token
            )

            branches.append(contentsOf: pageItems)
            if pageItems.count < 100 { break }
            page += 1
        }

        return branches
    }

    private func commitReferences(
        repository: RepositoryResponse,
        branch: String,
        username: String,
        since: Date,
        until: Date,
        token: String
    ) async throws -> [CommitReference] {
        var references: [CommitReference] = []
        var page = 1

        while true {
            let pageItems: [CommitListResponse] = try await get(
                path: "/repos/\(repository.fullName)/commits",
                query: [
                    URLQueryItem(name: "sha", value: branch),
                    URLQueryItem(name: "author", value: username),
                    URLQueryItem(name: "since", value: Self.apiDateFormatter.string(from: since)),
                    URLQueryItem(name: "until", value: Self.apiDateFormatter.string(from: until)),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ],
                token: token
            )

            references.append(contentsOf: pageItems.compactMap { item in
                guard let authoredAt = item.commit.author?.date ?? item.commit.committer?.date else { return nil }
                return CommitReference(
                    repositoryName: repository.name,
                    repositoryFullName: repository.fullName,
                    sha: item.sha,
                    authoredAt: authoredAt,
                    token: token
                )
            })

            if pageItems.count < 100 { break }
            page += 1
        }

        return references
    }

    private func commitDetails(references: [CommitReference]) async throws -> [CommitActivity] {
        var activities: [CommitActivity] = []

        for batch in references.batches(of: 8) {
            let values = try await withThrowingTaskGroup(of: CommitActivity.self) { group in
                for reference in batch {
                    group.addTask {
                        let detail: CommitDetailResponse = try await get(
                            path: "/repos/\(reference.repositoryFullName)/commits/\(reference.sha)",
                            token: reference.token
                        )
                        return CommitActivity(
                            repositoryName: reference.repositoryName,
                            repositoryFullName: reference.repositoryFullName,
                            authoredAt: reference.authoredAt,
                            additions: detail.stats.additions,
                            deletions: detail.stats.deletions
                        )
                    }
                }

                var result: [CommitActivity] = []
                for try await value in group {
                    result.append(value)
                }
                return result
            }
            activities.append(contentsOf: values)
        }

        return activities
    }

    private func snapshot(
        commits: [CommitActivity],
        intervalStart: Date,
        intervalEnd: Date,
        cellCount: Int,
        now: Date
    ) -> ActivitySnapshot {
        let groupedByName = Dictionary(grouping: commits, by: \CommitActivity.repositoryName)
        let duplicateNames = Set(groupedByName.compactMap { name, values in
            Set(values.map(\CommitActivity.repositoryFullName)).count > 1 ? name : nil
        })
        var repositoryTotals: [String: RepositoryAccumulator] = [:]
        var cells = Array(repeating: CellAccumulator(), count: cellCount)
        let intervalDuration = max(intervalEnd.timeIntervalSince(intervalStart), 1)

        for commit in commits {
            let displayName = duplicateNames.contains(commit.repositoryName)
                ? commit.repositoryFullName
                : commit.repositoryName
            repositoryTotals[displayName, default: RepositoryAccumulator()].add(commit)

            let progress = commit.authoredAt.timeIntervalSince(intervalStart) / intervalDuration
            let index = min(max(Int(progress * Double(cellCount)), 0), cellCount - 1)
            cells[index].additions += commit.additions
            cells[index].deletions += commit.deletions
        }

        let repositories = repositoryTotals.map { name, total in
            RepositoryActivity(
                name: name,
                commits: total.commits,
                additions: total.additions,
                deletions: total.deletions
            )
        }
        let additions = commits.reduce(0) { $0 + $1.additions }
        let deletions = commits.reduce(0) { $0 + $1.deletions }

        return ActivitySnapshot(
            additions: additions,
            deletions: deletions,
            commits: commits.count,
            repositories: repositories,
            activity: cells.enumerated().map {
                ActivityCell(id: $0.offset, additions: $0.element.additions, deletions: $0.element.deletions)
            },
            updatedAt: now,
            state: commits.isEmpty ? .noActivity : .loaded
        )
    }

    private func get<Response: Decodable>(
        path: String,
        query: [URLQueryItem] = [],
        token: String
    ) async throws -> Response {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw GitHubActivityError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("gitlines/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubActivityError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            return try Self.decoder.decode(Response.self, from: data)
        case 401:
            throw GitHubActivityError.invalidToken
        case 403:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                let resetAt = http.value(forHTTPHeaderField: "X-RateLimit-Reset")
                    .flatMap(TimeInterval.init)
                    .map(Date.init(timeIntervalSince1970:))
                throw GitHubActivityError.rateLimited(resetAt)
            }
            throw GitHubActivityError.accessDenied
        case 404:
            throw GitHubActivityError.notFound
        default:
            let body = try? Self.decoder.decode(APIErrorResponse.self, from: data)
            throw GitHubActivityError.api(body?.message ?? "GitHub returned HTTP \(http.statusCode).")
        }
    }

    private static let apiDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid GitHub date."
            )
        }
        return decoder
    }()
}

private struct UserResponse: Decodable, Sendable {
    let login: String
}

private struct RepositoryResponse: Decodable, Sendable {
    let name: String
    let fullName: String
    let pushedAt: Date?
    let defaultBranch: String
    let isPrivate: Bool

    var ownerName: String {
        fullName.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case pushedAt = "pushed_at"
        case defaultBranch = "default_branch"
        case isPrivate = "private"
    }
}

private struct AuthorizedRepository: Sendable {
    let repository: RepositoryResponse
    let token: String
}

private struct BranchResponse: Decodable, Sendable {
    let name: String
}

private struct CommitListResponse: Decodable, Sendable {
    let sha: String
    let commit: CommitMetadata
}

private struct CommitMetadata: Decodable, Sendable {
    let author: GitActorDate?
    let committer: GitActorDate?
}

private struct GitActorDate: Decodable, Sendable {
    let date: Date
}

private struct CommitDetailResponse: Decodable, Sendable {
    let stats: CommitStats
}

private struct CommitStats: Decodable, Sendable {
    let additions: Int
    let deletions: Int
}

private struct APIErrorResponse: Decodable, Sendable {
    let message: String
}

private struct CommitReference: Sendable {
    let repositoryName: String
    let repositoryFullName: String
    let sha: String
    let authoredAt: Date
    let token: String

    var id: String { "\(repositoryFullName.lowercased()):\(sha.lowercased())" }
}

private struct BranchCommitScan: Sendable {
    let branch: String
    let references: [CommitReference]
}

private struct RepositoryCommitScan: Sendable {
    let repositoryFullName: String
    let references: [CommitReference]
    let activeBranches: Set<String>
}

private struct CommitReferenceScan: Sendable {
    var references: [CommitReference] = []
    var activeBranchesByRepository: [String: Set<String>] = [:]
}

private struct CommitActivity: Sendable {
    let repositoryName: String
    let repositoryFullName: String
    let authoredAt: Date
    let additions: Int
    let deletions: Int
}

private struct RepositoryAccumulator {
    var commits = 0
    var additions = 0
    var deletions = 0

    mutating func add(_ commit: CommitActivity) {
        commits += 1
        additions += commit.additions
        deletions += commit.deletions
    }
}

private struct CellAccumulator {
    var additions = 0
    var deletions = 0
}

private struct GitHubBranchCacheArchive: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let branchesByRepository: [String: [String]]

    init(branchesByRepository: [String: [String]]) {
        schemaVersion = Self.currentSchemaVersion
        self.branchesByRepository = branchesByRepository
    }
}

enum GitHubBranchCache {
    private static let key = "github.recentActivityBranches"

    static func read() -> [String: Set<String>] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let archive = try? JSONDecoder().decode(GitHubBranchCacheArchive.self, from: data),
            archive.schemaVersion == GitHubBranchCacheArchive.currentSchemaVersion
        else {
            return [:]
        }

        return archive.branchesByRepository.mapValues(Set.init)
    }

    static func merge(_ discovered: [String: Set<String>]) {
        guard !discovered.isEmpty else { return }

        var cached = read()
        for (repository, branches) in discovered {
            cached[repository, default: []].formUnion(branches)
        }

        let archive = GitHubBranchCacheArchive(
            branchesByRepository: cached.mapValues { $0.sorted() }
        )
        guard let data = try? JSONEncoder().encode(archive) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func remove() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private extension Array {
    func batches(of size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
