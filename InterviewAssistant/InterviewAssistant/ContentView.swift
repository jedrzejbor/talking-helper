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
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 380)
        .onAppear {
            hotkeyManager.registerToggleOverlayHotkey {
                overlayController.toggle()
            }
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
}
