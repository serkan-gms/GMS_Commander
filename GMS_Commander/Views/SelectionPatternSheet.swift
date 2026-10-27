//
//  SelectionPatternSheet.swift
//  GMS_Commander
//
//  Etkin paneldeki öğeleri joker (glob) veya düzenli ifadeyle seçen pencere.
//  Seçim yalnızca görünen liste üzerinde çalışır; dosya sistemine dokunmaz.
//

import SwiftUI
import AppKit

/// Desene göre seçim uygulama biçimi.
enum SelectionApplyMode {
    case replace
    case add
    case remove
}

/// Desene göre seçim penceresi.
struct SelectionPatternSheet: View {
    let items: [FileItem]
    let initialSelection: Set<URL>
    let onApply: (Set<URL>, SelectionApplyMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pattern = "*"
    @State private var useRegex = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            editor
            Rectangle().fill(Theme.border).frame(height: 1)
            preview
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 820, height: 520)
        .background(Theme.panel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("selectionPattern.title"))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(L.t("selectionPattern.subtitle", items.count))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(L.t("common.close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
        .background(Theme.header)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L.t("selectionPattern.pattern"))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                TextField(L.t("selectionPattern.placeholder"), text: $pattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { apply(.replace) }
                Toggle(L.t("search.criteria.regex"), isOn: $useRegex)
                    .toggleStyle(.checkbox)
            }
            HStack(spacing: 8) {
                if let error = matchError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label(
                        L.t("selectionPattern.matched", matchedURLs.count),
                        systemImage: "checkmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(L.t("selectionPattern.selected", initialSelection.count))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.header)
    }

    @ViewBuilder
    private var preview: some View {
        if matchError != nil {
            Text(L.t("selectionPattern.invalidPattern"))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.field)
        } else if matchedItems.isEmpty {
            Text(L.t("selectionPattern.noMatch"))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.field)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(matchedItems.prefix(500)) { item in
                        HStack(spacing: 6) {
                            Image(nsImage: FileIconProvider.icon(for: item))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if initialSelection.contains(item.url) {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
            }
            .background(Theme.field)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(L.t("selectionPattern.invert")) {
                let all = Set(items.map(\.url))
                onApply(all.subtracting(initialSelection), .replace)
                dismiss()
            }
            Button(L.t("selectionPattern.clear")) {
                onApply([], .replace)
                dismiss()
            }
            Spacer()
            Button(L.t("selectionPattern.add")) { apply(.add) }
                .disabled(matchedURLs.isEmpty)
            Button(L.t("selectionPattern.remove")) { apply(.remove) }
                .disabled(matchedURLs.isEmpty)
            Button(L.t("selectionPattern.replace")) { apply(.replace) }
                .buttonStyle(.borderedProminent)
                .disabled(matchedURLs.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.header)
    }

    // MARK: - Eşleştirme

    private var matchError: String? {
        guard useRegex else { return nil }
        guard SelectionPatternMatcher.isValidRegex(pattern) else {
            return L.t("selectionPattern.invalidRegex")
        }
        return nil
    }

    private var matchedItems: [FileItem] {
        guard matchError == nil else { return [] }
        return items.filter {
            SelectionPatternMatcher.matches(name: $0.name, pattern: pattern, useRegex: useRegex)
        }
    }

    private var matchedURLs: Set<URL> {
        Set(matchedItems.map(\.url))
    }

    private func apply(_ mode: SelectionApplyMode) {
        guard matchError == nil, !matchedURLs.isEmpty else { return }
        onApply(matchedURLs, mode)
        dismiss()
    }
}
