//
//  SystemAudioTranscriptionService.swift
//  InterviewAssistant
//
//  Created by Codex on 20/08/2026.
//

import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class SystemAudioTranscriptionService: NSObject, ObservableObject {
    enum TranscriptionState: Equatable {
        case idle
        case starting
        case recording
        case uploading
        case ready
        case permissionMissing
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                "Kanal rozmowcy gotowy do testu"
            case .starting:
                "Uruchamianie przechwytywania rozmowcy"
            case .recording:
                "Nagrywanie audio rozmowcy"
            case .uploading:
                "Transkrypcja audio rozmowcy"
            case .ready:
                "Pytanie rozmowcy gotowe"
            case .permissionMissing:
                "Brak zgody na nagrywanie ekranu i audio"
            case .failed(let message):
                "Blad kanalu rozmowcy: \(message)"
            }
        }
    }

    @Published private(set) var state: TranscriptionState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var recordingSeconds = 0
    @Published private(set) var sampleBufferCount = 0
    @Published private(set) var requestDuration: TimeInterval?

    private let maximumRecordingSeconds = 10
    private let sampleRate: UInt32 = 16_000
    private let sampleQueue = DispatchQueue(label: "InterviewAssistant.SystemAudioTranscription")
    private var stream: SCStream?
    private var recordingTimer: Timer?
    nonisolated private let accumulator = SystemAudioPCMAccumulator()
    private var operationTask: Task<Void, Never>?

    var isBusy: Bool {
        state == .starting || state == .recording || state == .uploading
    }

    func start(apiKey: String, model: String = "gpt-4o-mini-transcribe") {
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

        guard CGPreflightScreenCaptureAccess() else {
            state = .permissionMissing
            return
        }

        transcript = ""
        recordingSeconds = 0
        sampleBufferCount = 0
        requestDuration = nil
        accumulator.reset()
        state = .starting

        operationTask = Task {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else {
                    throw SystemAudioTranscriptionError.missingDisplay
                }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                configuration.capturesAudio = true
                configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = Int(sampleRate)
                configuration.channelCount = 1

                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
                try await stream.startCapture()

                guard !Task.isCancelled else {
                    try? await stream.stopCapture()
                    return
                }

                self.stream = stream
                self.state = .recording
                self.startTimer(apiKey: trimmedKey, model: trimmedModel)
            } catch {
                self.state = .failed(error.localizedDescription)
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
            state = .failed("brak klucza API lub modelu transkrypcji")
            return
        }

        finishAndTranscribe(apiKey: trimmedKey, model: trimmedModel)
    }

    func cancel() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        operationTask?.cancel()
        operationTask = nil

        let activeStream = stream
        stream = nil
        Task {
            try? await activeStream?.stopCapture()
        }

        accumulator.reset()
        recordingSeconds = 0
        sampleBufferCount = 0
        state = .idle
    }

    private func startTimer(apiKey: String, model: String) {
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
                    self.finishAndTranscribe(apiKey: apiKey, model: model)
                }
            }
        }
    }

    private func finishAndTranscribe(apiKey: String, model: String) {
        recordingTimer?.invalidate()
        recordingTimer = nil
        state = .uploading

        let activeStream = stream
        stream = nil
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("interview-assistant-system-audio-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let startedAt = Date()

        operationTask = Task {
            do {
                try await activeStream?.stopCapture()
                let waveData = await withCheckedContinuation { continuation in
                    sampleQueue.async { [accumulator, sampleRate] in
                        continuation.resume(returning: accumulator.makeWaveFile(sampleRate: sampleRate))
                    }
                }

                guard waveData.count > 44 else {
                    throw SystemAudioTranscriptionError.emptyRecording
                }

                try waveData.write(to: outputURL, options: .atomic)
                defer {
                    try? FileManager.default.removeItem(at: outputURL)
                }

                transcript = try await OpenAIAudioTranscriptionClient.transcribe(
                    audioURL: outputURL,
                    apiKey: apiKey,
                    model: model
                )
                requestDuration = Date().timeIntervalSince(startedAt)
                state = .ready
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: outputURL)
                state = .idle
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                requestDuration = Date().timeIntervalSince(startedAt)
                state = .failed(error.localizedDescription)
            }
        }
    }
}

extension SystemAudioTranscriptionService: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else {
            return
        }

        let appendedSamples = accumulator.append(sampleBuffer)

        DispatchQueue.main.async { [weak self] in
            guard let self, appendedSamples > 0 else {
                return
            }

            self.sampleBufferCount += 1
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state != .uploading else {
                return
            }

            self.state = .failed(error.localizedDescription)
        }
    }
}

private final class SystemAudioPCMAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var pcmData = Data()

    func append(_ sampleBuffer: CMSampleBuffer) -> Int {
        guard
            CMSampleBufferDataIsReady(sampleBuffer),
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
            basicDescription.mFormatID == kAudioFormatLinearPCM,
            basicDescription.mBitsPerChannel == 32,
            basicDescription.mFormatFlags & kAudioFormatFlagIsFloat != 0
        else {
            return 0
        }

        var requiredSize = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )

        guard sizeStatus == noErr, requiredSize > 0 else {
            return 0
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let audioBufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        let dataStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )

        guard dataStatus == noErr else {
            return 0
        }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        var appendedSamples = 0

        lock.lock()
        defer { lock.unlock() }

        for buffer in buffers {
            guard let data = buffer.mData else {
                continue
            }

            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)

            for index in 0..<sampleCount {
                let clamped = min(max(samples[index], -1), 1)
                var sample = Int16(clamped * Float(Int16.max)).littleEndian
                withUnsafeBytes(of: &sample) { pcmData.append(contentsOf: $0) }
            }

            appendedSamples += sampleCount
        }

        return appendedSamples
    }

    func reset() {
        lock.lock()
        pcmData.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func makeWaveFile(sampleRate: UInt32) -> Data {
        lock.lock()
        let capturedPCMData = pcmData
        lock.unlock()

        let dataSize = UInt32(clamping: capturedPCMData.count)
        let byteRate = sampleRate * 2
        var wave = Data()

        wave.appendASCII("RIFF")
        wave.appendLittleEndian(36 + dataSize)
        wave.appendASCII("WAVE")
        wave.appendASCII("fmt ")
        wave.appendLittleEndian(UInt32(16))
        wave.appendLittleEndian(UInt16(1))
        wave.appendLittleEndian(UInt16(1))
        wave.appendLittleEndian(sampleRate)
        wave.appendLittleEndian(byteRate)
        wave.appendLittleEndian(UInt16(2))
        wave.appendLittleEndian(UInt16(16))
        wave.appendASCII("data")
        wave.appendLittleEndian(dataSize)
        wave.append(capturedPCMData)

        return wave
    }
}

private extension Data {
    mutating func appendASCII(_ text: String) {
        append(Data(text.utf8))
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }
}

private enum SystemAudioTranscriptionError: LocalizedError {
    case missingDisplay
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .missingDisplay:
            "brak dostepnego ekranu dla strumienia audio"
        case .emptyRecording:
            "nie odebrano probek audio systemowego"
        }
    }
}
