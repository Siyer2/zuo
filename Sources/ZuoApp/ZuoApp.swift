import AppBundle
import SwiftUI

// This file is shared between SPM and xcode project

@main
struct ZuoApp: App {
    @StateObject var viewModel = TrayMenuModel.shared
    @StateObject var messageModel = MessageModel.shared
    @StateObject var settingsViewModel = SettingsViewModel.shared
    @Environment(\.openWindow) var openWindow: OpenWindowAction

    init() {
        initAppBundle()
    }

    var body: some Scene {
        menuBar(viewModel: viewModel)
        getMessageWindow(messageModel: messageModel)
            .onChange(of: messageModel.message) { message in
                if message != nil {
                    openWindow(id: messageWindowId)
                }
            }
        getSettingsWindow(viewModel: settingsViewModel)
            .onChange(of: settingsViewModel.isSettingsOpen) { isOpen in
                if isOpen {
                    openWindow(id: settingsWindowId)
                    settingsViewModel.isSettingsOpen = false
                }
            }
    }
}
