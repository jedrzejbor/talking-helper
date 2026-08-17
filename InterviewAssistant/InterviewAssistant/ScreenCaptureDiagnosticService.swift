//
//  ScreenCaptureDiagnosticService.swift
//  InterviewAssistant
//
//  Created by Codex on 17/08/2026.
//

import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenCaptureDiagnosticService: ObservableObject {
    enum DiagnosticState: Equatable {
        case idle
        case checking
        case ready(Summary)
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                "ScreenCaptureKit nie sprawdzony"
            case .checking:
                "Sprawdzanie zrodel przechwytywania"
            case .ready:
                "ScreenCaptureKit ma dostep"
            case .failed(let message):
                "Brak dostepu albo blad: \(message)"
            }
        }
    }

    struct Summary: Equatable {
        let displayCount: Int
        let windowCount: Int
        let applicationCount: Int
        let sampleApplicationNames: [String]

        var details: String {
            let names = sampleApplicationNames.isEmpty
                ? "brak przykladowych aplikacji"
                : sampleApplicationNames.joined(separator: ", ")

            return "Ekrany: \(displayCount), okna: \(windowCount), aplikacje: \(applicationCount). Przyklady: \(names)"
        }
    }

    @Published private(set) var state: DiagnosticState = .idle

    func checkAccess() {
        state = .checking

        Task {
            do {
                let content = try await SCShareableContent.current
                let appNames = content.applications
                    .map(\.applicationName)
                    .filter { !$0.isEmpty }
                    .sorted()
                    .prefix(5)

                state = .ready(
                    Summary(
                        displayCount: content.displays.count,
                        windowCount: content.windows.count,
                        applicationCount: content.applications.count,
                        sampleApplicationNames: Array(appNames)
                    )
                )
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
