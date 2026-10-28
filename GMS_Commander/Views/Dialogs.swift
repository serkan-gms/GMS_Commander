//
//  Dialogs.swift
//  GMS_Commander
//
//  Yardımcı pencereler: yeniden adlandırma, dosya özellikleri, çakışma kararı,
//  kısayol listesi ve "Hakkında" bilgisi.
//

import SwiftUI
import AppKit

// MARK: - Yeniden adlandırma

/// Yeniden adlandırma sayfası.
struct RenameSheet: View {
    let request: RenameRequest
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var fieldFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L.t("rename.title"), systemImage: "pencil")
                .font(.headline)

            TextField(L.t("rename.placeholder"), text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(commit)

            Text(L.t("rename.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L.t("common.rename"), action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            name = request.suggestedName
            fieldFocused = true
        }
    }

    private func commit() {
        guard !trimmedName.isEmpty else { return }
        onCommit(trimmedName)
        dismiss()
    }
}

// MARK: - Özellikler

/// Dosya özellikleri sayfası.
struct PropertiesSheet: View {
    let item: FileItem
    @ObservedObject var viewModel: MainViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: FileIconProvider.icon(for: item))
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Divider()

            if let properties = viewModel.properties {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        row(L.t("properties.name"), properties.name)
                        row(L.t("properties.path"), properties.path)
                        row(L.t("properties.kind"), properties.kind)
                        row(L.t("properties.size"), properties.sizeText)
                        if let countText = properties.itemCountText {
                            row(L.t("properties.items"), countText)
                        }
                        row(L.t("properties.created"), properties.createdText)
                        row(L.t("properties.modified"), properties.modifiedText)
                        row(L.t("properties.permissions"), properties.permissionsText)
                        row(L.t("properties.owner"), properties.ownerText)
                        row(L.t("properties.group"), properties.groupText)
                        if let destination = properties.symlinkDestination {
                            row(L.t("properties.symlinkTarget"), destination)
                        }
                        row(L.t("properties.hidden"), properties.isHidden ? L.t("common.yes") : L.t("common.no"))
                        row(L.t("properties.readable"), properties.isReadable ? L.t("common.yes") : L.t("common.no"))
                        row(L.t("properties.writable"), properties.isWritable ? L.t("common.yes") : L.t("common.no"))
                        row(L.t("properties.executable"), properties.isExecutable ? L.t("common.yes") : L.t("common.no"))
                        row(L.t("properties.attributes"), "\(properties.extendedAttributeCount)")
                        if let volume = properties.volumeName {
                            row(L.t("properties.volume"), volume)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L.t("properties.loading"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }

            HStack {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(item.url.path, forType: .string)
                } label: {
                    Label(L.t("properties.copyPath"), systemImage: "doc.on.doc")
                }
                Spacer()
                Button(L.t("common.close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

// MARK: - Çakışma

/// Kopyalama/taşıma sırasındaki çakışma sayfası.
/// Kaynak ve hedefin tür, boyut ve tarih bilgileri karşılaştırmalı gösterilir;
/// kullanıcı isterse aynı kararı bu aktarımdaki tüm çakışmalara uygulayabilir.
struct ConflictSheet: View {
    let request: ConflictRequest
    let onDecision: (ConflictDecision, Bool) -> Void

    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L.t("conflict.title"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(L.t("conflict.message", request.sourceName, request.destinationName))
                .fixedSize(horizontal: false, vertical: true)

            Text(request.destinationDirectory)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            Divider()

            // Karşılaştırma tablosu: tür, boyut ve değiştirme tarihi.
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("")
                    Text(L.t("conflict.source")).font(.caption.bold())
                    Text(L.t("conflict.destination")).font(.caption.bold())
                }
                Divider().gridCellColumns(3)
                GridRow {
                    Text(L.t("conflict.type")).font(.caption).foregroundStyle(.secondary)
                    Text(request.sourceIsDirectory ? L.t("conflict.folder") : L.t("conflict.file"))
                    Text(request.destinationIsDirectory ? L.t("conflict.folder") : L.t("conflict.file"))
                }
                GridRow {
                    Text(L.t("conflict.size")).font(.caption).foregroundStyle(.secondary)
                    Text(sizeText(request.sourceSize, isDirectory: request.sourceIsDirectory))
                    Text(sizeText(request.destinationSize, isDirectory: request.destinationIsDirectory))
                }
                GridRow {
                    Text(L.t("conflict.modified")).font(.caption).foregroundStyle(.secondary)
                    Text(DateFormatterHelper.listString(from: request.sourceDate))
                    Text(DateFormatterHelper.listString(from: request.destinationDate))
                }
            }
            .font(.callout)

            Toggle(L.t("conflict.applyToAll"), isOn: $applyToAll)
                .toggleStyle(.checkbox)

            Divider()

            HStack {
                Button(L.t("conflict.cancel")) { onDecision(.cancel, false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L.t("conflict.skip")) { onDecision(.skip, applyToAll) }
                Button(L.t("conflict.keepBoth")) { onDecision(.keepBoth, applyToAll) }
                Button(L.t("conflict.overwrite")) { onDecision(.overwrite, applyToAll) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled()
    }

    private func sizeText(_ size: Int64?, isDirectory: Bool) -> String {
        guard !isDirectory, let size else { return "—" }
        return FileSizeFormatter.string(fromBytes: size)
    }
}

// MARK: - Kısayollar

/// Klavye kısayolları ve kullanım ipuçları.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    /// Kullanıcının işlev tuşu atamaları; F tuşu satırlarında gösterilir.
    var bindings: KeyboardShortcutManager.FunctionKeyBindings = .default

    private var shortcuts: [KeyboardShortcutManager.Shortcut] {
        KeyboardShortcutManager.all.map { entry in
            guard entry.titleKey.hasPrefix("fkey."),
                  let action = KeyboardShortcutManager.FunctionKeyAction(
                    rawValue: String(entry.titleKey.dropFirst("fkey.".count))
                  ) else {
                return entry
            }
            return KeyboardShortcutManager.Shortcut(
                keys: bindings.label(for: action),
                titleKey: entry.titleKey
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L.t("help.title"), systemImage: "keyboard")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(shortcuts) { entry in
                        HStack(spacing: 12) {
                            Text(entry.keys)
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 80, alignment: .leading)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            Text(entry.title)
                                .font(.callout)
                            Spacer()
                        }
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(maxHeight: 380)

            Divider()

            Text(L.t("help.tip"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(L.t("help.version", AppInfo.version))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L.t("common.close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

/// Uygulama sürüm bilgisi.
enum AppInfo {
    static let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    static let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    static let name = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "GMS Commander"
    /// Programı hazırlayan kişi.
    static let author = "Serkan GÜLTEKİN"
}
