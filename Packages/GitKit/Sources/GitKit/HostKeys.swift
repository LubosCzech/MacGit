import Foundation

/// SSH server, ke kterému se git připojuje.
public struct SSHEndpoint: Hashable, Sendable {
    public var host: String
    public var port: Int

    public init(host: String, port: Int = 22) {
        self.host = host
        self.port = port
    }

    /// Zápis hostitele v known_hosts: `host` nebo `[host]:port`.
    public var knownHostsName: String { port == 22 ? host : "[\(host)]:\(port)" }

    /// `git@host:path`, `ssh://git@host:2222/path`; pro HTTPS vrací nil.
    public static func from(remote: String) -> SSHEndpoint? {
        let value = remote.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("ssh://") || value.hasPrefix("git+ssh://") {
            guard let components = URLComponents(string: value), let host = components.host else { return nil }
            return SSHEndpoint(host: host, port: components.port ?? 22)
        }
        guard !value.contains("://"), let colon = value.firstIndex(of: ":") else { return nil }
        var host = String(value[..<colon])
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        return host.isEmpty ? nil : SSHEndpoint(host: host)
    }
}

public struct HostKey: Identifiable, Hashable, Sendable {
    /// Řádek pro known_hosts (`host typ klíč`).
    public var line: String
    public var type: String
    public var fingerprint: String
    public var bits: String
    public var id: String { line }
}

public enum HostKeyTrust {
    public enum Problem: Sendable, Equatable {
        /// Server ještě není v known_hosts.
        case unknown
        /// Server je známý, ale nabízí jiný klíč – možný útok nebo přeinstalovaný server.
        case changed
    }

    public static func problem(in error: Error) -> Problem? {
        guard let error = error as? GitError else { return nil }
        if error.message.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") { return .changed }
        if error.message.contains("Host key verification failed") || error.message.contains("No ED25519 host key is known") {
            return .unknown
        }
        return nil
    }

    public static var knownHostsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/known_hosts")
    }

    /// Stáhne veřejné klíče serveru a spočítá jejich otisky (SHA256).
    public static func scan(_ endpoint: SSHEndpoint) async throws -> [HostKey] {
        let scan = try await ProcessRunner.run("/usr/bin/ssh-keyscan", ["-T", "8", "-p", String(endpoint.port), endpoint.host], timeout: 20)
        let lines = scan.output.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.isEmpty }
        guard !lines.isEmpty else {
            throw GitError(arguments: ["ssh-keyscan"], status: scan.status, message: "Server \(endpoint.host) neodpověděl na SSH (port \(endpoint.port)).")
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("macgit-hostkeys-\(UUID().uuidString)")
        try lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let fingerprints = try await ProcessRunner.run("/usr/bin/ssh-keygen", ["-lf", file.path], timeout: 10)
        let parsed = fingerprints.output.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }

        return lines.enumerated().compactMap { index, line in
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 3 else { return nil }
            // ssh-keygen vypisuje: <bits> <SHA256:…> <host> (<TYP>)
            let info = index < parsed.count ? parsed[index] : []
            let type = info.last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "()")) } ?? parts[1]
            return HostKey(line: line, type: type, fingerprint: info.count > 1 ? info[1] : "?", bits: info.first ?? "")
        }
        .sorted { order($0.type) < order($1.type) }
    }

    private static func order(_ type: String) -> Int {
        switch type.uppercased() {
        case "ED25519": 0
        case "ECDSA": 1
        default: 2
        }
    }

    /// Přidá klíče serveru do ~/.ssh/known_hosts.
    public static func trust(_ keys: [HostKey], knownHosts: URL = knownHostsURL) throws {
        let directory = knownHosts.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var existing = (try? String(contentsOf: knownHosts, encoding: .utf8)) ?? ""
        let newLines = keys.map(\.line).filter { !existing.contains($0) }
        guard !newLines.isEmpty else { return }
        if !existing.isEmpty && !existing.hasSuffix("\n") { existing += "\n" }
        existing += newLines.joined(separator: "\n") + "\n"
        try existing.write(to: knownHosts, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: knownHosts.path)
    }
}
