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

    /// Runs an executable at the given path with arguments and an
    /// optional custom environment, capturing stdout and stderr.
    ///
    /// The command is executed through `/bin/zsh -l -c` so that the
    /// user's login shell profile is sourced and `PATH` is available.
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

        // Build the full shell command string.
        let fullCommand = ([command] + arguments)
            .map { arg in
                // Escape single quotes inside arguments for safe shell expansion.
                let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
                return "'\(escaped)'"
            }
            .joined(separator: " ")

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", fullCommand]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Merge environment.
        var env = environment ?? ProcessInfo.processInfo.environment
        env["PATH"] = enrichedPath()
        process.environment = env

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

    // MARK: - Run Shim

    /// Convenience method to run a codex-shim subcommand.
    ///
    /// Automatically injects `--port` and passes additional arguments
    /// to the shim binary.
    ///
    /// - Parameters:
    ///   - subcommand: The shim subcommand (e.g. `"status"`, `"start"`).
    ///   - arguments: Extra arguments appended after the subcommand.
    ///   - shimPath: Path or command name for the shim binary.
    ///   - port: The port the shim listens on.
    /// - Returns: A ``ProcessResult`` with exit code and captured output.
    static func runShim(
        _ subcommand: String,
        arguments: [String] = [],
        shimPath: String = "codex-shim",
        port: Int = 8765
    ) async throws -> ProcessResult {
        var args = ["--port", "\(port)", subcommand]
        args.append(contentsOf: arguments)
        return try await run(shimPath, arguments: args)
    }

    // MARK: - Run Elevated

    /// Runs a command with elevated administrator privileges using AppleScript's `do shell script`.
    ///
    /// This will trigger the standard macOS Touch ID / Password authentication dialog.
    static func runElevated(_ command: String, arguments: [String] = []) async throws -> ProcessResult {
        let escapedArgs = arguments.map { arg in
            let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }.joined(separator: " ")
        
        let fullCmd = "\(command) \(escapedArgs)"
        
        // Escape the command for AppleScript string
        let appleScriptCmd = "do shell script \"\(fullCmd.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        
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
