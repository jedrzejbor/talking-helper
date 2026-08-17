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

    private func makePanel() -> NSPanel {
        let contentView = OverlayView(
            onHide: { [weak self] in
                self?.hide()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        let panel = NSPanel(
            contentRect: NSRect(x: 120, y: 160, width: 420, height: 180),
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
}
