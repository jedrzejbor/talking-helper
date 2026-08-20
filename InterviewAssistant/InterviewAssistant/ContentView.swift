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
    @StateObject private var systemAudioService = SystemAudioCaptureService()
    @StateObject private var transcriptionService = AudioTranscriptionService()
    @StateObject private var screenCaptureService = ScreenCaptureDiagnosticService()
    @StateObject private var codeCaptureService = CodeCaptureService()
    @StateObject private var suggestionService = OpenAISuggestionService()
    @State private var apiKey = ""
    @State private var modelName = "gpt-5.6"
    @State private var transcriptionModelName = "gpt-4o-mini-transcribe"
    @State private var interviewQuestion = ""
    @State private var keyStatus = "Klucz API niezaladowany"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Interview Assistant")
                        .font(.largeTitle.weight(.semibold))

                    Text("Etap 0: testy techniczne")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    overlaySection
                    microphoneSection
                    systemAudioSection
                    transcriptionSection
                    screenCaptureSection
                    codeCaptureSection
                    aiSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 760, minHeight: 700)
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
            loadAPIKey()
        }
        .onDisappear {
            microphoneService.stop()
            systemAudioService.stop()
            transcriptionService.cancel()
        }
        .onChange(of: suggestionService.answer) { _, answer in
            guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            overlayController.updateContent(
                title: "Podpowiedz AI",
                body: answer,
                status: "Ostatnia odpowiedz AI"
            )
        }
        .onChange(of: suggestionService.state) { _, state in
            if state == .loading {
                overlayController.updateContent(
                    title: "AI pracuje",
                    body: "Generuje podpowiedz. Za chwile wynik pojawi sie w tym panelu.",
                    status: "Przetwarzanie",
                    show: overlayController.isVisible
                )
            }
        }
        .onChange(of: transcriptionService.transcript) { _, transcript in
            guard !transcript.isEmpty else {
                return
            }

            interviewQuestion = transcript
            overlayController.updateContent(
                title: "Transkrypcja testowa",
                body: transcript,
                status: "Audio zamienione na tekst"
            )
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

                Button("Pokaz testowa tresc") {
                    overlayController.updateContent(
                        title: "Overlay testowy",
                        body: "Ten panel powinien byc widoczny nad innymi aplikacjami. Teraz sprawdzamy, jak zachowuje sie przy udostepnianiu ekranu.",
                        status: "Test overlayu"
                    )
                }
                .buttonStyle(.bordered)

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

    private var systemAudioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio systemowe")
                .font(.headline)

            Text("Ten test sprawdza, czy ScreenCaptureKit dostarcza dzwiek systemowy lub dzwiek aplikacji rozmowy.")
                .foregroundStyle(.secondary)

            HStack {
                Button(systemAudioService.state == .running ? "Zatrzymaj audio systemowe" : "Uruchom audio systemowe") {
                    systemAudioService.toggle()
                }
                .buttonStyle(.bordered)

                Text(systemAudioService.state.label)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: systemAudioService.level)
                .progressViewStyle(.linear)

            Text(String(format: "Poziom: %.1f dB, probki: %d", systemAudioService.decibels, systemAudioService.sampleBufferCount))
                .font(.callout)
                .foregroundStyle(.secondary)

            if systemAudioService.state == .permissionMissing {
                Text("Wlacz InterviewAssistant w Nagrywanie ekranu i dzwieku systemowego, zamknij aplikacje i uruchom ja ponownie.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transkrypcja audio")
                .font(.headline)

            Text("Nagraj do 10 sekund z mikrofonu. Po zatrzymaniu probka zostanie wyslana do OpenAI i wpisana jako pytanie rozmowcy.")
                .foregroundStyle(.secondary)

            HStack {
                if transcriptionService.state == .recording {
                    Button("Zatrzymaj i transkrybuj") {
                        transcriptionService.stopAndTranscribe(
                            apiKey: apiKey,
                            model: transcriptionModelName
                        )
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Nagraj probke") {
                        microphoneService.stop()
                        transcriptionService.startRecording(
                            apiKey: apiKey,
                            model: transcriptionModelName
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(transcriptionService.isBusy)
                }

                TextField("Model transkrypcji", text: $transcriptionModelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                Text(transcriptionService.state.label)
                    .foregroundStyle(.secondary)
            }

            if transcriptionService.state == .recording {
                ProgressView(value: Double(transcriptionService.recordingSeconds), total: 10)
                    .progressViewStyle(.linear)

                Text("Nagrywanie: \(transcriptionService.recordingSeconds) / 10 s")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let duration = transcriptionService.requestDuration {
                Text(String(format: "Czas odpowiedzi API: %.2f s", duration))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !transcriptionService.transcript.isEmpty {
                Text(transcriptionService.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
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

                Button("Analizuj kod") {
                    suggestionService.analyzeCode(
                        apiKey: apiKey,
                        code: codeCaptureService.capturedText,
                        model: modelName
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    suggestionService.state == .loading ||
                    codeCaptureService.capturedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

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

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OpenAI odpowiedz tekstowa")
                .font(.headline)

            Text("Ten test sprawdza generowanie odpowiedzi na pytanie rozmowcy przez Responses API.")
                .foregroundStyle(.secondary)

            HStack {
                SecureField("OpenAI API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button("Zapisz klucz") {
                    saveAPIKey()
                }
                .buttonStyle(.bordered)
            }

            HStack {
                TextField("Model", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Text(keyStatus)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $interviewQuestion)
                .font(.body)
                .frame(height: 90)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.secondary.opacity(0.25), lineWidth: 1)
                }

            HStack {
                Button("Generuj odpowiedz") {
                    suggestionService.generateAnswer(
                        apiKey: apiKey,
                        question: interviewQuestion,
                        model: modelName
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(suggestionService.state == .loading)

                Text(suggestionService.state.label)
                    .foregroundStyle(.secondary)
            }

            if !suggestionService.answer.isEmpty {
                ScrollView {
                    Text(suggestionService.answer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 130)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func loadAPIKey() {
        do {
            if let savedKey = try KeychainService.read(account: "openai_api_key") {
                apiKey = savedKey
                keyStatus = "Klucz API zaladowany z Keychain"
            }
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func saveAPIKey() {
        do {
            try KeychainService.save(apiKey, account: "openai_api_key")
            keyStatus = "Klucz API zapisany w Keychain"
        } catch {
            keyStatus = error.localizedDescription
        }
    }
}
