import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import os.log

// MARK: - OpenAI Models

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let maxTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

// MARK: - OpenAI Client

@DependencyClient
struct OpenAIClient {
    var processTranscription: @Sendable (String, String, String, String, String) async throws -> String = { _, _, _, _, _ in "" }
    // Parameters: transcribedText, context, apiKey, model, systemPrompt
}

extension OpenAIClient: DependencyKey {
    static var liveValue: Self {
        let live = OpenAIClientLive()
        return .init(
            processTranscription: { transcribedText, context, apiKey, model, systemPrompt in
                try await live.processTranscription(
                    transcribedText: transcribedText,
                    context: context,
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt
                )
            }
        )
    }
}

extension DependencyValues {
    var openAI: OpenAIClient {
        get { self[OpenAIClient.self] }
        set { self[OpenAIClient.self] = newValue }
    }
}

// MARK: - OpenAI Client Implementation

struct OpenAIClientLive {
    func processTranscription(
        transcribedText: String,
        context: String,
        apiKey: String,
        model: String,
        systemPrompt: String
    ) async throws -> String {
        let logger = Logger(subsystem: "com.kitlangton.Hex", category: "OpenAI")
        logger.info("🤖 [OpenAI] Starting request")
        logger.info("🤖 [OpenAI] Model: \(model)")
        logger.info("🤖 [OpenAI] Transcribed text: '\(transcribedText)'")
        logger.info("🤖 [OpenAI] Context length: \(context.count) characters")
        logger.info("🤖 [OpenAI] API key length: \(apiKey.count) characters (masked)")
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build the user message combining transcribed text and context
        var userMessage = "Transcribed text: \(transcribedText)"
        if !context.isEmpty {
            userMessage += "\n\nContext from clipboard: \(context)"
        }
        
        logger.info("🤖 [OpenAI] User message: '\(userMessage)'")
        
        let openAIRequest = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "system", content: systemPrompt),
                OpenAIMessage(role: "user", content: userMessage)
            ],
            temperature: 0.7,
            maxTokens: 1000
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(openAIRequest)
            logger.info("🤖 [OpenAI] Request encoded successfully, sending to API...")
        } catch {
            logger.error("❌ [OpenAI] Failed to encode request: \(error.localizedDescription)")
            throw error
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            logger.info("🤖 [OpenAI] Received response from API")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("❌ [OpenAI] Invalid HTTP response")
                throw OpenAIError.invalidResponse
            }
            
            logger.info("🤖 [OpenAI] HTTP Status Code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode error"
                logger.error("❌ [OpenAI] Error response: \(responseString)")
                
                // Try to parse error response
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorData["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    logger.error("❌ [OpenAI] API Error: \(message)")
                    throw OpenAIError.apiError(message)
                }
                throw OpenAIError.httpError(httpResponse.statusCode)
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            logger.info("🤖 [OpenAI] Raw response: \(responseString)")
            
            let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            logger.info("🤖 [OpenAI] Response decoded successfully")
            
            guard let firstChoice = openAIResponse.choices.first else {
                logger.error("❌ [OpenAI] No choices in response")
                throw OpenAIError.noResponse
            }
            
            let result = firstChoice.message.content
            logger.info("✅ [OpenAI] Success! Generated response: '\(result)'")
            return result
            
        } catch {
            logger.error("❌ [OpenAI] Request failed with error: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - OpenAI Errors

enum OpenAIError: Error, LocalizedError {
    case invalidResponse
    case apiError(String)
    case httpError(Int)
    case noResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .apiError(let message):
            return "OpenAI API Error: \(message)"
        case .httpError(let statusCode):
            return "HTTP Error: \(statusCode)"
        case .noResponse:
            return "No response from OpenAI"
        }
    }
} 