//
//  OverlayContentModel.swift
//  InterviewAssistant
//
//  Created by Codex on 20/08/2026.
//

import Foundation

@MainActor
final class OverlayContentModel: ObservableObject {
    @Published var title = "Overlay testowy"
    @Published var body = "Ten panel powinien byc widoczny nad innymi aplikacjami. Teraz sprawdzamy, jak zachowuje sie przy udostepnianiu ekranu."
    @Published var status = "Gotowe"
}
