import Foundation

public enum HostingKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case github, gitlab
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        }
    }

    public var defaultHost: String {
        switch self {
        case .github: "github.com"
        case .gitlab: "gitlab.com"
        }
    }

    /// Uživatelské jméno pro HTTPS přihlášení tokenem.
    public func httpsUsername(for login: String) -> String {
        switch self {
        case .github: login
        case .gitlab: "oauth2"
        }
    }
}

public struct HostingUser: Sendable, Equatable {
    public var login: String
    public var name: String?
    public var email: String?
    public var avatarURL: URL?
}

public struct HostedRepository: Identifiable, Hashable, Sendable {
    public var id: String
    public var fullName: String
    public var description: String?
    public var httpsURL: String
    public var sshURL: String
    public var isPrivate: Bool
    public var updatedAt: Date?
    public var webURL: URL?
}

public struct HostingError: LocalizedError, Sendable {
    public var status: Int
    public var message: String
    public var errorDescription: String? {
        switch status {
        case 401: "Token je neplatný nebo vypršel (401)."
        case 403: "Token nemá dostatečná oprávnění (403). \(message)"
        default: "Chyba API \(status): \(message)"
        }
    }
}

public struct HostingClient: Sendable {
    public var kind: HostingKind
    public var host: String
    public var token: String
    var session: URLSession = .shared

    public init(kind: HostingKind, host: String, token: String) {
        self.kind = kind
        self.host = host.isEmpty ? kind.defaultHost : host
        self.token = token
    }

    var apiBase: URL {
        switch kind {
        case .github:
            host == "github.com" ? URL(string: "https://api.github.com")! : URL(string: "https://\(host)/api/v3")!
        case .gitlab:
            URL(string: "https://\(host)/api/v4")!
        }
    }

    private func request(_ path: String, method: String = "GET", body: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: apiBase.absoluteString + path)!)
        request.httpMethod = method
        switch kind {
        case .github:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        case .gitlab:
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"].map { "\($0)" }
            throw HostingError(status: status, message: message ?? String(decoding: data.prefix(300), as: UTF8.self))
        }
        return data
    }

    public func currentUser() async throws -> HostingUser {
        let data = try await request("/user")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        switch kind {
        case .github:
            return HostingUser(
                login: json["login"] as? String ?? "",
                name: json["name"] as? String,
                email: json["email"] as? String,
                avatarURL: (json["avatar_url"] as? String).flatMap(URL.init(string:))
            )
        case .gitlab:
            return HostingUser(
                login: json["username"] as? String ?? "",
                name: json["name"] as? String,
                email: (json["commit_email"] as? String) ?? (json["public_email"] as? String) ?? (json["email"] as? String),
                avatarURL: (json["avatar_url"] as? String).flatMap(URL.init(string:))
            )
        }
    }

    public func repositories(maxPages: Int = 10) async throws -> [HostedRepository] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func date(_ value: Any?) -> Date? {
            guard let string = value as? String else { return nil }
            return iso.date(from: string) ?? isoPlain.date(from: string)
        }

        var all: [HostedRepository] = []
        for page in 1...maxPages {
            let path = switch kind {
            case .github: "/user/repos?per_page=100&sort=updated&page=\(page)"
            case .gitlab: "/projects?membership=true&simple=true&per_page=100&order_by=last_activity_at&page=\(page)"
            }
            let data = try await request(path)
            let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            all += items.map { item in
                switch kind {
                case .github:
                    HostedRepository(
                        id: "\(item["id"] ?? "")",
                        fullName: item["full_name"] as? String ?? "",
                        description: item["description"] as? String,
                        httpsURL: item["clone_url"] as? String ?? "",
                        sshURL: item["ssh_url"] as? String ?? "",
                        isPrivate: item["private"] as? Bool ?? false,
                        updatedAt: date(item["pushed_at"] ?? item["updated_at"]),
                        webURL: (item["html_url"] as? String).flatMap(URL.init(string:))
                    )
                case .gitlab:
                    HostedRepository(
                        id: "\(item["id"] ?? "")",
                        fullName: item["path_with_namespace"] as? String ?? "",
                        description: item["description"] as? String,
                        httpsURL: item["http_url_to_repo"] as? String ?? "",
                        sshURL: item["ssh_url_to_repo"] as? String ?? "",
                        isPrivate: (item["visibility"] as? String) != "public",
                        updatedAt: date(item["last_activity_at"]),
                        webURL: (item["web_url"] as? String).flatMap(URL.init(string:))
                    )
                }
            }
            if items.count < 100 { break }
        }
        return all
    }

    public enum SSHKeyPurpose: Sendable {
        /// Přihlašování (push/pull).
        case authentication
        /// Ověřování podpisů commitů („Verified“ na GitHubu).
        case signing
    }

    /// Nahraje veřejný SSH klíč k účtu.
    /// GitHub eviduje přihlašovací a podpisové klíče zvlášť, GitLab umí oboje jedním klíčem.
    public func uploadSSHKey(title: String, publicKey: String, purpose: SSHKeyPurpose = .authentication) async throws {
        let key = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .github:
            let path = purpose == .signing ? "/user/ssh_signing_keys" : "/user/keys"
            _ = try await request(path, method: "POST", body: ["title": title, "key": key])
        case .gitlab:
            _ = try await request("/user/keys", method: "POST", body: ["title": title, "key": key, "usage_type": "auth_and_signing"])
        }
    }

    /// URL pro vytvoření pull/merge requestu z větve ve webovém rozhraní.
    public static func newPullRequestURL(remoteURL: String, branch: String, kind: HostingKind) -> URL? {
        guard let (host, path) = parseRemote(remoteURL) else { return nil }
        let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch
        switch kind {
        case .github: return URL(string: "https://\(host)/\(path)/pull/new/\(encodedBranch)")
        case .gitlab: return URL(string: "https://\(host)/\(path)/-/merge_requests/new?merge_request[source_branch]=\(encodedBranch)")
        }
    }

    /// `git@github.com:owner/repo.git` / `https://github.com/owner/repo.git` → (host, owner/repo)
    public static func parseRemote(_ remote: String) -> (host: String, path: String)? {
        var value = remote.trimmingCharacters(in: .whitespaces)
        if value.hasSuffix(".git") { value.removeLast(4) }
        if let components = URLComponents(string: value), let host = components.host, components.scheme != nil {
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return path.isEmpty ? nil : (host, path)
        }
        // scp-like syntaxe user@host:path
        guard let colon = value.firstIndex(of: ":") else { return nil }
        var hostPart = String(value[..<colon])
        if let at = hostPart.firstIndex(of: "@") { hostPart = String(hostPart[hostPart.index(after: at)...]) }
        let path = String(value[value.index(after: colon)...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? nil : (hostPart, path)
    }
}
