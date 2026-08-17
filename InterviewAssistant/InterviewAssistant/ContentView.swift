//
//  ContentView.swift
//  InterviewAssistant
//
//  Created by jedrek on 17/08/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var overlayController = OverlayPanelController()

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

            VStack(alignment: .leading, spacing: 10) {
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
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 260)
    }
}
