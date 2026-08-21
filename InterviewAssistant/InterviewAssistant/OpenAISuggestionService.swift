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
                "AI pracuje"
            case .ready:
                "Wynik gotowy"
            case .failed(let message):
                "Blad AI: \(message)"
            }
        }
    }

    @Published private(set) var state: SuggestionState = .idle
    @Published private(set) var answer = ""
    @Published private(set) var requestDuration: TimeInterval?

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
        requestDuration = nil
        let startedAt = Date()

        Task {
            do {
                let generatedAnswer = try await Self.callResponsesAPI(
                    apiKey: trimmedKey,
                    model: trimmedModel,
                    input: Self.answerPrompt(question: trimmedQuestion)
                )
                requestDuration = Date().timeIntervalSince(startedAt)
                answer = generatedAnswer
                state = .ready
            } catch {
                requestDuration = Date().timeIntervalSince(startedAt)
                state = .failed(error.localizedDescription)
            }
        }
    }

    func analyzeCode(apiKey: String, code: String, model: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            state = .failed("brak klucza API")
            return
        }

        guard !trimmedCode.isEmpty else {
            state = .failed("najpierw przechwyc kod")
            return
        }

        guard !trimmedModel.isEmpty else {
            state = .failed("brak nazwy modelu")
            return
        }

        state = .loading
        answer = ""
        requestDuration = nil
        let startedAt = Date()

        Task {
            do {
                let generatedAnswer = try await Self.callResponsesAPI(
                    apiKey: trimmedKey,
                    model: trimmedModel,
                    input: Self.codeAnalysisPrompt(code: trimmedCode)
                )
                requestDuration = Date().timeIntervalSince(startedAt)
                answer = generatedAnswer
                state = .ready
            } catch {
                requestDuration = Date().timeIntervalSince(startedAt)
                state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated private static func callResponsesAPI(apiKey: String, model: String, input: String) async throws -> String {
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
            input: input,
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

    nonisolated private static func answerPrompt(question: String) -> String {
        """
        Jestes prywatnym asystentem podczas rozmowy rekrutacyjnej lub rozmowy z klientem.
        Odpowiedz po polsku, konkretnie i naturalnie. Daj uzytkownikowi gotowa wypowiedz w 3-6 punktach lub krotkim akapicie.

        Pytanie rozmowcy:
        \(question)
        """
    }

    nonisolated private static func codeAnalysisPrompt(code: String) -> String {
        """
        Jestes prywatnym asystentem podczas live codingu na rozmowie technicznej.
        Przeanalizuj ponizszy kod i odpowiedz po polsku.

        Format odpowiedzi:
        1. Co widze w kodzie: 2-4 krotkie punkty.
        2. Potencjalny problem: konkret, bez zgadywania ponad dane z kodu.
        3. Co zrobic dalej: kolejne kroki implementacji lub debugowania.
        4. Jak to powiedziec na rozmowie: naturalna wypowiedz w 2-4 zdaniach.

        Jesli kod jest niepelny albo OCR mogl znieksztalcic tekst, zaznacz to wprost.

        Kod:
        ```text
        \(code)
        ```
        """
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
