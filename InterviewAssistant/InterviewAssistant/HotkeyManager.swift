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
        case registered([String])
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                "Skroty nieaktywne"
            case .registered(let shortcuts):
                "Skroty aktywne: \(shortcuts.joined(separator: ", "))"
            case .failed(let message):
                "Nie udalo sie zarejestrowac skrotu: \(message)"
            }
        }
    }

    @Published private(set) var state: RegistrationState = .idle

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var shortcutLabels: [UInt32: String] = [:]

    deinit {
        unregister()
    }

    func registerDefaultHotkeys(
        toggleOverlay: @escaping @MainActor () -> Void,
        captureCode: @escaping @MainActor () -> Void
    ) {
        registerHotkey(
            id: 1,
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey),
            label: "Cmd + Shift + Space",
            action: toggleOverlay
        )

        registerHotkey(
            id: 2,
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(cmdKey | shiftKey),
            label: "Cmd + Shift + C",
            action: captureCode
        )
    }

    func registerHotkey(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        label: String,
        action: @escaping @MainActor () -> Void
    ) {
        installEventHandlerIfNeeded()
        actions[id] = action

        let hotKeyID = EventHotKeyID(
            signature: OSType(fourCharacterCode: "IAHK"),
            id: id
        )

        var hotKeyRef: EventHotKeyRef?
        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if hotKeyStatus == noErr, let hotKeyRef {
            hotKeyRefs[id] = hotKeyRef
            shortcutLabels[id] = label
            state = .registered(shortcutLabels.keys.sorted().compactMap { shortcutLabels[$0] })
        } else {
            state = .failed("\(label), OSStatus \(hotKeyStatus)")
        }
    }

    func unregister() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRefs.removeAll()
        actions.removeAll()
        shortcutLabels.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        state = .idle
    }

    private func handle(event: EventRef?) {
        guard let event else {
            return
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            Task { @MainActor in
                self?.actions[hotKeyID.id]?()
            }
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

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

        if handlerStatus != noErr {
            state = .failed("handler, OSStatus \(handlerStatus)")
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
