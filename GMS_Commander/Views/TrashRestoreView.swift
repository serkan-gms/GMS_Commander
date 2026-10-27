//
//  TrashRestoreView.swift
//  GMS_Commander
//
//  Çöp Kutusu'ndaki öğeleri listeleyen ve seçilenleri etkin panele geri
//  yükleyen pencere. Boşaltma işlemi ayrıca onay ister.
//

import SwiftUI

/// Çöp Kutusu penceresinin durumu.
@MainActor
final class TrashRestoreViewModel: ObservableObject {
    @Published private(set) var items: [TrashItem] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isWorking = false
    @Published var selection: Set<URL> = []
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var isConfirmingEmpty = false

    /// Geri yükleme hedefi.
    let destination: URL
    private let service = TrashService()

    init(destination: URL) {
        self.destination = destination
    }

    /// Çöp kutusu içeriğini yeniler.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let listed = try await Task.detached(priority: .userInitiated) {
                try TrashService().listItems()
            }.value
            items = listed
            selection = selection.intersection(Set(listed.map(\.url)))
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }

    /// Seçili öğeleri hedef klasöre geri yükler.
    /// - Returns: En az bir öğe geri yüklendiyse `true`.
    @discardableResult
    func restoreSelected() async -> Bool {
        guard !isWorking else { return false }
        let selected = items.filter { selection.contains($0.url) }
        guard !selected.isEmpty else {
            errorMessage = L.t("trash.selectFirst")
            return false
        }

        isWorking = true
        message = nil
        errorMessage = nil
        defer { isWorking = false }

        do {
            let restored = try await Task.detached(priority: .userInitiated) { [service, destination] in
                try service.restore(selected, to: destination)
            }.value
            message = L.t("trash.restoreSuccess", restored.count, destination.lastPathComponent)
            selection.removeAll()
            await load()
            return !restored.isEmpty
        } catch {
            errorMessage = ErrorMessages.message(for: error)
            return false
        }
    }

    /// Çöp kutusunu kalıcı olarak boşaltır.
    func emptyTrash() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await Task.detached(priority: .userInitiated) {
                try TrashService().empty()
            }.value
            message = L.t("trash.emptySuccess")
            selection.removeAll()
            await load()
        } catch {
            errorMessage = ErrorMessages.message(for: error)
        }
    }
}

/// Çöp Kutusu geri yükleme penceresi.
struct TrashRestoreView: View {
    @StateObject private var model: TrashRestoreViewModel
    @Environment(\.dismiss) private var dismiss
    private let onRestored: () -> Void

    init(destination: URL, onRestored: @escaping () -> Void) {
        _model = StateObject(wrappedValue: TrashRestoreViewModel(destination: destination))
        self.onRestored = onRestored
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            content
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 700, height: 480)
        .background(Theme.panel)
        .task { await model.load() }
        .confirmationDialog(
            L.t("trash.emptyConfirmTitle"),
            isPresented: $model.isConfirmingEmpty,
            titleVisibility: .visible
        ) {
            Button(L.t("trash.emptyAction"), role: .destructive) {
                Task {
                    await model.emptyTrash()
                    onRestored()
                }
            }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(L.t("trash.emptyConfirmMessage"))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("trash.title"))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t("trash.destination", model.destination.path))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(L.t("trash.itemCount", model.items.count))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.header)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView(L.t("trash.loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "trash.slash")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.textSecondary)
                Text(L.t("trash.empty"))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(model.items, selection: $model.selection) {
                TableColumn(L.t("column.name")) { item in
                    HStack(spacing: 5) {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(item.isDirectory ? Theme.folder : Theme.textSecondary)
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                TableColumn(L.t("trash.column.size")) { item in
                    Text(item.isDirectory ? "—" : FileSizeFormatter.string(fromBytes: item.size))
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 100, max: 140)
                TableColumn(L.t("trash.column.date")) { item in
                    Text(item.modificationDate.map { DateFormatterHelper.detailedString(from: $0) } ?? "—")
                        .monospacedDigit()
                }
                .width(min: 140, ideal: 170, max: 220)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if let message = model.message {
                Label(message, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if model.isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button(L.t("trash.emptyButton")) {
                    model.isConfirmingEmpty = true
                }
                .controlSize(.small)
                .disabled(model.items.isEmpty || model.isWorking)

                Button(L.t("trash.restoreButton")) {
                    Task {
                        if await model.restoreSelected() { onRestored() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selection.isEmpty || model.isWorking)

                Button(L.t("common.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .background(Theme.header)
    }
}
