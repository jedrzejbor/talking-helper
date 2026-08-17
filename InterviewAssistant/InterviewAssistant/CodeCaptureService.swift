//
//  CodeCaptureService.swift
//  InterviewAssistant
//
//  Created by Codex on 17/08/2026.
//

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

@MainActor
final class CodeCaptureService: ObservableObject {
    enum CaptureState: Equatable {
        case idle
        case readingClipboard
        case runningOCR
        case captured(String)
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                "Kod nie przechwycony"
            case .readingClipboard:
                "Sprawdzanie schowka"
            case .runningOCR:
                "OCR ekranu w toku"
            case .captured(let source):
                "Przechwycono tekst: \(source)"
            case .failed(let message):
                "Nie udalo sie przechwycic kodu: \(message)"
            }
        }
    }

    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var capturedText = ""

    func captureCode() {
        state = .readingClipboard

        if let clipboardText = NSPasteboard.general.string(forType: .string),
           !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            capturedText = clipboardText
            state = .captured("schowek")
            return
        }

        captureScreenWithOCR()
    }

    func clear() {
        capturedText = ""
        state = .idle
    }

    private func captureScreenWithOCR() {
        state = .runningOCR

        Task {
            do {
                let image = try await Self.captureMainDisplayImage()
                let text = try Self.recognizeText(in: image)

                capturedText = text
                state = text.isEmpty
                    ? .failed("OCR nie znalazl tekstu")
                    : .captured("OCR ekranu")
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated private static func captureMainDisplayImage() async throws -> CGImage {
        let content = try await SCShareableContent.current

        guard let display = content.displays.first else {
            throw CaptureError.missingDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    nonisolated private static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "pl-PL"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
    }
}

private enum CaptureError: LocalizedError {
    case missingDisplay

    var errorDescription: String? {
        switch self {
        case .missingDisplay:
            "brak dostepnego ekranu do screenshotu"
        }
    }
}
