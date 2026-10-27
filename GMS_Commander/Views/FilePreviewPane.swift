//
//  FilePreviewPane.swift
//  GMS_Commander
//
//  Etkin panelde seçili dosyanın hızlı önizlemesini gösteren yan bölme.
//  Görseller, PDF'ler ve metin dosyaları gösterilir; diğer türlerde büyük
//  dosya simgesi ve meta veriler sunulur.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Seçili öğenin önizleme bölmesi.
struct FilePreviewPane: View {
    @ObservedObject var panel: FilePanelViewModel
    @ObservedObject var viewModel: MainViewModel

    @State private var image: NSImage?
    @State private var textPreview: String?
    @State private var isLoading = false

    /// Önizleme için seçili tek öğe.
    private var item: FileItem? {
        panel.selection.count == 1 ? panel.focusedItem : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if item != nil {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
                footer
            }
        }
        .background(Theme.panel)
        .task(id: item?.url) {
            await loadPreview()
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "eye")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            Text(L.t("preview.title"))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Theme.header)
    }

    @ViewBuilder
    private var content: some View {
        if let item {
            ScrollView {
                VStack(spacing: 8) {
                    if !item.isDirectory, let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .padding(6)
                    } else if !item.isDirectory, let textPreview {
                        Text(textPreview)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .textSelection(.enabled)
                    } else {
                        Image(nsImage: FileIconProvider.icon(for: item, pointSize: 64))
                            .frame(width: 64, height: 64)
                            .padding(.top, 18)
                        Text(item.isDirectory ? L.t("conflict.folder") : item.kind)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Text(item.name)
                        .font(.system(size: max(Appearance.secondaryFontSize, 9), weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 6)
                }
                .frame(maxWidth: .infinity)
            }
        } else if panel.selection.count > 1 {
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.textSecondary)
                Text(L.t("preview.multiple", panel.selection.count))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                Text(L.t("preview.empty"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let item {
                detailRow(L.t("properties.kind"), item.kind)
                if !item.isDirectory {
                    detailRow(L.t("properties.size"), FileSizeFormatter.string(for: item))
                }
                detailRow(L.t("properties.modified"), DateFormatterHelper.listString(from: item.modificationDate))
                if let permissions = item.permissionsText {
                    detailRow(L.t("column.permissions"), permissions)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Yükleme

    /// Seçili öğeye göre görsel veya metin önizlemesini yükler.
    private func loadPreview() async {
        image = nil
        textPreview = nil

        guard let item, !item.isDirectory else { return }

        let url = item.url
        let fileExtension = url.pathExtension.lowercased()
        let isImage = UTType(filenameExtension: fileExtension)?.conforms(to: .image) == true
            || fileExtension == "pdf"
        let isText = Self.textExtensions.contains(fileExtension)

        guard isImage || isText else { return }

        isLoading = true
        defer { isLoading = false }

        let result = await Task.detached(priority: .utility) { () -> (Data?, String?) in
            if isImage {
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size < 60 * 1024 * 1024 else { return (nil, nil) }
                return (try? Data(contentsOf: url, options: .mappedIfSafe), nil)
            }
            guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, nil) }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: 16 * 1024)) ?? Data()
            return (nil, String(decoding: data, as: UTF8.self))
        }.value

        // Seçim bu sırada değiştiyse eski sonucu göstermeyiz.
        guard item.url == self.item?.url else { return }

        if let data = result.0 {
            image = NSImage(data: data)
        } else if let text = result.1 {
            textPreview = text.isEmpty ? L.t("preview.emptyFile") : text
        }
    }

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp",
        "json", "xml", "yaml", "yml", "html", "htm", "css", "scss", "js", "ts",
        "py", "sh", "zsh", "bash", "plist", "log", "csv", "ini", "conf", "toml",
        "rs", "go", "java", "kt", "php", "rb", "sql", "gitignore", "env"
    ]
}
