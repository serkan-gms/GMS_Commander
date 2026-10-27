//
//  ArchiveBrowserView.swift
//  GMS_Commander
//
//  ZIP/TAR arşivlerini açmadan içeriğini gösteren ve seçili öğeleri ya da
//  tüm arşivi hedef panele çıkaran pencere.
//

import SwiftUI

/// Arşiv tarayıcısının durumu.
@MainActor
final class ArchiveBrowserViewModel: ObservableObject {
    /// Açılan arşiv.
    let archiveURL: URL
    /// Çıkarma hedefi (genellikle pasif panelin klasörü).
    let destinationDirectory: URL

    @Published private(set) var entries: [ArchiveEntry] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isExtracting = false
    @Published private(set) var progress: ArchiveProgress?
    @Published var selection: Set<String> = []
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let service = ArchiveService()
    private let control = TransferControl()

    init(archiveURL: URL, destinationDirectory: URL) {
        self.archiveURL = archiveURL
        self.destinationDirectory = destinationDirectory
    }

    /// Arşiv içeriğini okur.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let listed = try await Task.detached(priority: .userInitiated) { [archiveURL] in
                try ArchiveService().listEntries(in: archiveURL)
            }.value
            entries = listed
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Seçili öğeleri veya tüm arşivi çıkarır.
    /// - Parameter selectedOnly: `true` ise yalnızca seçim çıkarılır.
    /// - Returns: En az bir öğe hedefe taşındıysa `true`.
    @discardableResult
    func extract(selectedOnly: Bool) async -> Bool {
        guard !isExtracting else { return false }
        errorMessage = nil
        successMessage = nil

        let paths: Set<String>? = selectedOnly ? selection : nil
        if selectedOnly && paths?.isEmpty != false {
            errorMessage = L.t("archive.selectFirst")
            return false
        }

        isExtracting = true
        progress = nil
        defer {
            isExtracting = false
            progress = nil
        }

        do {
            let moved = try await service.extract(
                archive: archiveURL,
                to: destinationDirectory,
                selectedPaths: paths,
                control: control
            ) { [weak self] update in
                Task { @MainActor in
                    self?.progress = update
                }
            }
            successMessage = L.t("archive.extractSuccess", moved.count, destinationDirectory.lastPathComponent)
            selection.removeAll()
            return !moved.isEmpty
        } catch is CancellationError {
            errorMessage = L.t("archive.cancelled")
            return false
        } catch {
            errorMessage = ErrorMessages.message(for: error)
            return false
        }
    }

    /// Süren çıkarmayı iptal eder.
    func cancelExtraction() {
        control.cancel()
    }
}

/// Arşiv tarayıcı penceresi.
struct ArchiveBrowserView: View {
    @StateObject private var model: ArchiveBrowserViewModel
    @Environment(\.dismiss) private var dismiss
    private let onExtracted: () -> Void

    init(
        archiveURL: URL,
        destinationDirectory: URL,
        onExtracted: @escaping () -> Void
    ) {
        _model = StateObject(
            wrappedValue: ArchiveBrowserViewModel(
                archiveURL: archiveURL,
                destinationDirectory: destinationDirectory
            )
        )
        self.onExtracted = onExtracted
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            content
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 760, height: 520)
        .background(Theme.panel)
        .task { await model.load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "archivebox")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.archiveURL.lastPathComponent)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t("archive.destination", model.destinationDirectory.path))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(L.t("archive.entryCount", model.entries.count))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.header)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView(L.t("archive.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage, model.entries.isEmpty {
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
        } else {
            List(selection: $model.selection) {
                ForEach(model.entries) { entry in
                    HStack(spacing: 6) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.isDirectory ? Theme.folder : Theme.textSecondary)
                        Text(entry.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .tag(entry.path)
                    .contextMenu {
                        Button(L.t("archive.extractSelected")) {
                            model.selection = [entry.path]
                            Task { if await model.extract(selectedOnly: true) { onExtracted() } }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if let progress = model.progress, model.isExtracting {
                HStack(spacing: 8) {
                    ProgressView(value: progress.fraction)
                    Text(progress.currentName)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Text("\(progress.completedItems)/\(progress.totalItems)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if let success = model.successMessage {
                Label(success, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.errorMessage, !model.entries.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(L.t("archive.selectAll")) {
                    model.selection = Set(model.entries.map(\.path))
                }
                .controlSize(.small)
                Button(L.t("archive.deselectAll")) {
                    model.selection.removeAll()
                }
                .controlSize(.small)
                Spacer()
                if model.isExtracting {
                    Button(L.t("common.cancel")) { model.cancelExtraction() }
                        .controlSize(.small)
                } else {
                    Button(L.t("archive.extractSelected")) {
                        Task { if await model.extract(selectedOnly: true) { onExtracted() } }
                    }
                    .disabled(model.selection.isEmpty || model.entries.isEmpty)
                    Button(L.t("archive.extractAll")) {
                        Task { if await model.extract(selectedOnly: false) { onExtracted() } }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.entries.isEmpty)
                }
                Button(L.t("common.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .background(Theme.header)
    }
}
