//
//  FileIconGridView.swift
//  GMS_Commander
//
//  Panelin simge (ızgara) görünümü. Dosya ve klasörler büyük simgelerle
//  gösterilir; tek tıklama seçer, çift tıklama açar. Command ile çoklu seçim,
//  Shift ile aralık seçimi desteklenir.
//

import SwiftUI
import AppKit

/// Simge ızgarası tabanlı dosya görünümü.
struct FileIconGridView: View {
    @ObservedObject var panel: FilePanelViewModel
    @ObservedObject var viewModel: MainViewModel
    let isActive: Bool

    /// Shift ile aralık seçiminde son tıklanan öğenin sırası.
    @State private var lastClickedIndex: Int?

    private let tileWidth: CGFloat = 92
    private let iconSize: CGFloat = 42

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth + 20), spacing: 6)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                if panel.canGoUp && !panel.isSearchingActive {
                    parentTile
                }
                ForEach(Array(panel.items.enumerated()), id: \.element.id) { index, item in
                    tile(for: item, index: index)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(isActive ? Theme.panelActive : Theme.panel)
        .contentShape(Rectangle())
        .onTapGesture {
            // Boş alana tıklama seçimi temizler.
            panel.clearSelection()
        }
    }

    // MARK: - Kutular

    private var parentTile: some View {
        Button {
            viewModel.activate(side: panel.side)
            panel.goUp()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "arrow.turn.up.left")
                    .font(.system(size: iconSize * 0.65, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: iconSize, height: iconSize)
                Text("..")
                    .font(.system(size: max(Appearance.secondaryFontSize, 9), design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: tileWidth, height: 82)
        }
        .buttonStyle(.plain)
        .help(L.t("toolbar.up"))
    }

    private func tile(for item: FileItem, index: Int) -> some View {
        let selected = panel.selection.contains(item.url)
        return VStack(spacing: 4) {
            Image(nsImage: FileIconProvider.icon(for: item, pointSize: iconSize))
                .frame(width: iconSize, height: iconSize)

            Text(item.name)
                .font(.system(size: max(Appearance.secondaryFontSize, 9)))
                .foregroundStyle(
                    selected
                        ? Theme.textPrimary
                        : (item.isDirectory ? Theme.accent : Theme.textPrimary)
                )
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 3)
        .frame(width: tileWidth, height: 82, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Theme.accent.opacity(0.24) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(selected ? Theme.accent.opacity(0.75) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            viewModel.activate(side: panel.side)
            panel.select(item.url)
            lastClickedIndex = index
            viewModel.open(item)
        }
        .onTapGesture(count: 1) {
            handleTap(item: item, index: index)
        }
        .contextMenu {
            contextMenu(for: item)
        }
        .help(item.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func contextMenu(for item: FileItem) -> some View {
        Button(L.t("menu.file.open")) {
            viewModel.activate(side: panel.side)
            panel.select(item.url)
            viewModel.open(item)
        }
        // "Diğer Pencerede Aç" yalnızca klasörler için sunulur.
        if item.isDirectory {
            Button(L.t("menu.file.openInOtherPanel")) {
                viewModel.openInOtherPanel(item, from: panel.side)
            }
        }
        Button(L.t("menu.file.quickLook")) {
            viewModel.activate(side: panel.side)
            panel.select(item.url)
            viewModel.quickLookSelection()
        }
        Button(L.t("menu.file.view")) {
            viewModel.activate(side: panel.side)
            panel.select(item.url)
            viewModel.openViewer()
        }
        Button(L.t("menu.file.edit")) {
            viewModel.activate(side: panel.side)
            panel.select(item.url)
            viewModel.openEditor()
        }
        .disabled(item.isDirectory)
        Button(L.t("menu.tools.openArchive")) {
            viewModel.activate(side: panel.side)
            panel.select(item.url)
            viewModel.openSelectedArchive()
        }
        .disabled(ArchiveFormat.detect(item.url) == nil)
        Divider()
        Button(L.t("menu.edit.copy")) {
            panel.select(item.url)
            viewModel.copySelection()
        }
        Button(L.t("menu.edit.cut")) {
            panel.select(item.url)
            viewModel.cutSelection()
        }
        Button(L.t("menu.edit.paste")) { viewModel.paste() }
        if item.url.pathExtension.lowercased() == "app" {
            Button(L.t("favorites.addApplication")) {
                viewModel.activate(side: panel.side)
                if !viewModel.addApplicationToFavorites(item.url) {
                    viewModel.alert = UserFacingAlert(
                        title: L.t("favorites.add.title"),
                        message: L.t("favorites.application.exists")
                    )
                }
            }
        }
        Button(L.t("menu.edit.rename")) {
            viewModel.activate(side: panel.side)
            panel.select(item.url)
            viewModel.beginRename()
        }
        Button(L.t("menu.edit.batchRename")) {
            viewModel.activate(side: panel.side)
            if !panel.selection.contains(item.url) { panel.select(item.url) }
            viewModel.beginBatchRename()
        }
        Divider()
        Button(L.t("menu.tools.properties")) {
            viewModel.activate(side: panel.side)
            panel.select(item.url)
            viewModel.showProperties()
        }
        Button(L.t("menu.file.trash")) {
            viewModel.activate(side: panel.side)
            panel.select(item.url)
            viewModel.trashSelection()
        }
        Divider()
        Button(L.t("menu.view.refresh")) { viewModel.refreshActivePanel() }
        Button(L.t("menu.file.showHidden")) { viewModel.toggleHiddenFiles() }
    }

    // MARK: - Seçim

    private func handleTap(item: FileItem, index: Int) {
        viewModel.activate(side: panel.side)
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) {
            panel.toggleSelection(of: item.url)
        } else if flags.contains(.shift), let last = lastClickedIndex {
            let lower = min(last, index)
            let upper = max(last, index)
            let urls = (lower...upper).compactMap { position -> URL? in
                guard panel.items.indices.contains(position) else { return nil }
                return panel.items[position].url
            }
            panel.setSelection(Set(urls))
        } else {
            panel.select(item.url)
        }
        lastClickedIndex = index
    }
}
