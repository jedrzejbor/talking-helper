//
//  OpenAISuggestionService.swift
//  InterviewAssistant
//
//  Created by Codex on 20/08/2026.
//

import Foundation

@MainActor
final class OpenAISuggestionService: ObservableObject {
    enum SuggestionState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                "AI gotowe"
            case .loading:
                "Generowanie odpowiedzi"
            case .ready:
                "Odpowiedz wygenerowana"
            case .failed(let message):
                "Blad AI: \(message)"
            }
        }
    }

    @Published private(set) var state: SuggestionState = .idle
    @Published private(set) var answer = ""

    func generateAnswer(apiKey: String, question: String, model: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            state = .failed("brak klucza API")
            return
        }

        guard !trimmedQuestion.isEmpty else {
            state = .failed("wpisz pytanie")
            return
        }

        guard !trimmedModel.isEmpty else {
            state = .failed("brak nazwy modelu")
            return
        }

        state = .loading
        answer = ""

        Task {
            do {
                answer = try await Self.callResponsesAPI(
                    apiKey: trimmedKey,
                    model: trimmedModel,
                    question: trimmedQuestion
                )
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated private static func callResponsesAPI(apiKey: String, model: String, question: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45

        let body = ResponsesRequest(
            model: model,
            input: """
            Jestes prywatnym asystentem podczas rozmowy rekrutacyjnej lub rozmowy z klientem.
            Odpowiedz po polsku, konkretnie i naturalnie. Daj uzytkownikowi gotowa wypowiedz w 3-6 punktach lub krotkim akapicie.

            Pytanie rozmowcy:
            \(question)
            """,
            store: false
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            throw OpenAIClientError.apiError(
                status: httpResponse.statusCode,
                message: apiError?.error.message ?? String(data: data, encoding: .utf8) ?? "brak tresci bledu"
            )
        }

        let decoded = try JSONDecoder().decode(ResponsesResponse.self, from: data)

        guard let text = decoded.extractedText, !text.isEmpty else {
            throw OpenAIClientError.emptyOutput
        }

        return text
    }
}

private struct ResponsesRequest: Encodable {
    let model: String
    let input: String
    let store: Bool
}

private struct ResponsesResponse: Decodable {
    let outputText: String?
    let output: [OutputItem]?

    var extractedText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        let text = output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")

        return text?.isEmpty == false ? text : nil
    }

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct OutputItem: Decodable {
    let content: [ContentItem]?
}

private struct ContentItem: Decodable {
    let text: String?
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let message: String
}

private enum OpenAIClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(status: Int, message: String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "niepoprawny URL API"
        case .invalidResponse:
            "niepoprawna odpowiedz HTTP"
        case .apiError(let status, let message):
            "HTTP \(status): \(message)"
        case .emptyOutput:
            "model nie zwrocil tekstu"
        }
    }
}
