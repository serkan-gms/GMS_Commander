//
//  GMS_CommanderApp.swift
//  GMS_Commander
//
//  Uygulama giriş noktası. SwiftUI yaşam döngüsü kullanılır;
//  AppKit köprüsü yalnızca Quick Look ve uygulama etkinleştirme içindir.
//

import SwiftUI
import AppKit

#if !NC_STANDALONE
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
                .commanderWindowBranding()
        }
    }
}
#endif

/// Uygulama yaşam döngüsü olaylarını karşılayan temsilci.
class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if NCFile.supports(url) {
                NCExternalPreview.shared.open(url)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NCExternalPreview.shared.open(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateCancel }
        guard NCExternalPreview.shared.hasPendingChanges else { return .terminateNow }
        terminationPending = true
        Task { @MainActor in
            let confirmed = await NCExternalPreview.shared.confirmTermination()
            terminationPending = false
            sender.reply(toApplicationShouldTerminate: confirmed)
        }
        return .terminateLater
    }
}
