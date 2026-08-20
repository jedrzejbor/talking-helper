//
//  OpenAIAudioTranscriptionClient.swift
//  InterviewAssistant
//
//  Created by Codex on 20/08/2026.
//

import Foundation

enum OpenAIAudioTranscriptionClient {
    static func transcribe(
        audioURL: URL,
        apiKey: String,
        model: String,
        language: String = "pl"
    ) async throws -> String {
        guard let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            throw AudioTranscriptionClientError.invalidURL
        }

        let audioData = try Data(contentsOf: audioURL)
        guard !audioData.isEmpty else {
            throw AudioTranscriptionClientError.emptyRecording
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = multipartBody(
            boundary: boundary,
            audioData: audioData,
            filename: audioURL.lastPathComponent,
            mimeType: mimeType(for: audioURL.pathExtension),
            model: model,
            language: language
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AudioTranscriptionClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(TranscriptionErrorResponse.self, from: data)
            throw AudioTranscriptionClientError.apiError(
                status: httpResponse.statusCode,
                message: apiError?.error.message ?? String(data: data, encoding: .utf8) ?? "brak tresci bledu"
            )
        }

        let responseBody = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let text = responseBody.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw AudioTranscriptionClientError.emptyTranscript
        }

        return text
    }

    private static func multipartBody(
        boundary: String,
        audioData: Data,
        filename: String,
        mimeType: String,
        model: String,
        language: String
    ) -> Data {
        var body = Data()

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendUTF8("\(model)\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.appendUTF8("\(language)\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.appendUTF8("json\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audioData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        return body
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "wav":
            "audio/wav"
        case "m4a":
            "audio/mp4"
        default:
            "application/octet-stream"
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ text: String) {
        append(Data(text.utf8))
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct TranscriptionErrorResponse: Decodable {
    let error: TranscriptionAPIError
}

private struct TranscriptionAPIError: Decodable {
    let message: String
}

private enum AudioTranscriptionClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyRecording
    case emptyTranscript
    case apiError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "niepoprawny URL API"
        case .invalidResponse:
            "niepoprawna odpowiedz HTTP"
        case .emptyRecording:
            "nagrany plik audio jest pusty"
        case .emptyTranscript:
            "model nie zwrocil transkrypcji"
        case .apiError(let status, let message):
            "HTTP \(status): \(message)"
        }
    }
}
