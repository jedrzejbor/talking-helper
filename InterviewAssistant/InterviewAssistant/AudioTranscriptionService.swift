//
//  AudioTranscriptionService.swift
//  InterviewAssistant
//
//  Created by Codex on 20/08/2026.
//

import AVFoundation
import Foundation

@MainActor
final class AudioTranscriptionService: NSObject, ObservableObject {
    enum TranscriptionState: Equatable {
        case idle
        case requestingPermission
        case recording
        case uploading
        case ready
        case permissionDenied
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                "Transkrypcja gotowa do testu"
            case .requestingPermission:
                "Prosba o dostep do mikrofonu"
            case .recording:
                "Nagrywanie probki"
            case .uploading:
                "Wysylanie audio do transkrypcji"
            case .ready:
                "Transkrypcja gotowa"
            case .permissionDenied:
                "Brak zgody na mikrofon"
            case .failed(let message):
                "Blad transkrypcji: \(message)"
            }
        }
    }

    @Published private(set) var state: TranscriptionState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var recordingSeconds = 0
    @Published private(set) var requestDuration: TimeInterval?

    private let maximumRecordingSeconds = 10
    private var recorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingURL: URL?

    var isBusy: Bool {
        state == .requestingPermission || state == .recording || state == .uploading
    }

    func startRecording(apiKey: String, model: String = "gpt-4o-mini-transcribe") {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            state = .failed("brak klucza API")
            return
        }

        guard !trimmedModel.isEmpty else {
            state = .failed("brak nazwy modelu transkrypcji")
            return
        }

        state = .requestingPermission

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard let self else {
                    return
                }

                guard granted else {
                    self.state = .permissionDenied
                    return
                }

                self.beginRecording(apiKey: trimmedKey, model: trimmedModel)
            }
        }
    }

    func stopAndTranscribe(apiKey: String, model: String = "gpt-4o-mini-transcribe") {
        guard state == .recording else {
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty, !trimmedModel.isEmpty else {
            cancelRecording()
            state = .failed("brak klucza API lub modelu transkrypcji")
            return
        }

        finishRecordingAndUpload(apiKey: trimmedKey, model: trimmedModel)
    }

    func cancel() {
        cancelRecording()
        state = .idle
    }

    private func beginRecording(apiKey: String, model: String) {
        do {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("interview-assistant-transcription-\(UUID().uuidString)")
                .appendingPathExtension("m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw AudioTranscriptionError.recordingDidNotStart
            }

            self.recorder = recorder
            recordingURL = fileURL
            recordingSeconds = 0
            requestDuration = nil
            transcript = ""
            state = .recording

            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self else {
                        timer.invalidate()
                        return
                    }

                    self.recordingSeconds += 1

                    if self.recordingSeconds >= self.maximumRecordingSeconds {
                        timer.invalidate()
                        self.finishRecordingAndUpload(apiKey: apiKey, model: model)
                    }
                }
            }
        } catch {
            cancelRecording()
            state = .failed(error.localizedDescription)
        }
    }

    private func finishRecordingAndUpload(apiKey: String, model: String) {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recorder?.stop()
        recorder = nil

        guard let recordingURL else {
            state = .failed("brak nagranego pliku audio")
            return
        }

        state = .uploading
        let startedAt = Date()

        Task {
            defer {
                try? FileManager.default.removeItem(at: recordingURL)
                self.recordingURL = nil
            }

            do {
                transcript = try await Self.transcribe(
                    audioURL: recordingURL,
                    apiKey: apiKey,
                    model: model
                )
                requestDuration = Date().timeIntervalSince(startedAt)
                state = .ready
            } catch {
                requestDuration = Date().timeIntervalSince(startedAt)
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recorder?.stop()
        recorder = nil

        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }

        recordingURL = nil
        recordingSeconds = 0
    }

    nonisolated private static func transcribe(audioURL: URL, apiKey: String, model: String) async throws -> String {
        guard let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            throw AudioTranscriptionError.invalidURL
        }

        let audioData = try Data(contentsOf: audioURL)
        guard !audioData.isEmpty else {
            throw AudioTranscriptionError.emptyRecording
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
            model: model
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AudioTranscriptionError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(TranscriptionErrorResponse.self, from: data)
            throw AudioTranscriptionError.apiError(
                status: httpResponse.statusCode,
                message: apiError?.error.message ?? String(data: data, encoding: .utf8) ?? "brak tresci bledu"
            )
        }

        let responseBody = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let text = responseBody.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw AudioTranscriptionError.emptyTranscript
        }

        return text
    }

    nonisolated private static func multipartBody(
        boundary: String,
        audioData: Data,
        model: String
    ) -> Data {
        var body = Data()

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendUTF8("\(model)\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.appendUTF8("pl\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        body.appendUTF8("json\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"sample.m4a\"\r\n")
        body.appendUTF8("Content-Type: audio/mp4\r\n\r\n")
        body.append(audioData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        return body
    }
}

extension AudioTranscriptionService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard let error else {
            return
        }

        Task { @MainActor [weak self] in
            self?.cancelRecording()
            self?.state = .failed(error.localizedDescription)
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

private enum AudioTranscriptionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case recordingDidNotStart
    case emptyRecording
    case emptyTranscript
    case apiError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "niepoprawny URL API"
        case .invalidResponse:
            "niepoprawna odpowiedz HTTP"
        case .recordingDidNotStart:
            "nie udalo sie uruchomic nagrywania"
        case .emptyRecording:
            "nagrany plik audio jest pusty"
        case .emptyTranscript:
            "model nie zwrocil transkrypcji"
        case .apiError(let status, let message):
            "HTTP \(status): \(message)"
        }
    }
}
