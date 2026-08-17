//
//  CodeCaptureService.swift
//  InterviewAssistant
//
//  Created by Codex on 17/08/2026.
//

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

@MainActor
final class CodeCaptureService: ObservableObject {
    enum CaptureState: Equatable {
        case idle
        case readingCursorContext
        case readingClipboard
        case runningOCR
        case captured(String)
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                "Kod nie przechwycony"
            case .readingCursorContext:
                "Sprawdzanie kontekstu kursora"
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

    func captureCursorContext() {
        state = .readingCursorContext

        guard Self.isAccessibilityTrusted(prompt: true) else {
            state = .failed("brak zgody Accessibility dla odczytu tekstu pod kursorem")
            return
        }

        if let context = Self.focusedTextContext(), !context.isEmpty {
            capturedText = context
            state = .captured("kontekst kursora")
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

    nonisolated private static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    nonisolated private static func focusedTextContext() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard
            focusedStatus == .success,
            let focusedElementRef
        else {
            return nil
        }

        let focusedElement = focusedElementRef as! AXUIElement
        guard
            let fullText = stringAttribute(kAXValueAttribute, from: focusedElement),
            !fullText.isEmpty
        else {
            return nil
        }

        let cursorLocation = selectedTextRange(from: focusedElement)?.location
            ?? min(fullText.count, 0)

        return contextAroundCursor(in: fullText, cursorLocation: cursorLocation)
    }

    nonisolated private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)

        guard status == .success else {
            return nil
        }

        return valueRef as? String
    }

    nonisolated private static func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )

        guard
            status == .success,
            let rangeRef,
            CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = rangeRef as! AXValue
        var range = CFRange()

        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    nonisolated private static func contextAroundCursor(in text: String, cursorLocation: Int) -> String {
        let nsText = text as NSString
        let length = nsText.length
        let safeLocation = min(max(cursorLocation, 0), length)
        let maxCharacters = 8_000
        let halfWindow = maxCharacters / 2
        let roughStart = max(safeLocation - halfWindow, 0)
        let roughEnd = min(safeLocation + halfWindow, length)

        var start = roughStart
        var end = roughEnd

        if roughStart > 0 {
            let beforeCursor = nsText.substring(with: NSRange(location: 0, length: roughStart))
            if let lastNewline = beforeCursor.range(of: "\n", options: .backwards) {
                start = lastNewline.upperBound.utf16Offset(in: beforeCursor)
            }
        }

        if roughEnd < length {
            let afterStart = nsText.substring(with: NSRange(location: roughEnd, length: length - roughEnd))
            if let nextNewline = afterStart.range(of: "\n") {
                end = roughEnd + nextNewline.lowerBound.utf16Offset(in: afterStart)
            }
        }

        let range = NSRange(location: start, length: max(end - start, 0))
        return nsText.substring(with: range)
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
