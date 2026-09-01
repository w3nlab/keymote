import Foundation
import SriVibeCore

struct CloudTranscript: Sendable {
    let text: String
}

enum CloudModelError: LocalizedError {
    case notConfigured(CloudProvider)
    case unsupportedCapability(CloudProvider)
    case invalidResponse
    case http(Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case let .notConfigured(provider): "\(provider.rawValue) is not configured"
        case let .unsupportedCapability(provider): "\(provider.rawValue) does not support transcription"
        case .invalidResponse: "The cloud service returned an invalid response"
        case let .http(status): "Cloud service request failed (HTTP \(status))"
        case let .transport(message): message
        }
    }
}

/// The only cloud-facing surface used by UI features. Provider HTTP formats
/// stay behind this gateway so future modules do not depend on vendor APIs.
final class CloudModelGateway: @unchecked Sendable {
    private let keyStore: InstallationKeyStore
    private let session: URLSession

    init(keyStore: InstallationKeyStore = InstallationKeyStore(), session: URLSession = .shared) {
        self.keyStore = keyStore
        self.session = session
    }

    func transcribe(audio: Data, provider: CloudProvider, configuration: CloudProviderConfiguration, languageCode: String?) async throws -> CloudTranscript {
        guard provider.supportsTranscription else { throw CloudModelError.unsupportedCapability(provider) }
        guard configuration.isEnabled, !configuration.transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let encrypted = configuration.encryptedAPIKey, !encrypted.isEmpty else { throw CloudModelError.notConfigured(provider) }
        let key = try keyStore.decrypt(encrypted)
        switch provider {
        case .openAI:
            return try await openAITranscription(audio: audio, key: key, model: configuration.transcriptionModel, languageCode: languageCode)
        case .openRouter:
            return try await openRouterTranscription(audio: audio, key: key, model: configuration.transcriptionModel, languageCode: languageCode)
        case .anthropic:
            throw CloudModelError.unsupportedCapability(provider)
        }
    }

    func generateText(_ prompt: String, provider: CloudProvider, configuration: CloudProviderConfiguration) async throws -> String {
        guard configuration.isEnabled, !configuration.textModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let encrypted = configuration.encryptedAPIKey, !encrypted.isEmpty else { throw CloudModelError.notConfigured(provider) }
        let key = try keyStore.decrypt(encrypted)
        switch provider {
        case .anthropic: return try await anthropicText(prompt, key: key, model: configuration.textModel)
        case .openAI: return try await openAIText(prompt, key: key, model: configuration.textModel)
        case .openRouter: return try await openRouterText(prompt, key: key, model: configuration.textModel)
        }
    }

    private func openAITranscription(audio: Data, key: String, model: String, languageCode: String?) async throws -> CloudTranscript {
        let boundary = "Keymote-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        if let languageCode { field("language", languageCode) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"keymote.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await transcript(request)
    }

    private func openRouterTranscription(audio: Data, key: String, model: String, languageCode: String?) async throws -> CloudTranscript {
        var payload: [String: Any] = ["model": model, "input_audio": ["data": audio.base64EncodedString(), "format": "wav"]]
        if let languageCode { payload["language"] = languageCode }
        var request = jsonRequest(url: "https://openrouter.ai/api/v1/audio/transcriptions", key: key, payload: payload)
        request.setValue("Keymote", forHTTPHeaderField: "X-Title")
        return try await transcript(request)
    }

    private func transcript(_ request: URLRequest) async throws -> CloudTranscript {
        let (data, _) = try await send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = json["text"] as? String, !text.isEmpty else {
            throw CloudModelError.invalidResponse
        }
        return CloudTranscript(text: text)
    }

    private func anthropicText(_ prompt: String, key: String, model: String) async throws -> String {
        var request = jsonRequest(url: "https://api.anthropic.com/v1/messages", key: key, payload: ["model": model, "max_tokens": 64, "messages": [["role": "user", "content": prompt]]])
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        return try await textResponse(request)
    }

    private func openAIText(_ prompt: String, key: String, model: String) async throws -> String {
        let request = jsonRequest(url: "https://api.openai.com/v1/chat/completions", key: key, payload: ["model": model, "messages": [["role": "user", "content": prompt]], "max_tokens": 64])
        return try await textResponse(request)
    }

    private func openRouterText(_ prompt: String, key: String, model: String) async throws -> String {
        let request = jsonRequest(url: "https://openrouter.ai/api/v1/chat/completions", key: key, payload: ["model": model, "messages": [["role": "user", "content": prompt]], "max_tokens": 64])
        return try await textResponse(request)
    }

    private func textResponse(_ request: URLRequest) async throws -> String {
        let (data, _) = try await send(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CloudModelError.invalidResponse }
        if let content = json["content"] as? [[String: Any]], let text = content.compactMap({ $0["text"] as? String }).first { return text }
        if let choices = json["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let text = message["content"] as? String { return text }
        throw CloudModelError.invalidResponse
    }

    private func jsonRequest(url: String, key: String, payload: [String: Any]) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CloudModelError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw CloudModelError.http(http.statusCode) }
            return (data, http)
        } catch let error as CloudModelError { throw error }
        catch { throw CloudModelError.transport(error.localizedDescription) }
    }
}
