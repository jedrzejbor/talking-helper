//
//  OverlayPanelController.swift
//  InterviewAssistant
//
//  Created by Codex on 17/08/2026.
//

import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController: ObservableObject {
    @Published private(set) var isVisible = false

    let content = OverlayContentModel()

    private var panel: NSPanel?

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }

        panel?.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func updateContent(title: String, body: String, status: String, show: Bool = true) {
        content.title = title
        content.body = Self.compact(body)
        content.status = status

        if show {
            self.show()
        }
    }

    private func makePanel() -> NSPanel {
        let contentView = OverlayView(
            content: content,
            onHide: { [weak self] in
                self?.hide()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        let panel = NSPanel(
            contentRect: NSRect(x: 120, y: 160, width: 560, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        return panel
    }

    private static func compact(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count > 1_200 else {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 1_200)
        return String(trimmed[..<endIndex]) + "\n..."
    }
}
