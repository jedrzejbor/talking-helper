//
//  ContentView.swift
//  InterviewAssistant
//
//  Created by jedrek on 17/08/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var overlayController = OverlayPanelController()
    @StateObject private var hotkeyManager = HotkeyManager()
    @StateObject private var microphoneService = MicrophoneCaptureService()
    @StateObject private var screenCaptureService = ScreenCaptureDiagnosticService()
    @StateObject private var codeCaptureService = CodeCaptureService()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Interview Assistant")
                    .font(.largeTitle.weight(.semibold))

                Text("Etap 0: test overlayu")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                overlaySection
                microphoneSection
                screenCaptureSection
                codeCaptureSection
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 720)
        .onAppear {
            hotkeyManager.registerDefaultHotkeys(
                toggleOverlay: {
                    overlayController.toggle()
                },
                captureCode: {
                    codeCaptureService.captureCode()
                },
                captureCursorContext: {
                    codeCaptureService.captureCursorContext()
                }
            )
        }
        .onDisappear {
            microphoneService.stop()
        }
    }

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overlay")
                .font(.headline)

            Text("Pierwszy test sprawdza, czy mozemy wyswietlic prywatny panel nad innymi aplikacjami.")
                .foregroundStyle(.secondary)

            HStack {
                Button(overlayController.isVisible ? "Ukryj overlay" : "Pokaz overlay") {
                    overlayController.toggle()
                }
                .buttonStyle(.borderedProminent)

                Text(overlayController.isVisible ? "Overlay jest widoczny" : "Overlay jest ukryty")
                    .foregroundStyle(.secondary)
            }

            Text(hotkeyManager.state.label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mikrofon")
                .font(.headline)

            Text("Ten test sprawdza, czy aplikacja ma dostep do mikrofonu i czy poziom audio reaguje na glos.")
                .foregroundStyle(.secondary)

            HStack {
                Button(microphoneService.state == .running ? "Zatrzymaj mikrofon" : "Uruchom mikrofon") {
                    microphoneService.toggle()
                }
                .buttonStyle(.bordered)

                Text(microphoneService.state.label)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: microphoneService.level)
                .progressViewStyle(.linear)

            Text(String(format: "Poziom: %.1f dB", microphoneService.decibels))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var screenCaptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ScreenCaptureKit")
                .font(.headline)

            Text("Ten test sprawdza, czy aplikacja widzi ekrany, okna i aplikacje jako zrodla przechwytywania.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Popros o dostep") {
                    screenCaptureService.requestPermission()
                }
                .buttonStyle(.bordered)
                .disabled(screenCaptureService.state == .checking)

                Button("Sprawdz dostep do ekranu") {
                    screenCaptureService.checkAccess()
                }
                .buttonStyle(.bordered)
                .disabled(screenCaptureService.state == .checking)

                Button("Otworz ustawienia") {
                    PrivacySettingsOpener.openScreenCaptureSettings()
                }
                .buttonStyle(.bordered)

                Text(screenCaptureService.state.label)
                    .foregroundStyle(.secondary)
            }

            if case .ready(let summary) = screenCaptureService.state {
                Text(summary.details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if screenCaptureService.state == .permissionMissing {
                Text("Wlacz przelacznik przy InterviewAssistant w ustawieniach prywatnosci. Jesli jest juz wlaczony, usun wpis minusem, uruchom aplikacje ponownie i kliknij Popros o dostep.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .failed = screenCaptureService.state {
                Text("ScreenCaptureKit zwrocil blad mimo zgody. Zamknij aplikacje, uruchom ponownie z Xcode i sprawdz, czy w Signing & Capabilities ustawiony jest staly Team.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var codeCaptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Przechwytywanie kodu")
                .font(.headline)

            Text("Cmd + Shift + C pobiera tekst ze schowka. Cmd + Shift + D probuje pobrac kontekst z miejsca kursora bez zaznaczania tekstu.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Przechwyc kod") {
                    codeCaptureService.captureCode()
                }
                .buttonStyle(.bordered)
                .disabled(codeCaptureService.state == .runningOCR)

                Button("Kontekst kursora") {
                    codeCaptureService.captureCursorContext()
                }
                .buttonStyle(.bordered)
                .disabled(codeCaptureService.state == .runningOCR)

                Button("Wyczysc") {
                    codeCaptureService.clear()
                }
                .buttonStyle(.bordered)

                Text(codeCaptureService.state.label)
                    .foregroundStyle(.secondary)
            }

            if case .failed(let message) = codeCaptureService.state,
               message.contains("Accessibility") {
                HStack {
                    Button("Otworz Accessibility") {
                        PrivacySettingsOpener.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)

                    Text("Wlacz InterviewAssistant w Accessibility, zamknij aplikacje i uruchom ja ponownie.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if !codeCaptureService.capturedText.isEmpty {
                ScrollView {
                    Text(codeCaptureService.capturedText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 140)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
