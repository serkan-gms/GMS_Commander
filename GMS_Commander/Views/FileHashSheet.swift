//
//  FileHashSheet.swift
//  GMS_Commander
//
//  Seçili dosyaların SHA-256 özetlerini hesaplayan pencere.
//  Büyük dosyalar parça parça okunur; işlem iptal edilebilir.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Hash penceresinin durumu.
@MainActor
final class FileHashViewModel: ObservableObject {
    let urls: [URL]

    @Published private(set) var results: [FileHashResult] = []
    @Published private(set) var isComputing = true
    @Published private(set) var completedCount = 0
    @Published private(set) var wasCancelled = false
    @Published var statusMessage: String?

    private let control = TransferControl()

    init(urls: [URL]) {
        self.urls = urls
    }

    /// Hesaplamayı başlatır.
    func start() async {
        let urls = self.urls
        let control = self.control
        let results = await Task.detached(priority: .userInitiated) {
            FileHashService.hashes(
                for: urls,
                control: control,
                progress: { count in
                    Task { @MainActor in
                        self.completedCount = count
                    }
                }
            )
        }.value
        self.results = results
        self.isComputing = false
        self.wasCancelled = control.isCancelled
        if wasCancelled {
            statusMessage = L.t("hash.cancelled")
        }
    }

    /// Hesaplamayı iptal eder.
    func cancel() {
        control.cancel()
    }

    /// Bir özeti panoya kopyalar.
    func copyDigest(_ digest: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(digest, forType: .string)
        statusMessage = L.t("hash.copied")
    }

    /// Tüm sonuçları panoya kopyalar.
    func copyAll() {
        let lines = results.map { result in
            "\(result.digest ?? "-")  \(result.url.path)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        statusMessage = L.t("hash.copiedAll", results.count)
    }

    /// Sonuçları CSV olarak yazar.
    func exportCSV(to url: URL) throws {
        var lines = ["Ad;Yol;SHA-256;Hata"]
        for result in results {
            let fields = [
                result.name,
                result.url.path,
                result.digest ?? "",
                result.errorMessage ?? ""
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

/// SHA-256 hesaplama penceresi.
struct FileHashSheet: View {
    @StateObject private var model: FileHashViewModel
    @Environment(\.dismiss) private var dismiss

    init(urls: [URL]) {
        _model = StateObject(wrappedValue: FileHashViewModel(urls: urls))
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
        .task { await model.start() }
        .onDisappear { model.cancel() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "number.square")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("hash.title"))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t("hash.subtitle", model.urls.count))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if model.isComputing {
                ProgressView(
                    value: Double(model.completedCount),
                    total: Double(max(model.urls.count, 1))
                )
                .frame(width: 160)
            }
        }
        .padding(12)
        .background(Theme.header)
    }

    @ViewBuilder
    private var content: some View {
        if model.isComputing && model.results.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text(L.t("hash.computing", model.completedCount, model.urls.count))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.field)
        } else {
            Table(model.results) {
                TableColumn(L.t("column.name")) { result in
                    Text(result.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 140, ideal: 180)

                TableColumn("SHA-256") { result in
                    if let digest = result.digest {
                        Text(digest)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(result.errorMessage ?? "—")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .width(min: 280, ideal: 380)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let status = model.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.isComputing {
                Button(L.t("compare.cancel")) { model.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
            }
            Button(L.t("hash.copyAll")) { model.copyAll() }
                .disabled(model.results.isEmpty)
            Button(L.t("search.export")) { exportResults() }
                .disabled(model.results.isEmpty)
            Button(L.t("common.close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.header)
    }

    private func exportResults() {
        let panel = NSSavePanel()
        panel.title = L.t("hash.exportTitle")
        panel.nameFieldStringValue = L.t("hash.exportFileName")
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportCSV(to: url)
            model.statusMessage = L.t("search.exportDone", url.lastPathComponent)
        } catch {
            model.statusMessage = L.t("search.exportFailed", error.localizedDescription)
        }
    }
}
