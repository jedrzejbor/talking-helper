//
//  MicrophoneCaptureService.swift
//  InterviewAssistant
//
//  Created by Codex on 17/08/2026.
//

import AVFoundation
import Foundation

@MainActor
final class MicrophoneCaptureService: ObservableObject {
    enum CaptureState: Equatable {
        case idle
        case requestingPermission
        case permissionDenied
        case running
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                "Mikrofon nieaktywny"
            case .requestingPermission:
                "Prosba o dostep do mikrofonu"
            case .permissionDenied:
                "Brak zgody na mikrofon"
            case .running:
                "Mikrofon aktywny"
            case .failed(let message):
                "Blad mikrofonu: \(message)"
            }
        }
    }

    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var level: Double = 0
    @Published private(set) var decibels: Float = -80

    private let engine = AVAudioEngine()

    func toggle() {
        if state == .running {
            stop()
        } else {
            start()
        }
    }

    func start() {
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

                self.startEngine()
            }
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        level = 0
        decibels = -80
        state = .idle
    }

    private func startEngine() {
        if engine.isRunning {
            state = .running
            return
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            let measurement = Self.measureLevel(from: buffer)

            DispatchQueue.main.async {
                self?.decibels = measurement.decibels
                self?.level = measurement.normalizedLevel
            }
        }

        do {
            try engine.start()
            state = .running
        } catch {
            inputNode.removeTap(onBus: 0)
            state = .failed(error.localizedDescription)
        }
    }

    nonisolated private static func measureLevel(from buffer: AVAudioPCMBuffer) -> (decibels: Float, normalizedLevel: Double) {
        guard
            let channelData = buffer.floatChannelData,
            buffer.frameLength > 0
        else {
            return (-80, 0)
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]

            for frame in 0..<frameLength {
                let sample = samples[frame]
                sum += sample * sample
            }
        }

        let sampleCount = max(channelCount * frameLength, 1)
        let rms = sqrt(sum / Float(sampleCount))
        let decibels = max(20 * log10(max(rms, 0.000_001)), -80)
        let normalizedLevel = min(max((Double(decibels) + 80) / 80, 0), 1)

        return (decibels, normalizedLevel)
    }
}
