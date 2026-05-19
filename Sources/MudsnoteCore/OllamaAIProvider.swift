import Foundation

public struct OllamaAIProvider: Sendable {
    public let baseURL: URL
    public let model: String
    public let session: URLSession

    public init(baseURL: URL, model: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    public func generate(request: AIRequest) async throws -> String {
        let prompt = try AIPromptBuilder.prompt(for: request)
        let endpoint = baseURL.appendingPathComponent("api/generate")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 120
        urlRequest.httpBody = try JSONEncoder().encode(OllamaGenerateRequest(
            model: model,
            prompt: prompt,
            stream: false
        ))

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                throw AIError.requestFailed(body)
            }
            let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            let output = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else { throw AIError.invalidResponse }
            return output
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.localProviderUnavailable(baseURL.absoluteString)
        }
    }

    public func testConnection() async throws {
        let endpoint = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AIError.localProviderUnavailable(baseURL.absoluteString)
        }
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}
