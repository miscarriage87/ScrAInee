import Foundation
import KeychainAccess

/// Client for interacting with the Claude API
final class ClaudeAPIClient: Sendable {
    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model: String
    private let maxTokens: Int

    /// Configuration for retry behavior
    struct RetryConfig {
        var maxAttempts: Int = 3
        var baseDelay: TimeInterval = 1.0
        var maxDelay: TimeInterval = 30.0
        var retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]
    }

    private let retryConfig: RetryConfig

    // MARK: - Initialization

    init(apiKey: String, model: String = "claude-sonnet-4-20250514", maxTokens: Int = 4096, retryConfig: RetryConfig = RetryConfig()) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.retryConfig = retryConfig
    }

    /// Convenience initializer that loads API key from Keychain
    convenience init() {
        let keychain = KeychainAccess.Keychain(service: "com.cpohl.scrainee")
        let apiKey = (try? keychain.get("claude_api_key")) ?? ""
        self.init(apiKey: apiKey)
    }

    // MARK: - Connection Test

    /// Tests the API connection with a minimal request
    /// - Throws: ClaudeAPIError if connection fails or key is invalid
    func testConnection() async throws {
        guard !apiKey.isEmpty else {
            throw ClaudeAPIError.noAPIKey
        }

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "messages": [
                [
                    "role": "user",
                    "content": [["type": "text", "text": "Hi"]]
                ]
            ]
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return // Success
        case 401:
            throw ClaudeAPIError.invalidAPIKey
        case 429:
            throw ClaudeAPIError.rateLimited
        case 500...599:
            if let errorResponse = try? JSONDecoder().decode(APIError.self, from: data) {
                throw ClaudeAPIError.serverError(errorResponse.message)
            }
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        default:
            if let errorResponse = try? JSONDecoder().decode(APIError.self, from: data) {
                throw ClaudeAPIError.apiError(errorResponse.message)
            }
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - API Types

    struct Message: Codable {
        let role: String
        let content: [ContentBlock]
    }

    struct ContentBlock: Codable {
        let type: String
        let text: String?
        let source: ImageSource?

        init(type: String, text: String? = nil, source: ImageSource? = nil) {
            self.type = type
            self.text = text
            self.source = source
        }
    }

    struct ImageSource: Codable {
        let type: String
        let media_type: String
        let data: String
    }

    struct APIRequest: Encodable {
        let model: String
        let max_tokens: Int
        let messages: [[String: Any]]

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encode(max_tokens, forKey: .max_tokens)
            
            // Custom encoding for messages with Any type
            let messagesData = try JSONSerialization.data(withJSONObject: messages)
            let messagesJSON = try JSONSerialization.jsonObject(with: messagesData)
            try container.encode(messagesJSON as! [[String: AnyCodable]], forKey: .messages)
        }
        
        enum CodingKeys: String, CodingKey {
            case model
            case max_tokens
            case messages
        }
    }
    
    // Helper struct to encode Any values
    struct AnyCodable: Encodable {
        let value: Any
        
        init(_ value: Any) {
            self.value = value
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            
            switch value {
            case let string as String:
                try container.encode(string)
            case let int as Int:
                try container.encode(int)
            case let double as Double:
                try container.encode(double)
            case let bool as Bool:
                try container.encode(bool)
            case let dict as [String: Any]:
                let anyDict = dict.mapValues { AnyCodable($0) }
                try container.encode(anyDict)
            case let array as [Any]:
                let anyArray = array.map { AnyCodable($0) }
                try container.encode(anyArray)
            default:
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
            }
        }
    }

    struct APIResponse: Codable {
        let id: String
        let type: String
        let role: String
        let content: [ResponseContent]
        let usage: Usage?
    }

    struct ResponseContent: Codable {
        let type: String
        let text: String?
    }

    struct Usage: Codable {
        let input_tokens: Int
        let output_tokens: Int
    }

    struct APIError: Codable {
        let type: String
        let message: String
    }

    // MARK: - Streaming Types

    struct StreamEvent: Codable {
        let type: String
        let index: Int?
        let content_block: StreamContentBlock?
        let delta: StreamDelta?
        let message: APIResponse?
        let usage: Usage?
    }

    struct StreamContentBlock: Codable {
        let type: String
        let text: String?
    }

    struct StreamDelta: Codable {
        let type: String?
        let text: String?
        let stop_reason: String?
    }

    // MARK: - Text Analysis

    /// Sends a text-only prompt to Claude
    func analyzeText(prompt: String) async throws -> (text: String, usage: Usage?) {
        let contentBlocks: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]

        return try await sendRequest(contentBlocks: contentBlocks)
    }

    // MARK: - Image Analysis

    /// Analyzes images with a prompt
    /// - Parameters:
    ///   - images: Array of image data (HEIC, PNG, JPEG, etc.)
    ///   - prompt: The analysis prompt
    /// - Returns: Analysis text and token usage
    func analyzeImages(_ images: [Data], prompt: String) async throws -> (text: String, usage: Usage?) {
        var contentBlocks: [[String: Any]] = []

        // Add images (max 20 per request)
        for imageData in images.prefix(20) {
            let base64 = imageData.base64EncodedString()

            // Detect media type
            let mediaType = detectMediaType(from: imageData)

            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": base64
                ]
            ])
        }

        // Add text prompt
        contentBlocks.append([
            "type": "text",
            "text": prompt
        ])

        return try await sendRequest(contentBlocks: contentBlocks)
    }

    // MARK: - Private Methods

    private func sendRequest(contentBlocks: [[String: Any]]) async throws -> (text: String, usage: Usage?) {
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                [
                    "role": "user",
                    "content": contentBlocks
                ]
            ]
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        // Handle errors
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(APIError.self, from: data) {
                throw ClaudeAPIError.apiError(errorResponse.message)
            }
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

        guard let text = apiResponse.content.first?.text else {
            throw ClaudeAPIError.emptyResponse
        }

        return (text, apiResponse.usage)
    }

    private func detectMediaType(from data: Data) -> String {
        guard data.count > 8 else { return "image/jpeg" }

        let bytes = [UInt8](data.prefix(8))

        // Check for HEIC/HEIF (ftyp box)
        if bytes.count >= 8 {
            let ftypString = String(bytes: bytes[4...7], encoding: .ascii)
            if ftypString == "ftyp" {
                return "image/heic"
            }
        }

        // Check for PNG
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }

        // Check for JPEG
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        }

        // Check for WebP
        if bytes.count >= 4 {
            let riffString = String(bytes: bytes[0...3], encoding: .ascii)
            if riffString == "RIFF" {
                return "image/webp"
            }
        }

        // Check for GIF
        if bytes.count >= 6 {
            let gifString = String(bytes: bytes[0...5], encoding: .ascii)
            if gifString == "GIF87a" || gifString == "GIF89a" {
                return "image/gif"
            }
        }

        // Default to JPEG
        return "image/jpeg"
    }

    // MARK: - Streaming API

    /// Analyzes images with a prompt and streams the response
    /// - Parameters:
    ///   - images: Array of image data
    ///   - prompt: The analysis prompt
    ///   - onToken: Callback for each token/chunk received
    /// - Returns: Full text and token usage
    func streamAnalyzeImages(
        _ images: [Data],
        prompt: String,
        onToken: @escaping (String) -> Void
    ) async throws -> (text: String, usage: Usage?) {
        var contentBlocks: [[String: Any]] = []

        // Add images (max 20 per request)
        for imageData in images.prefix(20) {
            let base64 = imageData.base64EncodedString()
            let mediaType = detectMediaType(from: imageData)

            contentBlocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": base64
                ]
            ])
        }

        // Add text prompt
        contentBlocks.append([
            "type": "text",
            "text": prompt
        ])

        return try await sendStreamingRequest(contentBlocks: contentBlocks, onToken: onToken)
    }

    /// Streams a text-only prompt to Claude
    func streamAnalyzeText(
        prompt: String,
        onToken: @escaping (String) -> Void
    ) async throws -> (text: String, usage: Usage?) {
        let contentBlocks: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]

        return try await sendStreamingRequest(contentBlocks: contentBlocks, onToken: onToken)
    }

    private func sendStreamingRequest(
        contentBlocks: [[String: Any]],
        onToken: @escaping (String) -> Void
    ) async throws -> (text: String, usage: Usage?) {
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                [
                    "role": "user",
                    "content": contentBlocks
                ]
            ]
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }

        var fullText = ""
        var finalUsage: Usage?

        for try await line in bytes.lines {
            // SSE format: "data: {json}"
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = String(line.dropFirst(6))
            guard jsonString != "[DONE]" else { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let event = try? JSONDecoder().decode(StreamEvent.self, from: jsonData) else {
                continue
            }

            switch event.type {
            case "content_block_delta":
                if let text = event.delta?.text {
                    fullText += text
                    onToken(text)
                }
            case "message_delta":
                if let usage = event.usage {
                    finalUsage = usage
                }
            case "message_stop":
                break
            default:
                continue
            }
        }

        return (fullText, finalUsage)
    }

    // MARK: - Retry Logic

    /// Executes an operation with exponential backoff retry
    func withRetry<T>(
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<retryConfig.maxAttempts {
            do {
                return try await operation()
            } catch let error as ClaudeAPIError {
                lastError = error

                // Check if error is retryable
                if case .httpError(let statusCode) = error,
                   retryConfig.retryableStatusCodes.contains(statusCode) {
                    // Calculate delay with exponential backoff
                    let delay = min(
                        retryConfig.baseDelay * pow(2.0, Double(attempt)),
                        retryConfig.maxDelay
                    )

                    // Add jitter (0-25% of delay)
                    let jitter = Double.random(in: 0...0.25) * delay
                    let totalDelay = delay + jitter

                    print("Claude API: Retry attempt \(attempt + 1) after \(Int(totalDelay))s delay (status: \(statusCode))")

                    try await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
                    continue
                }

                // Non-retryable error, throw immediately
                throw error
            } catch {
                // Non-ClaudeAPIError, throw immediately
                throw error
            }
        }

        throw lastError ?? ClaudeAPIError.invalidResponse
    }

    /// Analyzes images with retry logic
    func analyzeImagesWithRetry(
        _ images: [Data],
        prompt: String
    ) async throws -> (text: String, usage: Usage?) {
        try await withRetry {
            try await self.analyzeImages(images, prompt: prompt)
        }
    }

    /// Streams image analysis with retry logic
    func streamAnalyzeImagesWithRetry(
        _ images: [Data],
        prompt: String,
        onToken: @escaping (String) -> Void
    ) async throws -> (text: String, usage: Usage?) {
        try await withRetry {
            try await self.streamAnalyzeImages(images, prompt: prompt, onToken: onToken)
        }
    }
}

// MARK: - Cost Estimator

struct CostEstimator {
    // Claude Sonnet 4 pricing (as of 2025)
    static let inputPricePerMillionTokens: Double = 3.0  // $3 per million input tokens
    static let outputPricePerMillionTokens: Double = 15.0 // $15 per million output tokens

    /// Estimates the approximate cost for analyzing screenshots
    /// - Parameters:
    ///   - screenshotCount: Number of screenshots to analyze
    ///   - estimatedOutputTokens: Expected output tokens (default 500)
    /// - Returns: Estimated cost in USD
    static func estimateCost(screenshotCount: Int, estimatedOutputTokens: Int = 500) -> Double {
        // Rough estimate: ~1000 tokens per screenshot (base64 + vision processing)
        let inputTokens = screenshotCount * 1000

        let inputCost = Double(inputTokens) / 1_000_000 * inputPricePerMillionTokens
        let outputCost = Double(estimatedOutputTokens) / 1_000_000 * outputPricePerMillionTokens

        return inputCost + outputCost
    }

    /// Formats the estimated cost as a string
    static func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "< $0.01")
        }
        return String(format: "$%.2f", cost)
    }

    /// Calculates actual cost from usage data
    static func calculateActualCost(usage: ClaudeAPIClient.Usage) -> Double {
        let inputCost = Double(usage.input_tokens) / 1_000_000 * inputPricePerMillionTokens
        let outputCost = Double(usage.output_tokens) / 1_000_000 * outputPricePerMillionTokens
        return inputCost + outputCost
    }
}

// MARK: - Errors

enum ClaudeAPIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case emptyResponse
    case noAPIKey
    case invalidAPIKey
    case rateLimited
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ungueltige API-Antwort"
        case .httpError(let code):
            return "HTTP Fehler: \(code)"
        case .apiError(let message):
            return "API Fehler: \(message)"
        case .emptyResponse:
            return "Leere API-Antwort"
        case .noAPIKey:
            return "Kein API-Key konfiguriert"
        case .invalidAPIKey:
            return "Ungueltiger API-Key"
        case .rateLimited:
            return "Rate Limit erreicht - bitte warten"
        case .serverError(let message):
            return "Server Fehler: \(message)"
        }
    }
}
