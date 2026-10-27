//
//  FolderCompareSheet.swift
//  GMS_Commander
//
//  İki panelin klasörlerini ad, boyut, tarih ve isteğe bağlı SHA-256
//  içeriğine göre karşılaştıran salt okunur rapor penceresi.
//  Hiçbir dosya kopyalanmaz, taşınmaz veya silinmez.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Süzgeç

/// Karşılaştırma sonuçlarının süzgeci.
enum CompareFilter: String, CaseIterable, Identifiable {
    case all
    case differences
    case onlyLeft
    case onlyRight
    case identical

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .all: return L.t("compare.filter.all")
        case .differences: return L.t("compare.filter.differences")
        case .onlyLeft: return L.t("compare.filter.onlyLeft")
        case .onlyRight: return L.t("compare.filter.onlyRight")
        case .identical: return L.t("compare.filter.identical")
        }
    }

    /// Satırın süzgece uyup uymadığı.
    func matches(_ entry: CompareEntry) -> Bool {
        switch self {
        case .all: return true
        case .differences: return entry.status.isDifference
        case .onlyLeft: return entry.status == .onlyLeft
        case .onlyRight: return entry.status == .onlyRight
        case .identical: return entry.status == .identical
        }
    }
}

// MARK: - Görünüm modeli

/// Klasör karşılaştırma penceresinin durumu.
@MainActor
final class FolderCompareViewModel: ObservableObject {
    let leftRoot: URL
    let rightRoot: URL

    @Published var options = CompareOptions()
    @Published var filter: CompareFilter = .differences
    @Published private(set) var entries: [CompareEntry] = []
    @Published private(set) var outcome: CompareOutcome?
    @Published private(set) var isComparing = false
    @Published private(set) var scannedCount = 0
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var selection: Set<String> = []

    private let service = FolderCompareService()
    private var control: TransferControl?

    init(leftRoot: URL, rightRoot: URL) {
        self.leftRoot = leftRoot
        self.rightRoot = rightRoot
    }

    /// Süzgeçten geçen satırlar.
    var filteredEntries: [CompareEntry] {
        entries.filter { filter.matches($0) }
    }

    /// Karşılaştırmayı başlatır.
    func start() {
        guard !isComparing else { return }
        errorMessage = nil
        statusMessage = nil
        entries = []
        selection = []
        outcome = nil
        scannedCount = 0
        isComparing = true

        let control = TransferControl()
        self.control = control
        let options = self.options
        let left = leftRoot
        let right = rightRoot

        Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.service.compare(
                    left: left,
                    right: right,
                    options: options,
                    control: control,
                    progress: { [weak self] count in
                        Task { @MainActor in
                            self?.scannedCount = count
                        }
                    }
                )
                self.outcome = outcome
                self.entries = outcome.entries
                if outcome.wasCancelled {
                    self.statusMessage = L.t("compare.cancelled")
                } else if outcome.differenceCount == 0 {
                    self.statusMessage = L.t("compare.noDifferences")
                }
            } catch is CancellationError {
                self.statusMessage = L.t("compare.cancelled")
            } catch {
                self.errorMessage = ErrorMessages.message(for: error)
            }
            self.isComparing = false
            self.control = nil
        }
    }

    /// Süren karşılaştırmayı iptal eder.
    func cancel() {
        control?.cancel()
    }

    /// Sonuçları CSV olarak dışa aktarır.
    /// - Parameter url: Hedef dosya.
    func exportCSV(to url: URL) throws {
        var lines = [
            "Göreli Yol;Durum;Sol Var;Sağ Var;Sol Boyut;Sağ Boyut;Sol Tarih;Sağ Tarih"
        ]
        for entry in filteredEntries {
            let fields = [
                entry.relativePath,
                entry.status.localizedName,
                entry.leftExists ? "evet" : "hayır",
                entry.rightExists ? "evet" : "hayır",
                entry.leftSize.map(String.init) ?? "",
                entry.rightSize.map(String.init) ?? "",
                entry.leftDate.map { DateFormatterHelper.detailedString(from: $0) } ?? "",
                entry.rightDate.map { DateFormatterHelper.detailedString(from: $0) } ?? ""
            ]
            lines.append(fields.map(Self.csvField).joined(separator: ";"))
        }
        let content = "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

// MARK: - Pencere

/// Klasör karşılaştırma penceresi.
struct FolderCompareSheet: View {
    @StateObject private var model: FolderCompareViewModel
    @Environment(\.dismiss) private var dismiss

    /// Seçilen öğeyi ilgili panelde gösterir.
    private let onReveal: (URL, PanelSide) -> Void

    init(
        leftRoot: URL,
        rightRoot: URL,
        onReveal: @escaping (URL, PanelSide) -> Void
    ) {
        _model = StateObject(
            wrappedValue: FolderCompareViewModel(leftRoot: leftRoot, rightRoot: rightRoot)
        )
        self.onReveal = onReveal
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            optionsBar
            Rectangle().fill(Theme.border).frame(height: 1)
            summaryBar
            Rectangle().fill(Theme.border).frame(height: 1)
            resultsArea
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 1020, height: 720)
        .background(Theme.panel)
        .onDisappear { model.cancel() }
    }

    // MARK: Başlık

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("compare.title"))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 4) {
                    Text(L.t("compare.leftRoot", model.leftRoot.path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.left.and.right")
                    Text(L.t("compare.rightRoot", model.rightRoot.path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if model.isComparing {
                ProgressView().controlSize(.small)
                Text(L.t("compare.scanning", model.scannedCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Button(L.t("compare.cancel")) { model.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button(L.t("compare.start")) { model.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
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

    // MARK: Seçenekler

    private var optionsBar: some View {
        HStack(spacing: 14) {
            Toggle(L.t("compare.option.size"), isOn: $model.options.compareSize)
                .toggleStyle(.checkbox)
            Toggle(L.t("compare.option.date"), isOn: $model.options.compareDate)
                .toggleStyle(.checkbox)
            Toggle(L.t("compare.option.content"), isOn: $model.options.compareContent)
                .toggleStyle(.checkbox)
                .help(L.t("compare.option.contentHelp"))
            Toggle(L.t("compare.option.hidden"), isOn: $model.options.includeHidden)
                .toggleStyle(.checkbox)
            Toggle(L.t("compare.option.recursive"), isOn: $model.options.recursive)
                .toggleStyle(.checkbox)
            Spacer()
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.header)
        .disabled(model.isComparing)
    }

    // MARK: Özet

    private var summaryBar: some View {
        HStack(spacing: 8) {
            if let outcome = model.outcome {
                summaryChip(.identical, count: outcome.count(of: .identical))
                summaryChip(.differentSize, count: outcome.count(of: .differentSize))
                summaryChip(.differentDate, count: outcome.count(of: .differentDate))
                summaryChip(.differentContent, count: outcome.count(of: .differentContent))
                summaryChip(.onlyLeft, count: outcome.count(of: .onlyLeft))
                summaryChip(.onlyRight, count: outcome.count(of: .onlyRight))
                summaryChip(.typeMismatch, count: outcome.count(of: .typeMismatch))
                if outcome.skippedCount > 0 {
                    Text(L.t("compare.skipped", outcome.skippedCount))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(L.t("compare.duration", outcome.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(model.isComparing ? L.t("compare.scanningSimple") : L.t("compare.prompt"))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Picker("", selection: $model.filter) {
                ForEach(CompareFilter.allCases) { filter in
                    Text(filter.localizedName).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 190)
            .disabled(model.entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.header)
    }

    private func summaryChip(_ status: CompareStatus, count: Int) -> some View {
        Button {
            model.filter = filter(for: status)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: status.systemImage)
                Text(status.localizedName)
                Text("\(count)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(color(for: status))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color(for: status).opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(L.t("compare.filterBy", status.localizedName))
    }

    private func filter(for status: CompareStatus) -> CompareFilter {
        switch status {
        case .identical: return .identical
        case .onlyLeft: return .onlyLeft
        case .onlyRight: return .onlyRight
        default: return .differences
        }
    }

    private func color(for status: CompareStatus) -> Color {
        switch status {
        case .identical: return .green
        case .onlyLeft: return .blue
        case .onlyRight: return .purple
        case .differentSize: return .orange
        case .differentDate: return .yellow
        case .differentContent: return .red
        case .typeMismatch: return .pink
        }
    }

    // MARK: Sonuçlar

    @ViewBuilder
    private var resultsArea: some View {
        if model.entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.textSecondary)
                Text(model.statusMessage ?? L.t("compare.prompt"))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.field)
        } else if model.filteredEntries.isEmpty {
            Text(L.t("compare.emptyFilter"))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.field)
        } else {
            resultsTable
        }
    }

    private var resultsTable: some View {
        Table(model.filteredEntries, selection: $model.selection) {
            TableColumn(L.t("compare.column.path")) { entry in
                HStack(spacing: 6) {
                    Image(systemName: entry.leftIsDirectory || entry.rightIsDirectory ? "folder" : "doc")
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 14)
                    Text(entry.relativePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn(L.t("compare.column.status")) { entry in
                HStack(spacing: 4) {
                    Image(systemName: entry.status.systemImage)
                    Text(entry.status.localizedName)
                }
                .font(.caption)
                .foregroundStyle(color(for: entry.status))
            }
            .width(min: 120, ideal: 150)

            TableColumn(L.t("compare.column.left")) { entry in
                sideCell(
                    exists: entry.leftExists,
                    isDirectory: entry.leftIsDirectory,
                    size: entry.leftSize,
                    date: entry.leftDate
                )
            }
            .width(min: 140, ideal: 190)

            TableColumn(L.t("compare.column.right")) { entry in
                sideCell(
                    exists: entry.rightExists,
                    isDirectory: entry.rightIsDirectory,
                    size: entry.rightSize,
                    date: entry.rightDate
                )
            }
            .width(min: 140, ideal: 190)
        }
        .contextMenu(forSelectionType: String.self) { paths in
            if let path = paths.first, let entry = entry(for: path) {
                Button(L.t("compare.revealLeft")) { reveal(entry, side: .left) }
                    .disabled(!entry.leftExists)
                Button(L.t("compare.revealRight")) { reveal(entry, side: .right) }
                    .disabled(!entry.rightExists)
                Divider()
                Button(L.t("compare.copyPath")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.relativePath, forType: .string)
                }
            }
        } primaryAction: { paths in
            if let path = paths.first, let entry = entry(for: path) {
                if entry.leftExists {
                    reveal(entry, side: .left)
                } else if entry.rightExists {
                    reveal(entry, side: .right)
                }
            }
        }
    }

    private func sideCell(
        exists: Bool,
        isDirectory: Bool,
        size: Int64?,
        date: Date?
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if exists {
                if isDirectory {
                    Text(L.t("compare.folder"))
                } else if let size {
                    Text(FileSizeFormatter.string(fromBytes: size))
                        .monospacedDigit()
                }
                if let date {
                    Text(DateFormatterHelper.listString(from: date))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text("—").foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.textPrimary)
    }

    // MARK: Altlık

    private var footer: some View {
        HStack(spacing: 8) {
            Label(L.t("compare.readOnlyNote"), systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if let status = model.statusMessage, !model.entries.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(L.t("search.export")) { exportResults() }
                .disabled(model.filteredEntries.isEmpty)
            Button(L.t("compare.revealLeft")) {
                if let entry = selectedEntry { reveal(entry, side: .left) }
            }
            .disabled(!(selectedEntry?.leftExists ?? false))
            Button(L.t("compare.revealRight")) {
                if let entry = selectedEntry { reveal(entry, side: .right) }
            }
            .disabled(!(selectedEntry?.rightExists ?? false))
            Button(L.t("common.close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.header)
    }

    // MARK: İşlemler

    private var selectedEntry: CompareEntry? {
        guard let path = model.selection.first else { return nil }
        return entry(for: path)
    }

    private func entry(for path: String) -> CompareEntry? {
        model.entries.first { $0.relativePath == path }
    }

    private func reveal(_ entry: CompareEntry, side: PanelSide) {
        let root = side == .left ? model.leftRoot : model.rightRoot
        let url = root.appendingPathComponent(entry.relativePath)
        onReveal(url, side)
        dismiss()
    }

    private func exportResults() {
        let panel = NSSavePanel()
        panel.title = L.t("compare.exportTitle")
        panel.nameFieldStringValue = L.t("compare.exportFileName")
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
