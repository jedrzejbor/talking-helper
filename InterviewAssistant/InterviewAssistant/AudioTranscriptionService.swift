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
                transcript = try await OpenAIAudioTranscriptionClient.transcribe(
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

private enum AudioTranscriptionError: LocalizedError {
    case recordingDidNotStart

    var errorDescription: String? {
        switch self {
        case .recordingDidNotStart:
            "nie udalo sie uruchomic nagrywania"
        }
    }
}
