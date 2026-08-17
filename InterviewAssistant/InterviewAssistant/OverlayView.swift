//
//  OverlayView.swift
//  InterviewAssistant
//
//  Created by Codex on 17/08/2026.
//

import SwiftUI

struct OverlayView: View {
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Interview Assistant")
                    .font(.headline)

                Spacer()

                Button("Ukryj", action: onHide)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text("Overlay testowy")
                .font(.title3.weight(.semibold))

            Text("Ten panel powinien byc widoczny nad innymi aplikacjami. Teraz sprawdzamy, jak zachowuje sie przy udostepnianiu ekranu.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }
}
