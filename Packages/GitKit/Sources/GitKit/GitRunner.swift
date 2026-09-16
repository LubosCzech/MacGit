import Foundation

public struct GitResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: String

    public var output: String { String(decoding: stdout, as: UTF8.self) }
}

public struct GitError: LocalizedError, Sendable {
    public let arguments: [String]
    public let status: Int32
    public let message: String

    public init(arguments: [String], status: Int32, message: String) {
        self.arguments = arguments
        self.status = status
        self.message = message
    }

    public var errorDescription: String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "git \(arguments.first ?? "") skončil s kódem \(status)" : trimmed
    }
}

/// Spouští systémový `git` jako podproces.
public struct GitRunner: Sendable {
    public var gitPath: String

    public init(gitPath: String? = nil) {
        self.gitPath = gitPath ?? GitRunner.locateGit()
    }

    public static func locateGit() -> String {
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/git"
    }

    /// Prostředí pro GUI aplikaci – doplní PATH o Homebrew (gpg, git-lfs, pinentry).
    static func baseEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let current = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        env["PATH"] = (current + extra.filter { !current.contains($0) }).joined(separator: ":")
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["LC_ALL"] = "en_US.UTF-8"
        env["GIT_EDITOR"] = "true"
        return env
    }

    @discardableResult
    public func run(
        _ arguments: [String],
        in directory: URL?,
        context: GitContext = .none,
        input: Data? = nil,
        allowFailure: Bool = false
    ) async throws -> GitResult {
        let fullArgs = ["-c", "core.quotepath=false", "-c", "color.ui=false"] + context.configArguments + arguments
        var env = GitRunner.baseEnvironment()
        env.merge(context.environment) { _, new in new }
        let gitPath = self.gitPath, environment = env

        let result: GitResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gitPath)
                process.arguments = fullArgs
                process.environment = environment
                if let directory { process.currentDirectoryURL = directory }

                let outPipe = Pipe(), errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                let inPipe = input.map { _ in Pipe() }
                process.standardInput = inPipe ?? FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                if let inPipe, let input {
                    // Zápis mimo čtecí vlákno, aby se velký patch nezablokoval o plný stdout.
                    DispatchQueue.global().async {
                        inPipe.fileHandleForWriting.write(input)
                        try? inPipe.fileHandleForWriting.close()
                    }
                }

                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: GitResult(
                    status: process.terminationStatus,
                    stdout: out,
                    stderr: String(decoding: errBox.data, as: UTF8.self)
                ))
            }
        }

        if result.status != 0 && !allowFailure {
            let message = result.stderr.isEmpty ? result.output : result.stderr
            throw GitError(arguments: arguments, status: result.status, message: message)
        }
        return result
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
