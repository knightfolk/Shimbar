import Foundation
import Observation

enum ShimServerState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case error(String)
}

struct ShimServerSnapshot: Sendable {
    let models: [LiveModel]
    let health: HealthResponse?
    let state: ShimServerState

    static let empty = ShimServerSnapshot(models: [], health: nil, state: .stopped)
}

@MainActor
@Observable
final class ShimServer {

    static let shared = ShimServer()

    private(set) var state: ShimServerState = .stopped
    private(set) var snapshot: ShimServerSnapshot = .empty

    private let settings = AppSettings.shared
    private var internalServer_task: Task<Void, Never>?

    private init() {}

    func start() async throws {
        if case .error = state {
            // Allow restarting from any error state
        } else if state != .stopped {
            return
        }
        state = .starting
        snapshot = ShimServerSnapshot(models: [], health: nil, state: .starting)

        do {
            var args = ["--port", "\(settings.port)"]
            if let sp = settings.settingsPath, !sp.isEmpty {
                args += ["--settings", sp]
            }
            args.append("start")
            _ = try await ProcessRunner.run(settings.shimPath, arguments: args)

            let healthURL = URL(string: "http://127.0.0.1:\(settings.port)/health")!
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 5
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = .running
                snapshot = ShimServerSnapshot(models: [], health: nil, state: .running)
                return
            }
            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            let models = await fetchModels()
            state = .running
            snapshot = ShimServerSnapshot(models: models, health: health, state: .running)
        } catch {
            state = .error(error.localizedDescription)
            snapshot = ShimServerSnapshot(models: [], health: nil, state: .error(error.localizedDescription))
            throw error
        }
    }

    func stop() async throws {
        guard state == .running || state == .starting else { return }
        state = .stopping
        do {
            var args = ["--port", "\(settings.port)"]
            if let sp = settings.settingsPath, !sp.isEmpty {
                args += ["--settings", sp]
            }
            args.append("stop")
            _ = try await ProcessRunner.run(settings.shimPath, arguments: args)
        } catch {}
        state = .stopped
        snapshot = .empty
    }

    func restart() async throws {
        try await stop()
        try await start()
    }

    func refreshSnapshot() async {
        guard state == .running else { return }
        do {
            let healthURL = URL(string: "http://127.0.0.1:\(settings.port)/health")!
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 3
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return
            }
            let health = try JSONDecoder().decode(HealthResponse.self, from: data)
            let models = await fetchModels()
            snapshot = ShimServerSnapshot(models: models, health: health, state: .running)
        } catch {}
    }

    func sendTestPrompt(_ prompt: String, model: String) async -> String? {
        let url = URL(string: "http://127.0.0.1:\(settings.port)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ChatCompletionRequest(
            model: model,
            messages: [ChatMessage(role: "user", content: prompt)],
            temperature: 0.0,
            maxTokens: 256
        )
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func fetchModels() async -> [LiveModel] {
        let url = URL(string: "http://127.0.0.1:\(settings.port)/v1/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.httpMethod = "GET"
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let result = try JSONDecoder().decode(LiveModelsResponse.self, from: data)
            return result.data
        } catch {
            return []
        }
    }
}
