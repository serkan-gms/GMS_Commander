//
//  FavoritesSidebarView.swift
//  GMS_Commander
//
//  Finder tarzı hızlı erişim: özel isimli ve renkli bölümler ile dosya/klasörler.
//

import SwiftUI
import AppKit

struct FavoritesSidebarView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var favorites: FavoritesViewModel

    @State private var selectedID: UUID?
    @State private var hoveredID: UUID?
    @State private var isEditingGroups = false
    @State private var favoriteToRename: FavoriteFolder?
    @State private var favoriteNameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(favorites.groups) { group in
                        groupSection(group)
                    }
                    if favorites.groups.isEmpty {
                        Text(L.t("favorites.empty"))
                            .font(.system(size: Appearance.keyFontSize))
                            .foregroundStyle(SidebarPalette.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                    }
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 5)
            }

            Divider()
            footer
        }
        .frame(width: 205)
        .background(NativeSidebarBackground())
        .sheet(isPresented: $isEditingGroups) {
            FavoriteGroupEditor(favorites: favorites)
        }
        .sheet(item: $favoriteToRename) { favorite in
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("favorites.renameTitle"))
                    .font(.headline)
                TextField(L.t("favorites.groupName"), text: $favoriteNameDraft)
                    .onSubmit { saveFavoriteName(favorite) }
                HStack {
                    Spacer()
                    Button(L.t("common.cancel")) { favoriteToRename = nil }
                    Button(L.t("common.save")) { saveFavoriteName(favorite) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 360)
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "sidebar.left")
                .foregroundStyle(SidebarPalette.secondaryText)
            Text(L.t("favorites.title"))
                .font(.system(size: Appearance.keyFontSize, weight: .semibold))
                .foregroundStyle(SidebarPalette.primaryText)
                .lineLimit(1)

            Spacer(minLength: 2)

            Menu {
                ForEach(favorites.groups) { group in
                    Menu(group.name) {
                        Button(L.t("favorites.addCurrent")) {
                            addCurrentDirectory(to: group.id)
                        }
                        Button(L.t("favorites.addSelected", viewModel.activePanel.selection.count)) {
                            addSelection(to: group.id)
                        }
                        .disabled(viewModel.activePanel.selection.isEmpty)
                    }
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(SidebarPalette.accent)
            }
            .menuStyle(.borderlessButton)
            .help(L.t("favorites.add"))

            Button {
                isEditingGroups = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(SidebarPalette.secondaryText)
            }
            .buttonStyle(.plain)
            .help(L.t("favorites.editGroups"))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.clear)
    }

    private func groupSection(_ group: FavoriteGroup) -> some View {
        let groupItems = favorites.items.filter { $0.groupID == group.id }
        let tint = Color(nsColor: ThemeSpec.rgb(group.colorHex))

        return VStack(alignment: .leading, spacing: 1) {
            Text(group.name.uppercased())
                .font(.system(size: max(Appearance.keyFontSize - 2, 9), weight: .bold))
                .tracking(0.4)
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.top, 7)
                .padding(.bottom, 3)

            ForEach(groupItems) { item in
                row(for: item, tint: tint)
            }
        }
    }

    private func row(for item: FavoriteFolder, tint: Color) -> some View {
        let isCurrent = item.isDirectory
            && item.path == viewModel.activePanel.currentDirectory.standardizedFileURL.path
        let isSelected = item.id == selectedID

        return Button {
            selectedID = item.id
            let targetSide = viewModel.activeSide
            viewModel.activate(side: targetSide)
            viewModel.openFavorite(item, side: targetSide)
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .frame(width: 15, height: 15)

                Text(item.name)
                    .font(.system(size: Appearance.keyFontSize, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? SidebarPalette.primaryText : SidebarPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected
                        ? SidebarPalette.selection
                        : (hoveredID == item.id ? SidebarPalette.hover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .help(item.path)
        .contextMenu {
            if item.isDirectory && !item.isApplication {
                Button(L.t("favorites.openActive")) { viewModel.openFavorite(item) }
                Button(L.t("favorites.openLeft")) { viewModel.openFavorite(item, side: .left) }
                Button(L.t("favorites.openRight")) { viewModel.openFavorite(item, side: .right) }
                Divider()
            } else if item.isApplication {
                Button(L.t("favorites.openApplication")) { viewModel.openFavorite(item) }
                Divider()
            } else {
                Button(L.t("favorites.openFile")) { viewModel.openFavorite(item) }
                Divider()
            }

            Menu(L.t("favorites.moveToGroup")) {
                ForEach(favorites.groups.filter { $0.id != item.groupID }) { destination in
                    Button(destination.name) { favorites.move(id: item.id, to: destination.id) }
                }
            }
            .disabled(favorites.groups.count < 2)

            Button(L.t("favorites.rename")) {
                favoriteNameDraft = item.name
                favoriteToRename = item
            }
            Button(L.t("favorites.moveUp")) { favorites.moveItem(id: item.id, offset: -1) }
            Button(L.t("favorites.moveDown")) { favorites.moveItem(id: item.id, offset: 1) }
            Divider()
            Button(L.t("favorites.remove"), role: .destructive) {
                if selectedID == item.id { selectedID = nil }
                favorites.remove(id: item.id)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
            Text(L.t("favorites.hint", favorites.items.count))
            Spacer(minLength: 0)
            Button {
                isEditingGroups = true
            } label: {
                Text(L.t("favorites.edit"))
                    .fontWeight(.medium)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: max(Appearance.keyFontSize - 1, 10)))
        .foregroundStyle(SidebarPalette.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(SidebarPalette.footer)
    }

    private enum SidebarPalette {
        static let primaryText = Color(nsColor: .labelColor)
        static let secondaryText = Color(nsColor: .secondaryLabelColor)
        static let accent = Color(nsColor: .controlAccentColor)
        static let selection = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        static let hover = Color(nsColor: .quaternaryLabelColor).opacity(0.18)
        static let footer = Color(nsColor: .controlBackgroundColor).opacity(0.45)
    }

    private struct NativeSidebarBackground: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .sidebar
            view.blendingMode = .behindWindow
            view.state = .followsWindowActiveState
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    }

    private func addCurrentDirectory(to groupID: UUID) {
        guard viewModel.addActiveDirectoryToFavorites(groupID: groupID) else {
            viewModel.alert = UserFacingAlert(
                title: L.t("favorites.add.title"),
                message: L.t("favorites.add.exists")
            )
            return
        }
    }

    private func addSelection(to groupID: UUID) {
        let addedCount = viewModel.addSelectionToFavorites(groupID: groupID)
        guard addedCount == 0 else { return }
        viewModel.alert = UserFacingAlert(
            title: L.t("favorites.add.title"),
            message: L.t("favorites.add.exists")
        )
    }

    private func saveFavoriteName(_ favorite: FavoriteFolder) {
        favorites.rename(id: favorite.id, to: favoriteNameDraft)
        favoriteToRename = nil
    }
}

private struct FavoriteGroupEditor: View {
    @ObservedObject var favorites: FavoritesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var groupNames: [UUID: String] = [:]
    @State private var newGroupName = ""
    @State private var newGroupColor: UInt32 = 0x4F9CF9

    private let colors: [(String, UInt32)] = [
        ("favorites.color.blue", 0x4F9CF9),
        ("favorites.color.purple", 0xB18AF5),
        ("favorites.color.green", 0x42C98A),
        ("favorites.color.orange", 0xE0A84B),
        ("favorites.color.red", 0xEF6461),
        ("favorites.color.teal", 0x39C6C8),
        ("favorites.color.pink", 0xE879B9)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.t("favorites.editGroups"))
                    .font(.headline)
                Spacer()
                Button(L.t("common.close")) { saveAndDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            List {
                ForEach(Array(favorites.groups.enumerated()), id: \.element.id) { index, group in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(Theme.textSecondary)
                        TextField(
                            L.t("favorites.groupName"),
                            text: Binding(
                                get: { groupNames[group.id] ?? group.name },
                                set: { groupNames[group.id] = $0 }
                            )
                        )

                        Menu {
                            ForEach(colors, id: \.1) { entry in
                                Button {
                                    favorites.updateGroup(
                                        FavoriteGroup(id: group.id, name: group.name, colorHex: entry.1)
                                    )
                                } label: {
                                    Label(
                                        L.t(entry.0),
                                        systemImage: group.colorHex == entry.1 ? "checkmark.circle.fill" : "circle.fill"
                                    )
                                    .tint(Color(nsColor: ThemeSpec.rgb(entry.1)))
                                }
                            }
                        } label: {
                            Circle()
                                .fill(Color(nsColor: ThemeSpec.rgb(group.colorHex)))
                                .frame(width: 15, height: 15)
                        }
                        .menuStyle(.borderlessButton)
                        .help(L.t("favorites.color"))

                        Button {
                            guard index > 0 else { return }
                            favorites.moveGroup(from: IndexSet(integer: index), to: index - 1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(index == 0)
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            favorites.removeGroup(id: group.id)
                            groupNames.removeValue(forKey: group.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .disabled(favorites.groups.count <= 1)
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 3)
                }

                HStack {
                    TextField(L.t("favorites.newGroupPlaceholder"), text: $newGroupName)
                    Menu {
                        ForEach(colors, id: \.1) { entry in
                            Button(L.t(entry.0)) { newGroupColor = entry.1 }
                        }
                    } label: {
                        Circle()
                            .fill(Color(nsColor: ThemeSpec.rgb(newGroupColor)))
                            .frame(width: 15, height: 15)
                    }
                    .menuStyle(.borderlessButton)

                    Button {
                        guard let group = favorites.addGroup(name: newGroupName, colorHex: newGroupColor) else { return }
                        groupNames[group.id] = group.name
                        newGroupName = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 5)
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Text(L.t("favorites.removeGroupHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L.t("common.close")) { saveAndDismiss() }
            }
            .padding()
        }
        .frame(width: 480, height: 380)
        .onAppear { synchronizeNames() }
        .onDisappear { persistNames() }
    }

    private func synchronizeNames() {
        groupNames = Dictionary(uniqueKeysWithValues: favorites.groups.map { ($0.id, $0.name) })
    }

    private func persistNames() {
        for group in favorites.groups {
            guard let name = groupNames[group.id],
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  name != group.name else { continue }
            favorites.updateGroup(FavoriteGroup(id: group.id, name: name, colorHex: group.colorHex))
        }
    }

    private func saveAndDismiss() {
        persistNames()
        dismiss()
    }
}
