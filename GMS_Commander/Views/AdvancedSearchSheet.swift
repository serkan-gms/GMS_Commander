//
//  AdvancedSearchSheet.swift
//  GMS_Commander
//
//  Gelişmiş arama penceresi: ad, uzantı, boyut, tarih, içerik ve dışlama
//  ölçütleriyle alt klasörleri tarar. Arama arka planda çalışır, iptal
//  edilebilir ve sonuçlar CSV olarak dışa aktarılabilir.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Boyut birimi

/// Arama formundaki boyut birimi.
enum SearchSizeUnit: String, CaseIterable, Identifiable {
    case kilobytes
    case megabytes
    case gigabytes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kilobytes: return "KB"
        case .megabytes: return "MB"
        case .gigabytes: return "GB"
        }
    }

    var multiplier: Int64 {
        switch self {
        case .kilobytes: return 1024
        case .megabytes: return 1024 * 1024
        case .gigabytes: return 1024 * 1024 * 1024
        }
    }
}

// MARK: - Görünüm modeli

/// Gelişmiş arama penceresinin durumu.
@MainActor
final class AdvancedSearchViewModel: ObservableObject {
    /// Aramanın başladığı klasör.
    let root: URL

    @Published var nameQuery = ""
    @Published var useRegex = false
    @Published var extensionsText = ""
    @Published var excludeText = ""
    @Published var includeFiles = true
    @Published var includeFolders = false
    @Published var includeHidden = false
    @Published var recursive = true
    @Published var minimumSizeText = ""
    @Published var maximumSizeText = ""
    @Published var sizeUnit: SearchSizeUnit = .megabytes
    @Published var useModifiedAfter = false
    @Published var useModifiedBefore = false
    @Published var modifiedAfter = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var modifiedBefore = Date()
    @Published var contentQuery = ""

    @Published private(set) var results: [FileItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var reachedLimit = false
    @Published private(set) var skippedCount = 0
    @Published private(set) var wasCancelled = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var selection: Set<URL> = []

    /// Son çalıştırılan ölçütler (şablon olarak yeniden kullanılabilir).
    private(set) var lastCriteria: SearchCriteria?

    private let service = FileSearchService()
    private var cancellation: SearchCancellation?
    private var searchTask: Task<Void, Never>?

    /// Gelişmiş aramada döndürülecek en fazla sonuç.
    static let resultLimit = 5000

    init(root: URL) {
        self.root = root
    }

    /// Formdaki değerlerle aramayı başlatır.
    func start() {
        guard !isSearching else { return }
        errorMessage = nil
        statusMessage = nil
        wasCancelled = false

        guard let criteria = makeCriteria() else { return }
        lastCriteria = criteria

        results = []
        selection = []
        reachedLimit = false
        skippedCount = 0
        isSearching = true

        let cancellation = SearchCancellation()
        self.cancellation = cancellation
        let started = Date()
        let root = self.root

        searchTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.service.search(
                root: root,
                criteria: criteria,
                limit: Self.resultLimit,
                cancellation: cancellation
            )
            self.finish(outcome, started: started)
        }
    }

    /// Süren aramayı iptal eder.
    func cancel() {
        cancellation?.cancel()
    }

    /// Formu varsayılan değerlere döndürür.
    func reset() {
        nameQuery = ""
        useRegex = false
        extensionsText = ""
        excludeText = ""
        includeFiles = true
        includeFolders = false
        includeHidden = false
        recursive = true
        minimumSizeText = ""
        maximumSizeText = ""
        sizeUnit = .megabytes
        useModifiedAfter = false
        useModifiedBefore = false
        contentQuery = ""
        errorMessage = nil
        statusMessage = nil
    }

    /// Sonuçları UTF-8 CSV dosyasına yazar.
    /// - Parameter url: Hedef dosya.
    func exportCSV(to url: URL) throws {
        var lines = ["Ad;Konum;Boyut (bayt);Değiştirilme Tarihi"]
        for item in results {
            let location = item.relativePath ?? item.url.deletingLastPathComponent().path
            let date = item.modificationDate.map { DateFormatterHelper.detailedString(from: $0) } ?? ""
            let fields = [item.name, location, String(item.size), date]
            lines.append(fields.map(Self.csvField).joined(separator: ";"))
        }
        let content = "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// CSV alanını gerektiğinde tırnak içine alır.
    private static func csvField(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Yardımcılar

    private func finish(_ outcome: SearchOutcome, started: Date) {
        isSearching = false
        cancellation = nil
        searchTask = nil
        elapsed = Date().timeIntervalSince(started)
        results = outcome.items
        reachedLimit = outcome.reachedLimit
        skippedCount = outcome.skippedCount
        wasCancelled = outcome.wasCancelled

        if outcome.wasCancelled {
            statusMessage = L.t("search.cancelled")
        } else if outcome.items.isEmpty {
            statusMessage = L.t("search.noResults")
        } else {
            statusMessage = nil
        }
    }

    /// Form değerlerinden ölçüt üretir; doğrulama başarısızsa hata gösterir.
    private func makeCriteria() -> SearchCriteria? {
        var criteria = SearchCriteria()
        criteria.nameQuery = nameQuery
        criteria.useRegex = useRegex
        criteria.contentQuery = contentQuery
        criteria.extensions = Self.parseList(extensionsText).map {
            $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }
        criteria.excludePatterns = Self.parseList(excludeText, separators: [",", ";", "\n"])
        criteria.includeFiles = includeFiles
        criteria.includeFolders = includeFolders
        criteria.includeHidden = includeHidden
        criteria.recursive = recursive

        guard !criteria.isEmpty else {
            errorMessage = L.t("search.emptyCriteria")
            return nil
        }
        guard criteria.includeFiles || criteria.includeFolders else {
            errorMessage = L.t("search.noTypes")
            return nil
        }

        if useRegex {
            let patterns = [criteria.nameQuery, criteria.contentQuery].filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            for pattern in patterns {
                if (try? NSRegularExpression(pattern: pattern)) == nil {
                    errorMessage = L.t("search.invalidRegex", pattern)
                    return nil
                }
            }
        }

        if !minimumSizeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = parseSize(minimumSizeText) else {
                errorMessage = L.t("search.invalidSize")
                return nil
            }
            criteria.minimumSize = value
        }
        if !maximumSizeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = parseSize(maximumSizeText) else {
                errorMessage = L.t("search.invalidSize")
                return nil
            }
            criteria.maximumSize = value
        }
        if let minimum = criteria.minimumSize,
           let maximum = criteria.maximumSize,
           minimum > maximum {
            errorMessage = L.t("search.invalidSizeRange")
            return nil
        }

        if useModifiedAfter {
            criteria.modifiedAfter = modifiedAfter
        }
        if useModifiedBefore {
            criteria.modifiedBefore = modifiedBefore
        }

        return criteria
    }

    private func parseSize(_ text: String) -> Int64? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0, value.isFinite else { return nil }
        let bytes = value * Double(sizeUnit.multiplier)
        guard bytes <= Double(Int64.max) else { return nil }
        return Int64(bytes)
    }

    /// Virgülle ayrılmış listeyi temizler.
    private static func parseList(
        _ text: String,
        separators: [Character] = [",", " ", ";"]
    ) -> [String] {
        text.split(whereSeparator: { separators.contains($0) || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Pencere

/// Gelişmiş arama penceresi.
struct AdvancedSearchSheet: View {
    @StateObject private var model: AdvancedSearchViewModel
    @Environment(\.dismiss) private var dismiss

    /// Sonuç, ana panelde gösterilmek üzere ana modele iletilir.
    private let onReveal: (FileItem) -> Void

    init(root: URL, onReveal: @escaping (FileItem) -> Void) {
        _model = StateObject(wrappedValue: AdvancedSearchViewModel(root: root))
        self.onReveal = onReveal
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            criteriaForm
            Rectangle().fill(Theme.border).frame(height: 1)
            resultsArea
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 940, height: 720)
        .background(Theme.panel)
        .onDisappear { model.cancel() }
    }

    // MARK: Başlık

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("search.advanced.title"))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t("search.root", model.root.path))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
                Text(L.t("search.searching"))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Button(L.t("common.close")) {
                model.cancel()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(12)
        .background(Theme.header)
    }

    // MARK: Ölçütler

    private var criteriaForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                formLabel(L.t("search.criteria.name"))
                TextField(L.t("search.criteria.namePlaceholder"), text: $model.nameQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.start() }
                Toggle(L.t("search.criteria.regex"), isOn: $model.useRegex)
                    .toggleStyle(.checkbox)
                    .help(L.t("search.criteria.regexHelp"))
            }

            HStack(spacing: 8) {
                formLabel(L.t("search.criteria.extensions"))
                TextField(L.t("search.criteria.extensionsPlaceholder"), text: $model.extensionsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                formLabel(L.t("search.criteria.exclude"))
                TextField(L.t("search.criteria.excludePlaceholder"), text: $model.excludeText)
                    .textFieldStyle(.roundedBorder)
                Toggle(L.t("search.criteria.hidden"), isOn: $model.includeHidden)
                    .toggleStyle(.checkbox)
            }

            HStack(spacing: 14) {
                Toggle(L.t("search.criteria.files"), isOn: $model.includeFiles)
                    .toggleStyle(.checkbox)
                Toggle(L.t("search.criteria.folders"), isOn: $model.includeFolders)
                    .toggleStyle(.checkbox)
                Toggle(L.t("search.criteria.recursive"), isOn: $model.recursive)
                    .toggleStyle(.checkbox)
                Spacer()
            }

            HStack(spacing: 8) {
                formLabel(L.t("search.criteria.size"))
                TextField(L.t("search.criteria.minimum"), text: $model.minimumSizeText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("–").foregroundStyle(Theme.textSecondary)
                TextField(L.t("search.criteria.maximum"), text: $model.maximumSizeText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Picker("", selection: $model.sizeUnit) {
                    ForEach(SearchSizeUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 70)

                Spacer(minLength: 16)
            }

            HStack(spacing: 8) {
                formLabel(L.t("search.criteria.date"))
                Toggle(L.t("search.criteria.after"), isOn: $model.useModifiedAfter)
                    .toggleStyle(.checkbox)
                DatePicker("", selection: $model.modifiedAfter, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!model.useModifiedAfter)
                    .frame(width: 140)

                Toggle(L.t("search.criteria.before"), isOn: $model.useModifiedBefore)
                    .toggleStyle(.checkbox)
                DatePicker("", selection: $model.modifiedBefore, displayedComponents: .date)
                    .labelsHidden()
                    .disabled(!model.useModifiedBefore)
                    .frame(width: 140)
                Spacer()
            }

            HStack(spacing: 8) {
                formLabel(L.t("search.criteria.content"))
                TextField(L.t("search.criteria.contentPlaceholder"), text: $model.contentQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.start() }
                Text(L.t("search.criteria.contentNote"))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                Spacer()
                Button(L.t("search.reset")) {
                    model.reset()
                }
                .disabled(model.isSearching)
                if model.isSearching {
                    Button(L.t("search.stop")) {
                        model.cancel()
                    }
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button(L.t("search.start")) {
                        model.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.includeFiles && !model.includeFolders)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.header)
    }

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 74, alignment: .trailing)
    }

    // MARK: Sonuçlar

    private var resultsArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L.t("search.results", model.results.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let status = model.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if model.isSearching {
                    Text(L.t("search.scanning"))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if model.reachedLimit {
                    Label(L.t("search.limitReached", AdvancedSearchViewModel.resultLimit), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if model.skippedCount > 0 {
                    Text(L.t("search.skipped", model.skippedCount))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if !model.results.isEmpty {
                    Text(L.t("search.elapsed", model.elapsed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.header)

            if model.results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: model.isSearching ? "magnifyingglass" : "doc.text.magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.textSecondary)
                    Text(model.isSearching ? L.t("search.searching") : (model.statusMessage ?? L.t("search.prompt")))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.field)
            } else {
                resultsTable
            }
        }
    }

    private var resultsTable: some View {
        Table(model.results, selection: $model.selection) {
            TableColumn(L.t("column.name")) { item in
                HStack(spacing: 6) {
                    Image(nsImage: FileIconProvider.icon(for: item))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 180, ideal: 260)

            TableColumn(L.t("search.column.location")) { item in
                Text(item.relativePath ?? item.url.deletingLastPathComponent().path)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 160, ideal: 300)

            TableColumn(L.t("column.size")) { item in
                Text(item.isDirectory ? "—" : FileSizeFormatter.string(fromBytes: item.size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn(L.t("column.date")) { item in
                Text(item.modificationDate.map { DateFormatterHelper.listString(from: $0) } ?? "—")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .width(min: 110, ideal: 140)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            if let url = urls.first, let item = item(for: url) {
                Button(L.t("search.open")) { open(item) }
                Button(L.t("search.reveal")) { reveal(item) }
                Divider()
                Button(L.t("search.copyPath")) { copyPath(item) }
            }
        } primaryAction: { urls in
            if let url = urls.first, let item = item(for: url) {
                open(item)
            }
        }
    }

    // MARK: Altlık

    private var footer: some View {
        HStack(spacing: 8) {
            if let item = selectedItem {
                Text(item.url.path)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(L.t("search.export")) { exportResults() }
                .disabled(model.results.isEmpty)
            Button(L.t("search.reveal")) {
                if let item = selectedItem { reveal(item) }
            }
            .disabled(selectedItem == nil)
            Button(L.t("search.open")) {
                if let item = selectedItem { open(item) }
            }
            .disabled(selectedItem == nil)
            Button(L.t("common.close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.header)
    }

    // MARK: İşlemler

    private var selectedItem: FileItem? {
        guard let url = model.selection.first else { return nil }
        return item(for: url)
    }

    private func item(for url: URL) -> FileItem? {
        model.results.first { $0.url == url }
    }

    /// Klasörleri panelde açar, dosyaları varsayılan uygulamayla açar.
    private func open(_ item: FileItem) {
        if item.isDirectory {
            reveal(item)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Öğeyi ana panelde gösterir ve pencereyi kapatır.
    private func reveal(_ item: FileItem) {
        onReveal(item)
        dismiss()
    }

    private func copyPath(_ item: FileItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
    }

    /// Sonuçları CSV olarak dışa aktarır.
    private func exportResults() {
        let panel = NSSavePanel()
        panel.title = L.t("search.export")
        panel.nameFieldStringValue = L.t("search.exportFileName")
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportCSV(to: url)
            model.statusMessage = L.t("search.exportDone", url.lastPathComponent)
        } catch {
            model.errorMessage = L.t("search.exportFailed", error.localizedDescription)
        }
    }
}
