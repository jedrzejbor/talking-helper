//
//  SystemAudioCaptureService.swift
//  InterviewAssistant
//
//  Created by Codex on 20/08/2026.
//

import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class SystemAudioCaptureService: NSObject, ObservableObject {
    enum CaptureState: Equatable {
        case idle
        case starting
        case running
        case permissionMissing
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                "Audio systemowe nieaktywne"
            case .starting:
                "Uruchamianie audio systemowego"
            case .running:
                "Audio systemowe aktywne"
            case .permissionMissing:
                "Brak zgody na nagrywanie ekranu i audio"
            case .failed(let message):
                "Blad audio systemowego: \(message)"
            }
        }
    }

    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var level: Double = 0
    @Published private(set) var decibels: Float = -80
    @Published private(set) var sampleBufferCount = 0

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "InterviewAssistant.SystemAudioCapture")

    func toggle() {
        if state == .running || state == .starting {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard CGPreflightScreenCaptureAccess() else {
            state = .permissionMissing
            return
        }

        state = .starting

        Task {
            do {
                let content = try await SCShareableContent.current

                guard let display = content.displays.first else {
                    throw SystemAudioCaptureError.missingDisplay
                }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                configuration.capturesAudio = true
                configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = 48_000
                configuration.channelCount = 2

                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
                try await stream.startCapture()

                self.stream = stream
                self.state = .running
            } catch {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        guard let stream else {
            reset()
            return
        }

        Task {
            do {
                try await stream.stopCapture()
            } catch {
                state = .failed(error.localizedDescription)
                return
            }

            reset()
        }
    }

    private func reset() {
        stream = nil
        level = 0
        decibels = -80
        sampleBufferCount = 0
        state = .idle
    }

    nonisolated private static func measureLevel(from sampleBuffer: CMSampleBuffer) -> (decibels: Float, normalizedLevel: Double)? {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return nil
        }

        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 0,
                mDataByteSize: 0,
                mData: nil
            )
        )
        var blockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            return nil
        }

        let buffer = audioBufferList.mBuffers
        guard
            let data = buffer.mData,
            buffer.mDataByteSize > 0
        else {
            return nil
        }

        let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard sampleCount > 0 else {
            return nil
        }

        let samples = data.assumingMemoryBound(to: Float.self)
        var sum: Float = 0

        for index in 0..<sampleCount {
            let sample = samples[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(sampleCount))
        let decibels = max(20 * log10(max(rms, 0.000_001)), -80)
        let normalizedLevel = min(max((Double(decibels) + 80) / 80, 0), 1)

        return (decibels, normalizedLevel)
    }
}

extension SystemAudioCaptureService: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else {
            return
        }

        let measurement = Self.measureLevel(from: sampleBuffer)

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.sampleBufferCount += 1

            if let measurement {
                self.decibels = measurement.decibels
                self.level = measurement.normalizedLevel
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.state = .failed(error.localizedDescription)
        }
    }
}

private enum SystemAudioCaptureError: LocalizedError {
    case missingDisplay

    var errorDescription: String? {
        switch self {
        case .missingDisplay:
            "brak dostepnego ekranu dla strumienia audio"
        }
    }
}
