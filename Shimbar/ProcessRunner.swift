import Foundation

// MARK: - ProcessResult

/// The result of a completed shell process.
struct ProcessResult {
    /// The process exit code (`0` typically indicates success).
    let exitCode: Int32

    /// The captured standard output.
    let stdout: String

    /// The captured standard error.
    let stderr: String

    /// Whether the process exited successfully (exit code `0`).
    var succeeded: Bool { exitCode == 0 }
}

// MARK: - ProcessRunner

/// An actor that provides async utilities for running shell commands
/// and interacting with the codex-shim CLI.
///
/// All methods are `static` for convenience. The actor isolation
/// ensures thread-safe access when needed.
actor ProcessRunner {

    // MARK: - Common PATH Directories

    /// Additional directories appended to `PATH` so that common
    /// install locations are searched even when the app is launched
    /// outside a login shell.
    private static var extraPathDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(home)/.local/bin",
            "\(home)/codex-shim/bin",
        ]
    }

    /// Builds a `PATH` string that merges the current environment's
    /// `PATH` with ``extraPathDirectories``.
    private static func enrichedPath() -> String {
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let extras = extraPathDirectories.joined(separator: ":")
        return "\(existing):\(extras)"
    }

    // MARK: - Run Command

    /// Resolves the absolute URL for a command or executable, searching enriched PATH if it's a bare command name.
    private static func resolveExecutableURL(_ command: String) -> URL? {
        if command.hasPrefix("/") || command.hasPrefix(".") {
            let url = URL(fileURLWithPath: command)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        
        let pathEnv = enrichedPath()
        let dirs = pathEnv.components(separatedBy: ":")
        for dir in dirs {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    /// Runs an executable at the given path with arguments and an
    /// optional custom environment, capturing stdout and stderr.
    ///
    /// It attempts direct binary execution if the executable can be resolved
    /// in the enriched PATH; otherwise, it falls back to zsh shell execution.
    ///
    /// - Parameters:
    ///   - command: The command or path to the executable.
    ///   - arguments: Command-line arguments passed to the executable.
    ///   - environment: Optional environment variables. When `nil`,
    ///     the current process environment (with enriched PATH) is used.
    /// - Returns: A ``ProcessResult`` with exit code and captured output.
    /// - Throws: Any error raised by `Process` (e.g. launch failure).
    static func run(
        _ command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Merge environment.
        var env = environment ?? ProcessInfo.processInfo.environment
        env["PATH"] = enrichedPath()
        process.environment = env

        // Attempt direct binary execution if executable is resolved, bypassing shell overhead.
        if let resolvedURL = resolveExecutableURL(command) {
            process.executableURL = resolvedURL
            process.arguments = arguments
        } else {
            // Fallback: run via zsh (without -l to avoid sourcing heavy interactive profiles)
            let fullCommand = ([command] + arguments)
                .map { arg in
                    // Escape single quotes inside arguments for safe shell expansion.
                    let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
                    return "'\(escaped)'"
                }
                .joined(separator: " ")

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", fullCommand]
        }

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let result = ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Run Elevated

    /// Runs a command with elevated administrator privileges using AppleScript's `do shell script`.
    ///
    /// This will trigger the standard macOS Touch ID / Password authentication dialog.
    static func runElevated(_ command: String, arguments: [String] = []) async throws -> ProcessResult {
        let escapedArgs = arguments.map { arg in
            let escaped = arg
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }.joined(separator: " ")
        
        let fullCmd = "\(command) \(escapedArgs)"
        
        let appleScriptSafe = fullCmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptCmd = "do shell script \"\(appleScriptSafe)\" with administrator privileges"
        
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScriptCmd]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                
                let result = ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                )
                continuation.resume(returning: result)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Which

    /// Locates the full path to an executable by searching `PATH`.
    ///
    /// - Parameter command: The name of the command to find.
    /// - Returns: The absolute path to the executable, or `nil` if
    ///   not found.
    static func which(_ command: String) async -> String? {
        guard let result = try? await run("/usr/bin/which", arguments: [command]),
              result.succeeded,
              !result.stdout.isEmpty
        else {
            return nil
        }
        return result.stdout
    }
}
