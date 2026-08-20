//
//  OverlayView.swift
//  InterviewAssistant
//
//  Created by Codex on 17/08/2026.
//

import SwiftUI

struct OverlayView: View {
    @ObservedObject var content: OverlayContentModel
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

            Text(content.title)
                .font(.title3.weight(.semibold))

            ScrollView {
                Text(content.body)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 190)

            Text(content.status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }
}
