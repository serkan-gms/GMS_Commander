//
//  FileEditorSheet.swift
//  GMS_Commander
//
//  F4 dahili metin düzenleyici. İkili dosyalar metin olarak açılmaz; kaydetme
//  atomiktir ve dosya açıldıktan sonra dışarıdan değiştiyse kullanıcıya sorulur.
//

import SwiftUI
import AppKit

/// Düzenleyici görünüm modeli.
@MainActor
final class FileEditorViewModel: ObservableObject {
    let url: URL

    @Published var text = ""
    @Published var encoding: ViewerEncoding = .utf8
    @Published private(set) var originalText = ""
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var showLineNumbers = true

    /// Dosyanın açılışta okunan değiştirme tarihi.
    private var loadedModificationDate: Date?
    /// Dış değişiklik uyarısı gösterilsin mi?
    @Published var isConfirmingOverwrite = false

    let searchController = ViewerTextController()

    init(url: URL) {
        self.url = url
    }

    /// Kaydedilmemiş değişiklik var mı?
    var hasUnsavedChanges: Bool {
        !isLoading && text != originalText
    }

    /// Dosyayı yükler.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let url = self.url
        do {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard Int64(size) <= FileViewerService.maximumEditableBytes else {
                throw ViewerError.tooLarge(FileSizeFormatter.string(fromBytes: Int64(size)))
            }
            let document = try await Task.detached(priority: .userInitiated) {
                try FileViewerService().loadText(url: url)
            }.value
            guard !document.isBinary else {
                throw ViewerError.binaryFile
            }
            text = Self.trimmingBOM(document.text, encoding: document.encoding)
            originalText = text
            encoding = document.encoding
            loadedModificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Metni kaydeder.
    /// - Parameter force: Dış değişiklik uyarısına rağmen yazılsın mı?
    /// - Returns: Kaydetme başarılıysa `true`.
    @discardableResult
    func save(force: Bool = false) async -> Bool {
        guard !isSaving, !isLoading else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let text = self.text
        let url = self.url
        let encoding = self.encoding
        let expectedDate = force ? nil : loadedModificationDate

        do {
            try await Task.detached(priority: .userInitiated) {
                try FileViewerService.save(
                    text: text,
                    to: url,
                    encoding: encoding,
                    expectedModificationDate: expectedDate
                )
            }.value
            originalText = text
            loadedModificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            return true
        } catch ViewerError.fileChanged {
            isConfirmingOverwrite = true
            return false
        } catch {
            errorMessage = ErrorMessages.message(for: error)
            return false
        }
    }

    /// UTF-8 BOM'unu görünen metinden kaldırır.
    fileprivate static func trimmingBOM(_ text: String, encoding: ViewerEncoding) -> String {
        guard encoding == .utf8, text.hasPrefix("\u{FEFF}") else { return text }
        return String(text.dropFirst())
    }
}

/// F4 düzenleyici penceresi.
struct FileEditorSheet: View {
    @StateObject private var model: FileEditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingClose = false
    @State private var saveStatus = ""

    init(url: URL) {
        _model = StateObject(wrappedValue: FileEditorViewModel(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            toolbar
            Rectangle().fill(Theme.border).frame(height: 1)
            content
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 900, height: 680)
        .background(Theme.panel)
        .task { await model.load() }
        .interactiveDismissDisabled(model.hasUnsavedChanges)
        .onDisappear { model.searchController.clearSearch() }
        .confirmationDialog(
            L.t("editor.unsavedTitle"),
            isPresented: $isConfirmingClose,
            titleVisibility: .visible
        ) {
            Button(L.t("editor.discardAndClose"), role: .destructive) {
                dismiss()
            }
            Button(L.t("editor.saveAndClose")) {
                Task {
                    if await model.save() { dismiss() }
                }
            }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(L.t("editor.unsavedMessage"))
        }
        .alert(
            L.t("editor.fileChangedTitle"),
            isPresented: $model.isConfirmingOverwrite
        ) {
            Button(L.t("editor.overwriteAnyway"), role: .destructive) {
                Task {
                    if await model.save(force: true) {
                        saveStatus = L.t("editor.saved")
                    }
                }
            }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(L.t("editor.fileChangedMessage"))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.url.lastPathComponent)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if model.hasUnsavedChanges {
                        Text(L.t("editor.modified"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                Text(model.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.header)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text(L.t("editor.encoding"))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Picker("", selection: $model.encoding) {
                    ForEach(ViewerEncoding.allCases) { encoding in
                        Text(encoding.localizedName).tag(encoding)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                .help(L.t("editor.encodingHelp"))
            }

            Toggle(L.t("viewer.lineNumbers"), isOn: $model.showLineNumbers)
                .toggleStyle(.checkbox)

            Spacer()

            if model.errorMessage == nil {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary)
                    TextField(L.t("viewer.searchPlaceholder"), text: $searchQuery)
                        .textFieldStyle(.plain)
                        .frame(width: 180)
                        .onSubmit { _ = model.searchController.findNext() }
                        .onChange(of: searchQuery) { _, value in
                            _ = model.searchController.updateSearch(value)
                        }
                    Button { _ = model.searchController.findPrevious() } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    Button { _ = model.searchController.findNext() } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.header)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView(L.t("editor.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage, model.originalText.isEmpty, model.text.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.ellipsis")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ViewerTextView(
                text: $model.text,
                isEditable: true,
                showLineNumbers: model.showLineNumbers,
                controller: model.searchController
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(L.t("editor.stats", (model.text as NSString).length, lineCount))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer()
            if !saveStatus.isEmpty {
                Label(saveStatus, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if model.isSaving {
                ProgressView().controlSize(.small)
            }
            Button(L.t("common.close")) {
                if model.hasUnsavedChanges {
                    isConfirmingClose = true
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)

            Button(L.t("editor.save")) {
                Task {
                    if await model.save() {
                        saveStatus = L.t("editor.saved")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model.isLoading || model.isSaving)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.header)
    }

    private var lineCount: Int {
        guard !model.text.isEmpty else { return 0 }
        return model.text.components(separatedBy: "\n").count
    }

    @State private var searchQuery = ""
}
