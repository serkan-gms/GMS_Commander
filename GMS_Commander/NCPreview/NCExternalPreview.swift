import SwiftUI
import AppKit

@MainActor
final class NCExternalPreview: NSObject, NSWindowDelegate {
    static let shared = NCExternalPreview()
    private struct Entry {
        let window: NSWindow
        let document: NCDocument
        var onClose: [() -> Void]
    }
    private var windows: [ObjectIdentifier: Entry] = [:]

    var hasOpenWindows: Bool { !windows.isEmpty }

    var hasPendingChanges: Bool {
        windows.values.contains { $0.document.isModified || $0.document.saving }
    }

    func confirmTermination() async -> Bool {
        let entries = Array(windows.values)
        var discarded: [ObjectIdentifier: String] = [:]
        for entry in entries {
            let document = entry.document
            guard !document.saving else {
                let alert = NSAlert()
                alert.messageText = L.t("nc.document.saving")
                alert.runModal()
                return false
            }
            guard document.isModified else { continue }
            let alert = NSAlert()
            alert.messageText = L.t("editor.unsavedTitle")
            alert.informativeText = "\(document.url.lastPathComponent)\n\(L.t("editor.unsavedMessage"))"
            alert.addButton(withTitle: L.t("editor.saveAndClose"))
            alert.addButton(withTitle: L.t("editor.discardAndClose"))
            alert.addButton(withTitle: L.t("common.cancel"))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard await document.save(), !document.isModified else { return false }
            case .alertSecondButtonReturn:
                discarded[ObjectIdentifier(document)] = document.text
            default:
                return false
            }
        }
        let unchanged = windows.values.allSatisfy { entry in
            !entry.document.saving && (!entry.document.isModified ||
                discarded[ObjectIdentifier(entry.document)] == entry.document.text)
        }
        if !unchanged {
            let alert = NSAlert()
            alert.messageText = L.t("nc.tools.textChanged")
            alert.runModal()
        }
        return unchanged
    }

    func open(_ url: URL, onClose: (() -> Void)? = nil) {
        guard url.isFileURL, NCFile.supports(url) else {
            let alert = NSAlert()
            alert.messageText = L.t("nc.unsupportedTitle")
            alert.informativeText = L.t("nc.unsupportedFile")
            alert.runModal()
            return
        }
        let key = url.standardizedFileURL
        if var existing = windows.values.first(where: { $0.document.url.standardizedFileURL == key }) {
            if let onClose {
                existing.onClose.append(onClose)
                windows[ObjectIdentifier(existing.window)] = existing
            }
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 850, height: 600)
        window.title = url.lastPathComponent
        window.delegate = self
        let document = NCDocument(url: key)
        window.contentView = NSHostingView(rootView: NCPreviewView(document: document) { [weak window] in
            window?.performClose(nil)
        })
        windows[ObjectIdentifier(window)] = Entry(window: window, document: document, onClose: onClose.map { [$0] } ?? [])
        if let frame = NCPreviewSettings.savedWindowFrame(defaults: NCPreviewSettings.sharedDefaults),
           let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let width = min(frame.width, visible.width)
            let height = min(frame.height, visible.height)
            let x = min(max(frame.minX, visible.minX), visible.maxX - width)
            let y = min(max(frame.minY, visible.minY), visible.maxY - height)
            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let entry = windows[ObjectIdentifier(sender)] else { return true }
        guard !entry.document.saving else { return false }
        guard entry.document.isModified else { return true }
        let alert = NSAlert()
        alert.messageText = L.t("editor.unsavedTitle")
        alert.informativeText = L.t("editor.unsavedMessage")
        alert.addButton(withTitle: L.t("editor.saveAndClose"))
        alert.addButton(withTitle: L.t("editor.discardAndClose"))
        alert.addButton(withTitle: L.t("common.cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                if await entry.document.save() { sender.performClose(nil) }
            }
            return false
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let entry = windows.removeValue(forKey: ObjectIdentifier(window)) else { return }
        NCPreviewSettings.saveWindowFrame(window.frame, defaults: NCPreviewSettings.sharedDefaults)
        entry.document.cancel()
        entry.onClose.forEach { $0() }
    }
}
