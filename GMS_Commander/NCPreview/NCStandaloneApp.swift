#if NC_STANDALONE
import AppKit
import UniformTypeIdentifiers

@main
struct NCStandaloneApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = NCStandaloneDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class NCStandaloneDelegate: AppDelegate {
    override func applicationDidFinishLaunching(_ notification: Notification) {
        let applicationMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let commands = NSMenu()
        commands.addItem(withTitle: L.t("nc.standalone.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = commands
        applicationMenu.addItem(applicationItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L.t("nc.standalone.file"))
        let open = NSMenuItem(title: L.t("nc.standalone.open"), action: #selector(openDocument(_:)), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(open)
        fileItem.submenu = fileMenu
        applicationMenu.addItem(fileItem)
        NSApp.mainMenu = applicationMenu
        NSApp.activate(ignoringOtherApps: true)
        for path in CommandLine.arguments.dropFirst() where !path.hasPrefix("-") {
            NCExternalPreview.shared.open(URL(fileURLWithPath: path))
        }
    }

    @MainActor func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        let hasFileArgument = CommandLine.arguments.dropFirst().contains { !$0.hasPrefix("-") }
        if !hasFileArgument && !NCExternalPreview.shared.hasOpenWindows {
            openDocument(nil)
        }
        return true
    }

    @MainActor @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["nc", "gcode", "cnc"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { NCExternalPreview.shared.open(url) }
    }
}
#endif
