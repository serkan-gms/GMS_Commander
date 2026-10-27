//
//  FileViewerSheet.swift
//  GMS_Commander
//
//  F3 dahili görüntüleyici: metin, hex, görsel ve PDF içerikleri gösterir.
//  Büyük dosyalar sınırlı okunur ve bu durum kullanıcıya bildirilir.
//

import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - Görünüm modeli

/// Görüntüleyici görünüm modu.
enum ViewerMode: String, CaseIterable, Identifiable {
    case text
    case hex

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .text: return L.t("viewer.mode.text")
        case .hex: return L.t("viewer.mode.hex")
        }
    }
}

/// F3 görüntüleyicisinin durumu.
@MainActor
final class FileViewerViewModel: ObservableObject {
    /// Gösterilen dosya.
    let url: URL

    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingHex = false
    @Published var mode: ViewerMode = .text
    @Published var encoding: ViewerEncoding = .utf8
    @Published var viewerText = ""
    @Published var hexText = ""
    @Published private(set) var document: ViewerDocument?
    @Published private(set) var image: NSImage?
    @Published private(set) var isPDF = false
    @Published var errorMessage: String?
    @Published var showLineNumbers = true

    /// Metin arama denetleyicisi.
    let searchController = ViewerTextController()

    private let service = FileViewerService()

    init(url: URL) {
        self.url = url
    }

    /// Dosyanın türüne göre içeriği yükler.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let fileExtension = url.pathExtension.lowercased()
        let contentType = UTType(filenameExtension: fileExtension)
        let isImageType = contentType?.conforms(to: .image) == true
        let isPDFType = contentType?.conforms(to: .pdf) == true || fileExtension == "pdf"
        let url = self.url

        if isImageType || isPDFType {
            if isPDFType {
                isPDF = true
                mode = .text
                return
            }
            let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                guard size <= 120 * 1024 * 1024 else { return nil }
                return try? Data(contentsOf: url, options: .mappedIfSafe)
            }.value
            if let data, let decoded = NSImage(data: data) {
                image = decoded
            } else {
                errorMessage = L.t("viewer.imageFailed")
            }
            return
        }

        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try FileViewerService().loadText(url: url)
            }.value
            self.document = document
            self.encoding = document.encoding
            self.viewerText = document.text
            self.showLineNumbers = !document.isBinary
            self.mode = document.isBinary ? .hex : .text
            if document.isBinary {
                await loadHex()
            }
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Seçilen kodlamayla metni yeniden yükler.
    func reloadWithEncoding() async {
        guard !isPDF, image == nil else { return }
        errorMessage = nil
        let encoding = self.encoding
        let url = self.url
        do {
            let document = try await Task.detached(priority: .userInitiated) {
                try FileViewerService().loadText(url: url, encoding: encoding)
            }.value
            self.document = document
            self.viewerText = Self.trimmingBOM(document.text, encoding: document.encoding)
            self.mode = .text
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Hex görünümüne geçer ve içeriği yükler.
    func switchToHex() {
        mode = .hex
        guard hexText.isEmpty else { return }
        Task { await loadHex() }
    }

    /// Hex içeriğini yükler.
    func loadHex() async {
        guard !isLoadingHex else { return }
        isLoadingHex = true
        defer { isLoadingHex = false }
        let url = self.url
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try FileViewerService().hexDump(url: url)
            }.value
            hexText = result.text
            if let current = document {
                document = ViewerDocument(
                    text: current.text,
                    encoding: current.encoding,
                    isTruncated: current.isTruncated,
                    byteCount: result.byteCount,
                    isBinary: current.isBinary
                )
            } else {
                document = ViewerDocument(
                    text: "",
                    encoding: .utf8,
                    isTruncated: result.isTruncated,
                    byteCount: result.byteCount,
                    isBinary: true
                )
            }
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// UTF-8 BOM'unu görünen metinden kaldırır.
    private static func trimmingBOM(_ text: String, encoding: ViewerEncoding) -> String {
        guard encoding == .utf8, text.hasPrefix("\u{FEFF}") else { return text }
        return String(text.dropFirst())
    }
}

// MARK: - Pencere

/// F3 görüntüleyici penceresi.
struct FileViewerSheet: View {
    @StateObject private var model: FileViewerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchStatus = ""

    init(url: URL) {
        _model = StateObject(wrappedValue: FileViewerViewModel(url: url))
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
        .frame(minWidth: 720, idealWidth: 900, minHeight: 520, idealHeight: 680)
        .background(Theme.panel)
        .background(
            WindowAccessor { window in
                SheetWindowConfiguration.makeResizable(
                    window,
                    minimumContentSize: NSSize(width: 720, height: 520)
                )
            }
        )
        .task { await model.load() }
        .onDisappear { model.searchController.clearSearch() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.url.lastPathComponent)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(L.t("viewer.quickLook")) {
                QuickLookCoordinator.shared.show([model.url])
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Theme.header)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if model.image == nil, !model.isPDF {
                Picker("", selection: $model.mode) {
                    ForEach(ViewerMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
                .onChange(of: model.mode) { _, newValue in
                    if newValue == .hex { model.switchToHex() }
                }

                HStack(spacing: 4) {
                    Text(L.t("viewer.encoding"))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Picker("", selection: $model.encoding) {
                        ForEach(ViewerEncoding.allCases) { encoding in
                            Text(encoding.localizedName).tag(encoding)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    .disabled(model.mode == .hex)
                    .onChange(of: model.encoding) { _, _ in
                        Task { await model.reloadWithEncoding() }
                    }
                }

                Toggle(L.t("viewer.lineNumbers"), isOn: $model.showLineNumbers)
                    .toggleStyle(.checkbox)
                    .disabled(model.mode == .hex)
            }

            Spacer()

            if model.mode == .text, model.image == nil, !model.isPDF {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary)
                    TextField(L.t("viewer.searchPlaceholder"), text: $searchQuery)
                        .textFieldStyle(.plain)
                        .frame(width: 180)
                        .onSubmit { findNext() }
                        .onChange(of: searchQuery) { _, value in
                            let count = model.searchController.updateSearch(value)
                            searchStatus = count == 0
                                ? (value.isEmpty ? "" : L.t("viewer.noMatch"))
                                : L.t("viewer.matchCount", count)
                        }
                    Button {
                        findPrevious()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .help(L.t("viewer.previousMatch"))
                    Button {
                        findNext()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .help(L.t("viewer.nextMatch"))
                    Text(searchStatus)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minWidth: 54, alignment: .leading)
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
            ProgressView(L.t("viewer.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage, model.document == nil, model.image == nil, !model.isPDF {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let image = model.image {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 1200, maxHeight: 1200)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isPDF {
            PDFKitView(url: model.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.mode == .hex {
            if model.isLoadingHex {
                ProgressView(L.t("viewer.loadingHex"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ViewerTextView(
                    text: $model.hexText,
                    isEditable: false,
                    showLineNumbers: false,
                    controller: model.searchController
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ViewerTextView(
                text: $model.viewerText,
                isEditable: false,
                showLineNumbers: model.showLineNumbers,
                controller: model.searchController
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let document = model.document {
                Text(FileSizeFormatter.string(fromBytes: document.byteCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                if document.isTruncated {
                    Label(
                        L.t("viewer.truncated", FileSizeFormatter.string(fromBytes: Int64(FileViewerService.maximumPreviewBytes))),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if document.isBinary {
                    Text(L.t("viewer.binary"))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Button(L.t("common.close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.header)
    }

    private var headerIcon: String {
        if model.image != nil { return "photo" }
        if model.isPDF { return "doc.richtext" }
        return model.mode == .hex ? "number" : "doc.text.magnifyingglass"
    }

    private var subtitle: String {
        if model.isPDF { return L.t("viewer.pdfDocument") }
        if model.image != nil { return L.t("viewer.imageDocument") }
        if let document = model.document {
            return L.t("viewer.encodingSubtitle", document.encoding.localizedName)
        }
        return model.url.path
    }

    private func findNext() {
        let position = model.searchController.findNext()
        if model.searchController.matchCount > 0 {
            searchStatus = L.t("viewer.matchPosition", position, model.searchController.matchCount)
        }
    }

    private func findPrevious() {
        let position = model.searchController.findPrevious()
        if model.searchController.matchCount > 0 {
            searchStatus = L.t("viewer.matchPosition", position, model.searchController.matchCount)
        }
    }
}

// MARK: - PDF görünümü

/// PDFKit tabanlı salt okunur PDF görünümü.
struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = Palette.panel
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}
}
