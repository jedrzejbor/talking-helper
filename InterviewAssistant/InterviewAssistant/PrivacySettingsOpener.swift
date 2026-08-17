//
//  PrivacySettingsOpener.swift
//  InterviewAssistant
//
//  Created by Codex on 17/08/2026.
//

import AppKit

enum PrivacySettingsOpener {
    static func openScreenCaptureSettings() {
        openSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        openSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func openSettings(urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
