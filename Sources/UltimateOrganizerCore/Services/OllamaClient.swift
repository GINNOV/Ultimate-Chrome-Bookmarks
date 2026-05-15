import Foundation

public struct OllamaClient {
    public var baseURL: URL
    public var timeoutInterval: TimeInterval
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        timeoutInterval: TimeInterval = 60,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.timeoutInterval = timeoutInterval
        self.session = session
    }

    public func generate(model: String, prompt: String, contextWindow: Int? = nil) async throws -> String {
        do {
            return try await generateWithOllama(model: model, prompt: prompt, contextWindow: contextWindow)
        } catch {
            return try await generateWithOpenAICompatible(model: model, prompt: prompt)
        }
    }

    private func generateWithOllama(model: String, prompt: String, contextWindow: Int?) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.timeoutInterval = timeoutInterval
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaGenerateRequest(
                model: model,
                prompt: prompt,
                stream: false,
                options: contextWindow.map { OllamaGenerateOptions(numCtx: $0) }
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaClientError.requestFailed
        }

        return try JSONDecoder().decode(OllamaGenerateResponse.self, from: data).response
    }

    private func generateWithOpenAICompatible(model: String, prompt: String) async throws -> String {
        var request = URLRequest(url: openAIChatCompletionsURL())
        request.timeoutInterval = timeoutInterval
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OpenAIChatCompletionRequest(
                model: model,
                messages: [
                    OpenAIChatMessage(role: "user", content: prompt)
                ],
                temperature: 0.1,
                stream: false
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaClientError.requestFailed
        }

        guard let content = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data).choices.first?.message.content else {
            throw OllamaClientError.requestFailed
        }

        return content
    }

    public func checkService(configuredModel: String) async -> LocalAIServiceStatus {
        if let ollamaStatus = await checkOllama(configuredModel: configuredModel) {
            return ollamaStatus
        }

        if let openAIStatus = await checkOpenAICompatible(configuredModel: configuredModel) {
            return openAIStatus
        }

        return LocalAIServiceStatus(
            isAvailable: false,
            backendName: "No local AI server",
            endpoint: baseURL.absoluteString,
            configuredModel: configuredModel,
            availableModels: [],
            isConfiguredModelAvailable: false,
            message: "No response from Ollama /api/tags or LM Studio /v1/models."
        )
    }

    private func checkOllama(configuredModel: String) async -> LocalAIServiceStatus? {
        let url = baseURL.appendingPathComponent("api/tags")
        guard let data = try? await getData(from: url),
              let response = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        else {
            return nil
        }

        let models = response.models.map(\.name).sorted()
        return LocalAIServiceStatus(
            isAvailable: true,
            backendName: "Ollama",
            endpoint: url.absoluteString,
            configuredModel: configuredModel,
            availableModels: models,
            isConfiguredModelAvailable: modelList(models, contains: configuredModel),
            message: models.isEmpty ? "Ollama responded, but no models were reported." : nil
        )
    }

    private func checkOpenAICompatible(configuredModel: String) async -> LocalAIServiceStatus? {
        let url = openAIModelsURL()
        guard let data = try? await getData(from: url),
              let response = try? JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        else {
            return nil
        }

        let models = response.data.map(\.id).sorted()
        return LocalAIServiceStatus(
            isAvailable: true,
            backendName: "LM Studio / OpenAI-compatible",
            endpoint: url.absoluteString,
            configuredModel: configuredModel,
            availableModels: models,
            isConfiguredModelAvailable: modelList(models, contains: configuredModel),
            message: models.isEmpty ? "The server responded, but no models were reported." : nil
        )
    }

    private func getData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = min(timeoutInterval, 5)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaClientError.requestFailed
        }

        return data
    }

    private func openAIModelsURL() -> URL {
        if baseURL.pathComponents.last == "v1" {
            return baseURL.appendingPathComponent("models")
        }

        return baseURL.appendingPathComponent("v1/models")
    }

    private func openAIChatCompletionsURL() -> URL {
        if baseURL.pathComponents.last == "v1" {
            return baseURL.appendingPathComponent("chat/completions")
        }

        return baseURL.appendingPathComponent("v1/chat/completions")
    }

    private func modelList(_ models: [String], contains configuredModel: String) -> Bool {
        let normalizedConfiguredModel = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedConfiguredModel.isEmpty else { return false }

        return models.contains { model in
            model == normalizedConfiguredModel || model.hasPrefix("\(normalizedConfiguredModel):")
        }
    }
}

public enum OllamaClientError: Error {
    case requestFailed
}

public struct LocalAIServiceStatus: Equatable, Sendable {
    public var isAvailable: Bool
    public var backendName: String
    public var endpoint: String
    public var configuredModel: String
    public var availableModels: [String]
    public var isConfiguredModelAvailable: Bool
    public var message: String?
}

private struct OllamaGenerateRequest: Encodable {
    var model: String
    var prompt: String
    var stream: Bool
    var options: OllamaGenerateOptions?

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case stream
        case options
    }
}

private struct OllamaGenerateOptions: Encodable {
    var numCtx: Int

    enum CodingKeys: String, CodingKey {
        case numCtx = "num_ctx"
    }
}

private struct OllamaGenerateResponse: Decodable {
    var response: String
}

private struct OpenAIChatCompletionRequest: Encodable {
    var model: String
    var messages: [OpenAIChatMessage]
    var temperature: Double
    var stream: Bool
}

private struct OpenAIChatMessage: Codable {
    var role: String
    var content: String
}

private struct OpenAIChatCompletionResponse: Decodable {
    var choices: [OpenAIChatChoice]
}

private struct OpenAIChatChoice: Decodable {
    var message: OpenAIChatMessage
}

private struct OllamaTagsResponse: Decodable {
    var models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    var name: String
}

private struct OpenAIModelsResponse: Decodable {
    var data: [OpenAIModel]
}

private struct OpenAIModel: Decodable {
    var id: String
}
