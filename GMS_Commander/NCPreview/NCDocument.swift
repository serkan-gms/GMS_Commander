import SwiftUI
import AppKit

private enum NCDocumentError: LocalizedError {
    case tooLarge
    case missingModificationDate

    var errorDescription: String? {
        switch self {
        case .tooLarge: return L.t("nc.tooLarge")
        case .missingModificationDate: return L.t("nc.document.noDate")
        }
    }
}

@MainActor
final class NCDocument: ObservableObject {
    @Published var text = ""
    @Published private(set) var originalText = ""
    @Published private(set) var url: URL
    @Published private(set) var program: NCProgram?
    @Published private(set) var revision = UUID()
    @Published private(set) var loading = true
    @Published private(set) var loaded = false
    @Published private(set) var parsing = false
    @Published private(set) var saving = false
    @Published var error: String?
    @Published var selectedLine = 0
    let editor = NCCodeEditorController()

    private var encoding: ViewerEncoding = .utf8
    private var hasBOM = false
    private var modificationDate: Date?
    private var parseTask: Task<Void, Never>?

    init(url: URL) { self.url = url }
    var isModified: Bool { loaded && text != originalText }

    func load() async {
        do {
            let url = self.url
            let result = try await Task.detached(priority: .userInitiated) {
                let before = try NCDocument.modificationDate(url)
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let prefix = try handle.read(upToCount: 3) ?? Data()
                let document = try FileViewerService().loadText(url: url)
                guard !document.isBinary else { throw ViewerError.binaryFile }
                guard !document.isTruncated else { throw NCDocumentError.tooLarge }
                let date = try NCDocument.modificationDate(url)
                guard before == date else { throw ViewerError.fileChanged }
                return (document, date, ViewerEncoding.detect(from: prefix) != nil)
            }.value
            encoding = result.0.encoding
            hasBOM = result.2
            text = result.0.text.hasPrefix("\u{FEFF}") ? String(result.0.text.dropFirst()) : result.0.text
            originalText = text
            modificationDate = result.1
            loaded = true
            loading = false
            reparse()
        } catch {
            self.error = ErrorMessages.message(for: error)
            loading = false
        }
    }

    func reparse() {
        guard loaded && !loading else { return }
        parseTask?.cancel()
        parsing = true
        let snapshot = text
        parseTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                let worker = Task.detached(priority: .userInitiated) { NCParser.parse(snapshot) }
                let result = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, text == snapshot else { return }
                program = result
                revision = UUID()
                parsing = false
            } catch is CancellationError {
                return
            } catch {
                self.error = ErrorMessages.message(for: error)
                parsing = false
            }
        }
    }

    func cancel() {
        parseTask?.cancel()
    }

    nonisolated private static func modificationDate(_ url: URL) throws -> Date {
        guard let date = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date else {
            throw NCDocumentError.missingModificationDate
        }
        return date
    }

    nonisolated static func checkUnchanged(_ target: URL, expected: Date) throws {
        let current = try modificationDate(target)
        guard current == expected else { throw ViewerError.fileChanged }
    }

    func save(as newURL: URL? = nil, force: Bool = false) async -> Bool {
        guard loaded, !loading, !saving else { return false }
        saving = true
        defer { saving = false }
        let target = newURL ?? url
        let snapshot = text
        let encodedText = hasBOM ? "\u{FEFF}" + snapshot : snapshot
        let encoding = self.encoding
        let expected = newURL == nil && !force ? modificationDate : nil
        do {
            let date = try await Task.detached(priority: .userInitiated) {
                if let expected {
                    try NCDocument.checkUnchanged(target, expected: expected)
                }
                try FileViewerService.save(text: encodedText, to: target, encoding: encoding, expectedModificationDate: expected)
                return try NCDocument.modificationDate(target)
            }.value
            url = target
            originalText = snapshot
            modificationDate = date
            return true
        } catch ViewerError.fileChanged {
            let alert = NSAlert()
            alert.messageText = L.t("editor.fileChangedTitle")
            alert.informativeText = L.t("editor.fileChangedMessage")
            alert.addButton(withTitle: L.t("editor.overwriteAnyway"))
            alert.addButton(withTitle: L.t("common.cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                saving = false
                return await save(as: newURL, force: true)
            }
            return false
        } catch {
            self.error = ErrorMessages.message(for: error)
            return false
        }
    }

    func saveAs() async -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.directoryURL = NCPreviewSettings.saveDirectory(for: url, defaults: NCPreviewSettings.sharedDefaults)
        guard panel.runModal() == .OK, let target = panel.url else { return false }
        let succeeded: Bool
        if target.standardizedFileURL == url.standardizedFileURL {
            succeeded = await save()
        } else {
            succeeded = await save(as: target)
        }
        if succeeded {
            NCPreviewSettings.saveLastSaveDirectory(target.deletingLastPathComponent(), defaults: NCPreviewSettings.sharedDefaults)
        }
        return succeeded
    }
}
