//
//  GMS_CommanderApp.swift
//  GMS_Commander
//
//  Uygulama giriş noktası. SwiftUI yaşam döngüsü kullanılır;
//  AppKit köprüsü yalnızca Quick Look ve uygulama etkinleştirme içindir.
//

import SwiftUI
import AppKit

@main
struct GMSCommanderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var settings: SettingsStore
    @StateObject private var viewModel: MainViewModel
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var favorites = FavoritesViewModel.shared

    init() {
        let store = SettingsStore()
        _settings = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: MainViewModel(settings: store))
    }

    var body: some Scene {
        WindowGroup(L.t("app.name")) {
            MainWindowView(viewModel: viewModel, settings: settings)
                .environmentObject(theme)
                .environmentObject(favorites)
                .preferredColorScheme(theme.themeID.isLight ? .light : .dark)
        }
        .defaultSize(width: 1400, height: 820)
        .commands {
            CommanderCommands(viewModel: viewModel, settings: settings)
        }

        Settings {
            SettingsView(settings: settings)
                .environmentObject(theme)
                .environmentObject(favorites)
        }
    }
}

/// Uygulama yaşam döngüsü olaylarını karşılayan temsilci.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
