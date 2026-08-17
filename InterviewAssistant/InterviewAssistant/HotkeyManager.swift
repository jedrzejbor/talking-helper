//
//  HotkeyManager.swift
//  InterviewAssistant
//
//  Created by Codex on 17/08/2026.
//

import Carbon
import Foundation

final class HotkeyManager: ObservableObject {
    enum RegistrationState: Equatable {
        case idle
        case registered(String)
        case failed(OSStatus)

        var label: String {
            switch self {
            case .idle:
                "Skrot nieaktywny"
            case .registered(let shortcut):
                "Skrot aktywny: \(shortcut)"
            case .failed(let status):
                "Nie udalo sie zarejestrowac skrotu: \(status)"
            }
        }
    }

    @Published private(set) var state: RegistrationState = .idle

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    deinit {
        unregister()
    }

    func registerToggleOverlayHotkey(action: @escaping @MainActor () -> Void) {
        guard hotKeyRef == nil else {
            self.action = action
            return
        }

        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                let manager = Unmanaged<HotkeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                manager.handle(event: event)

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            state = .failed(handlerStatus)
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: OSType(fourCharacterCode: "IAHK"),
            id: 1
        )

        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if hotKeyStatus == noErr {
            state = .registered("Cmd + Shift + Space")
        } else {
            state = .failed(hotKeyStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        state = .idle
    }

    private func handle(event: EventRef?) {
        guard event != nil else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            Task { @MainActor in
                self?.action?()
            }
        }
    }
}

private extension OSType {
    init(fourCharacterCode: String) {
        precondition(fourCharacterCode.utf8.count == 4)

        self = fourCharacterCode.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}
