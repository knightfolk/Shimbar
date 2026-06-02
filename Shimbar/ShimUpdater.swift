// ShimUpdater.swift
// Shimbar
//
// Manages checking the upstream codex-shim repository for updates
// and performing git pull + pip reinstall when requested.

import Foundation
import Observation

// MARK: - ShimUpdater

/// Checks the local codex-shim git repository against its upstream remote
/// and orchestrates one-click updates (git pull + pip install).
///
/// The updater resolves the git repo root by walking up from the discovered
/// shim binary path (e.g. `~/codex-shim/bin/codex-shim` → `~/codex-shim`).
/// It compares the local `HEAD` commit hash against the remote via
/// `git ls-remote` (no fetch required) and surfaces the result to the UI.
@MainActor
@Observable
final class ShimUpdater {

    // MARK: - Singleton

    static let shared = ShimUpdater()

    // MARK: - Published State

    /// Whether the remote has commits not present locally.
    var updateAvailable: Bool = false

    /// The short hash of the local HEAD commit.
    var localCommitHash: String?

    /// The short hash of the remote HEAD commit.
    var remoteCommitHash: String?

    /// Whether an update check is currently in flight.
    var isChecking: Bool = false

    /// Whether an update installation is currently in flight.
    var isUpdating: Bool = false

    /// Timestamp of the last successful update check.
    var lastCheckDate: Date?

    /// Human-readable error from the last check or update attempt.
    var lastUpdateError: String?

    /// Step-by-step log of the most recent update operation.
    var updateLog: [String] = []

    /// Whether the user has dismissed the update banner for this session.
    var isDismissed: Bool = false

    // MARK: - Private State

    /// Resolved path to the git repository root containing the codex-shim source.
    private var repoPath: String?

    // MARK: - Initialization

    private init() {}

    // MARK: - Repo Resolution

    /// Resolves the git repository root from the shim binary path.
    ///
    /// Walks up the directory tree from the binary location looking for a
    /// `.git` directory. For example:
    /// - `~/codex-shim/bin/codex-shim` → `~/codex-shim`
    /// - `~/Projects/codex-shim/bin/codex-shim` → `~/Projects/codex-shim`
    ///
    /// - Parameter shimPath: The filesystem path to the codex-shim binary.
    /// - Returns: The path to the repository root, or `nil` if not found.
    func resolveRepoPath(from shimPath: String) -> String? {
        let fm = FileManager.default
        var current = URL(fileURLWithPath: shimPath).deletingLastPathComponent()

        // Walk up at most 6 levels to find .git
        for _ in 0..<6 {
            let gitDir = current.appendingPathComponent(".git")
            if fm.fileExists(atPath: gitDir.path) {
                return current.path
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break } // reached root
            current = parent
        }

        // Fallback: Check common local git clone locations
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/codex-shim",
            "\(home)/Projects/codex-shim",
            "\(home)/Developer/codex-shim"
        ]
        for candidate in candidates {
            let gitDir = URL(fileURLWithPath: candidate).appendingPathComponent(".git")
            if fm.fileExists(atPath: gitDir.path) {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Check for Updates

    /// Compares the local HEAD against the remote HEAD to determine
    /// if updates are available.
    ///
    /// This is a lightweight operation that uses `git ls-remote` to query
    /// the remote without downloading objects.
    ///
    /// - Parameter shimPath: The filesystem path to the codex-shim binary.
    func checkForUpdate(shimPath: String) async {
        guard !isChecking else { return }
        isChecking = true
        lastUpdateError = nil
        defer { isChecking = false }

        // 1. Resolve the repo path
        guard let repo = resolveRepoPath(from: shimPath) else {
            lastUpdateError = "Could not locate the codex-shim git repository from binary path."
            updateAvailable = false
            return
        }
        repoPath = repo

        // 2. Get the local HEAD hash
        do {
            let localResult = try await ProcessRunner.run(
                "/usr/bin/git",
                arguments: ["-C", repo, "rev-parse", "HEAD"]
            )
            guard localResult.succeeded, !localResult.stdout.isEmpty else {
                lastUpdateError = "Failed to read local git HEAD: \(localResult.stderr)"
                return
            }
            let fullHash = localResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            localCommitHash = String(fullHash.prefix(7))

            // 3. Get the remote HEAD hash via ls-remote (no fetch needed)
            let remoteResult = try await ProcessRunner.run(
                "/usr/bin/git",
                arguments: ["-C", repo, "ls-remote", "origin", "HEAD"]
            )
            guard remoteResult.succeeded, !remoteResult.stdout.isEmpty else {
                lastUpdateError = "Failed to query remote: \(remoteResult.stderr)"
                return
            }

            // ls-remote output format: "<hash>\tHEAD"
            let remoteLine = remoteResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let remoteFullHash = remoteLine.components(separatedBy: .whitespaces).first ?? ""
            remoteCommitHash = String(remoteFullHash.prefix(7))

            // 4. Compare
            var update = false
            if !remoteFullHash.isEmpty && fullHash != remoteFullHash {
                // Check if the remote commit is already an ancestor of our local HEAD.
                // If it is, we don't need to update (local is ahead of remote).
                // First verify the remote commit object exists in our local repository.
                let objectExists = try? await ProcessRunner.run(
                    "/usr/bin/git",
                    arguments: ["-C", repo, "cat-file", "-e", remoteFullHash]
                )
                if let exists = objectExists?.succeeded, exists {
                    let isAncestor = try? await ProcessRunner.run(
                        "/usr/bin/git",
                        arguments: ["-C", repo, "merge-base", "--is-ancestor", remoteFullHash, "HEAD"]
                    )
                    update = !(isAncestor?.succeeded ?? false)
                } else {
                    update = true
                }
            }
            updateAvailable = update
            lastCheckDate = Date()

        } catch {
            lastUpdateError = "Update check failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Perform Update

    /// Pulls the latest changes from upstream and reinstalls the package.
    ///
    /// Steps:
    /// 1. `git pull --ff-only` in the repo directory
    /// 2. `pip3 install --user -e .` to rebuild in editable mode
    /// 3. Restart the shim daemon if it was running
    ///
    /// The ``updateLog`` is populated with step-by-step progress.
    ///
    /// - Parameter shimManager: The shared ShimManager, used to restart the daemon.
    func performUpdate(shimManager: ShimManager) async {
        guard let repo = repoPath else {
            lastUpdateError = "No repository path resolved. Run a check first."
            return
        }
        guard !isUpdating else { return }

        isUpdating = true
        lastUpdateError = nil
        updateLog = []
        defer { isUpdating = false }

        let wasRunning = shimManager.status == .running

        // Step 1: git pull
        appendLog("→ Running git pull --rebase --autostash in \(repo)...")
        do {
            let pullResult = try await ProcessRunner.run(
                "/usr/bin/git",
                arguments: ["-C", repo, "pull", "--rebase", "--autostash"]
            )
            appendLog("  stdout: \(pullResult.stdout)")
            if !pullResult.stderr.isEmpty {
                appendLog("  stderr: \(pullResult.stderr)")
            }
            if !pullResult.succeeded {
                lastUpdateError = "git pull failed (exit \(pullResult.exitCode)): \(pullResult.stderr)"
                appendLog("✗ git pull failed")
                return
            }
            appendLog("✓ git pull succeeded")
        } catch {
            lastUpdateError = "git pull error: \(error.localizedDescription)"
            appendLog("✗ git pull error: \(error.localizedDescription)")
            return
        }

        // Step 2: Reinstall package
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let uvPath = "\(homeDir)/.local/bin/uv"
        let isUvTool = FileManager.default.fileExists(atPath: "\(homeDir)/.local/share/uv/tools/codex-shim")
        
        var installationSucceeded = false
        
        // Strategy A: If it's a uv-managed tool installation, use uv tool install natively
        if FileManager.default.fileExists(atPath: uvPath) && isUvTool {
            appendLog("→ Detected uv-managed codex-shim installation.")
            appendLog("→ Running uv tool install --editable \(repo) --force ...")
            do {
                let uvResult = try await ProcessRunner.run(
                    uvPath,
                    arguments: ["tool", "install", "--editable", repo, "--force"]
                )
                appendLog("  stdout: \(uvResult.stdout.suffix(300))")
                if !uvResult.stderr.isEmpty {
                    appendLog("  stderr: \(uvResult.stderr.suffix(300))")
                }
                if uvResult.succeeded {
                    appendLog("✓ uv tool upgrade succeeded")
                    installationSucceeded = true
                } else {
                    appendLog("⚠ uv tool upgrade failed, falling back to python pip...")
                }
            } catch {
                appendLog("⚠ uv tool upgrade error: \(error.localizedDescription), falling back...")
            }
        }
        
        // Strategy B: If uv tool is not used or failed, try finding a verified Python 3.11+ compatible environment
        if !installationSucceeded {
            appendLog("→ Discovering a Python 3.11+ compatible environment...")
            var pythonPath = "python3"
            var useFallback = true
            
            if let compatiblePython = await findCompatiblePython() {
                pythonPath = compatiblePython
                useFallback = false
                appendLog("✓ Found compatible Python 3.11+ at: \(pythonPath)")
            } else {
                appendLog("⚠ No verified Python 3.11+ found. Falling back to system pip3...")
            }
            
            if useFallback {
                appendLog("→ Running pip3 install --user -e . ...")
                do {
                    let pip3Path = await ProcessRunner.which("pip3")
                    let pip3 = pip3Path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "pip3"

                    let pipResult = try await ProcessRunner.run(
                        pip3,
                        arguments: ["install", "--user", "-e", repo]
                    )
                    appendLog("  stdout: \(pipResult.stdout.suffix(200))")
                    if !pipResult.stderr.isEmpty {
                        appendLog("  stderr: \(pipResult.stderr.suffix(200))")
                    }
                    if !pipResult.succeeded {
                        lastUpdateError = "pip3 install failed (exit \(pipResult.exitCode)): \(pipResult.stderr.prefix(200))"
                        appendLog("✗ pip3 install failed")
                        return
                    }
                    appendLog("✓ pip3 install succeeded")
                    installationSucceeded = true
                } catch {
                    lastUpdateError = "pip3 install error: \(error.localizedDescription)"
                    appendLog("✗ pip3 install error: \(error.localizedDescription)")
                    return
                }
            } else {
                appendLog("→ Running \(pythonPath) -m pip install --user -e . ...")
                do {
                    let pipResult = try await ProcessRunner.run(
                        pythonPath,
                        arguments: ["-m", "pip", "install", "--user", "-e", repo]
                    )
                    appendLog("  stdout: \(pipResult.stdout.suffix(200))")
                    if !pipResult.stderr.isEmpty {
                        appendLog("  stderr: \(pipResult.stderr.suffix(200))")
                    }
                    if !pipResult.succeeded {
                        lastUpdateError = "pip install failed (exit \(pipResult.exitCode)): \(pipResult.stderr.prefix(200))"
                        appendLog("✗ pip install failed")
                        return
                    }
                    appendLog("✓ pip install succeeded")
                    installationSucceeded = true
                } catch {
                    lastUpdateError = "pip install error: \(error.localizedDescription)"
                    appendLog("✗ pip install error: \(error.localizedDescription)")
                    return
                }
            }
        }

        // Step 3: Update local commit hash
        appendLog("→ Refreshing local version info...")
        do {
            let headResult = try await ProcessRunner.run(
                "/usr/bin/git",
                arguments: ["-C", repo, "rev-parse", "HEAD"]
            )
            if headResult.succeeded {
                let newHash = headResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                localCommitHash = String(newHash.prefix(7))
            }
        } catch {
            // Non-fatal — the update itself already succeeded
            appendLog("  (could not refresh commit hash: \(error.localizedDescription))")
        }
        updateAvailable = false
        isDismissed = false

        // Step 4: Restart the daemon if it was running
        if wasRunning {
            appendLog("→ Restarting shim daemon...")
            do {
                try await shimManager.restart()
                appendLog("✓ Shim daemon restarted")
            } catch {
                appendLog("⚠ Restart failed: \(error.localizedDescription) — you may need to restart manually")
            }
        } else {
            appendLog("ℹ Shim was not running — skipping restart")
        }

        appendLog("✓ Update complete!")
    }

    // MARK: - Helpers

    /// Append a line to the update log on the main actor.
    private func appendLog(_ message: String) {
        updateLog.append(message)
    }

    /// Finds a Python 3 executable on the system that is version 3.11 or newer.
    private func findCompatiblePython() async -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        
        // 1. Dynamic check: Scan ~/.local/share/uv/python/ for any compatible uv-managed Python environments
        let uvPythonDir = "\(home)/.local/share/uv/python"
        if let subdirs = try? fm.contentsOfDirectory(atPath: uvPythonDir) {
            for subdir in subdirs {
                let candidate = "\(uvPythonDir)/\(subdir)/bin/python3"
                if fm.fileExists(atPath: candidate) {
                    do {
                        let result = try await ProcessRunner.run(
                            candidate,
                            arguments: ["-c", "import sys; print(sys.version_info >= (3, 11))"]
                        )
                        if result.succeeded && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "True" {
                            return candidate
                        }
                    } catch {
                        continue
                    }
                }
            }
        }
        
        // 2. Static check: Candidate paths in order of preference (preferring Homebrew/user-installed over macOS system Python)
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "\(home)/.local/bin/python3",
            "/usr/bin/python3"
        ]
        
        for candidate in candidates {
            if fm.fileExists(atPath: candidate) {
                // Verify the python version is >= 3.11
                do {
                    let result = try await ProcessRunner.run(
                        candidate,
                        arguments: ["-c", "import sys; print(sys.version_info >= (3, 11))"]
                    )
                    if result.succeeded && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "True" {
                        return candidate
                    }
                } catch {
                    continue
                }
            }
        }
        
        // 3. Last resort: search PATH
        if let pathPython = await ProcessRunner.which("python3") {
            let cleaned = pathPython.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                do {
                    let result = try await ProcessRunner.run(
                        cleaned,
                        arguments: ["-c", "import sys; print(sys.version_info >= (3, 11))"]
                    )
                    if result.succeeded && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "True" {
                        return cleaned
                    }
                } catch {}
            }
        }
        
        return nil
    }
}
