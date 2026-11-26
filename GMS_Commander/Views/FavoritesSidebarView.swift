//
//  FavoritesSidebarView.swift
//  GMS_Commander
//
//  Finder tarzı hızlı erişim: özel isimli ve renkli bölümler ile dosya/klasörler.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FavoritesSidebarView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var favorites: FavoritesViewModel

    @State private var selectedID: UUID?
    @State private var hoveredID: UUID?
    @State private var isEditingGroups = false
    /// Sürükleme sırasında üzerine gelinen bölüm (görsel vurgu için).
    @State private var dropTargetGroupID: UUID?
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
                .commanderWindowBranding()
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
            .commanderWindowBranding()
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(L.t("favorites.title"))
                .font(.system(size: Appearance.keyFontSize, weight: .semibold))
                .foregroundStyle(SidebarPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .layoutPriority(1)

            Spacer(minLength: 2)

            FavoritesAddMenu(
                groups: favorites.groups,
                selectionCount: viewModel.activePanel.selection.count,
                canAddCurrent: { favorites.canAdd(url: viewModel.activePanel.currentDirectory, to: $0.id) },
                canAddSelection: canAddSelection,
                addCurrent: addCurrentDirectory,
                addSelection: addSelection
            )
            .frame(width: 16, height: 18)

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
                row(for: item, tint: tint, groupRole: group.role)
            }
        }
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(dropTargetGroupID == group.id ? tint.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        // Panelden veya Finder'dan sürüklenen öğeler bölüme doğrudan eklenir.
        .onDrop(of: [.fileURL], isTargeted: dropTargetBinding(for: group.id)) { providers in
            handleDrop(providers, to: group)
        }
    }

    private func dropTargetBinding(for groupID: UUID) -> Binding<Bool> {
        Binding(
            get: { dropTargetGroupID == groupID },
            set: { isTargeted in
                if isTargeted {
                    dropTargetGroupID = groupID
                } else if dropTargetGroupID == groupID {
                    dropTargetGroupID = nil
                }
            }
        )
    }

    /// Sürükle-bırak ile gelen adresleri bölüme ekler.
    ///
    /// Türü uymayan öğeler atlanır; hiçbiri eklenemezse uyarı gösterilir.
    private func handleDrop(_ providers: [NSItemProvider], to group: FavoriteGroup) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !matching.isEmpty else { return false }

        let groupID = group.id
        Task { @MainActor in
            var addedCount = 0
            var rejectedCount = 0
            for provider in matching {
                guard let url = await Self.loadFileURL(from: provider) else { continue }
                if favorites.add(url: url, to: groupID) {
                    addedCount += 1
                } else {
                    rejectedCount += 1
                }
            }
            if addedCount == 0 {
                showAddFailure(for: group, rejectedCount: rejectedCount)
            }
        }
        return true
    }

    /// `NSItemProvider` içeriğini dosya adresine çevirir.
    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    private func row(for item: FavoriteFolder, tint: Color, groupRole: FavoriteGroupRole?) -> some View {
        let isCurrent = item.isDirectory
            && item.path == viewModel.activePanel.currentDirectory.standardizedFileURL.path
        let isSelected = item.id == selectedID
        let isExternal = groupRole == .disks && viewModel.isExternalVolume(item.url)

        return HStack(spacing: 4) {
            Button {
                selectedID = item.id
                let targetSide = viewModel.activeSide
                viewModel.activate(side: targetSide)
                viewModel.openFavorite(item, side: targetSide)
            } label: {
                HStack(spacing: 6) {
                    if isExternal {
                        Image(systemName: "externaldrive.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(SidebarPalette.accent)
                            .frame(width: 15, height: 15)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                            .resizable()
                            .frame(width: 15, height: 15)
                    }

                    Text(item.name)
                        .font(.system(size: Appearance.keyFontSize, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? SidebarPalette.primaryText : SidebarPalette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.path)

            if isExternal {
                Button {
                    viewModel.ejectVolume(item)
                } label: {
                    if viewModel.ejectingVolumePath == item.path {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "eject")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(SidebarPalette.secondaryText)
                .disabled(viewModel.isOperating)
                .help(L.t("favorites.ejectHelp", item.name))
                .accessibilityLabel(L.t("favorites.ejectHelp", item.name))
            }
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
        .onHover { hovering in
            hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
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
                // Yalnızca kayıt türü uyan bölümler hedef olarak sunulur.
                ForEach(favorites.groups.filter {
                    $0.id != item.groupID && $0.kind == favorites.kind(of: item.url)
                }) { destination in
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
            Button(
                L.t(groupRole == .applications ? "favorites.removeApplication" : "favorites.remove"),
                role: .destructive
            ) {
                if selectedID == item.id { selectedID = nil }
                favorites.remove(id: item.id)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Programı hazırlayan bilgisi, öğe sayısı/Düzenle satırının üstünde.
            Text(AppInfo.author)
                .fontWeight(.medium)
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

    struct FavoritesAddMenu: NSViewRepresentable {
        let groups: [FavoriteGroup]
        let selectionCount: Int
        let canAddCurrent: (FavoriteGroup) -> Bool
        let canAddSelection: (FavoriteGroup) -> Bool
        let addCurrent: (FavoriteGroup) -> Void
        let addSelection: (FavoriteGroup) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        func makeNSView(context: Context) -> NSButton {
            let button = NSButton()
            button.isBordered = false
            button.image = NSImage(
                systemSymbolName: "chevron.down",
                accessibilityDescription: L.t("favorites.add")
            )?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = L.t("favorites.add")
            button.setAccessibilityLabel(L.t("favorites.add"))
            button.target = context.coordinator
            button.action = #selector(Coordinator.showMenu(_:))
            return button
        }

        func updateNSView(_ button: NSButton, context: Context) {
            context.coordinator.parent = self
        }

        final class Coordinator: NSObject {
            var parent: FavoritesAddMenu

            init(_ parent: FavoritesAddMenu) {
                self.parent = parent
            }

            @objc func showMenu(_ button: NSButton) {
                makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
            }

            func makeMenu() -> NSMenu {
                let menu = NSMenu()
                menu.autoenablesItems = false
                for group in parent.groups {
                    let groupItem = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
                    let submenu = NSMenu(title: group.name)
                    submenu.autoenablesItems = false
                    let current = NSMenuItem(
                        title: L.t("favorites.addCurrent"),
                        action: #selector(addCurrent(_:)),
                        keyEquivalent: ""
                    )
                    current.target = self
                    current.representedObject = group
                    current.isEnabled = parent.canAddCurrent(group)
                    submenu.addItem(current)

                    let selection = NSMenuItem(
                        title: L.t("favorites.addSelected", parent.selectionCount),
                        action: #selector(addSelection(_:)),
                        keyEquivalent: ""
                    )
                    selection.target = self
                    selection.representedObject = group
                    selection.isEnabled = parent.canAddSelection(group)
                    submenu.addItem(selection)
                    groupItem.submenu = submenu
                    menu.addItem(groupItem)
                }
                return menu
            }

            @objc private func addCurrent(_ item: NSMenuItem) {
                guard let group = item.representedObject as? FavoriteGroup else { return }
                parent.addCurrent(group)
            }

            @objc private func addSelection(_ item: NSMenuItem) {
                guard let group = item.representedObject as? FavoriteGroup else { return }
                parent.addSelection(group)
            }
        }
    }

    /// Seçili öğelerin tamamı bölümün kayıt türüne uyuyor mu?
    private func canAddSelection(to group: FavoriteGroup) -> Bool {
        let urls = viewModel.activePanel.selection
        return !urls.isEmpty && urls.allSatisfy { favorites.canAdd(url: $0, to: group.id) }
    }

    private func addCurrentDirectory(to group: FavoriteGroup) {
        let url = viewModel.activePanel.currentDirectory
        guard favorites.canAdd(url: url, to: group.id) else {
            showKindMismatch(for: group)
            return
        }
        guard viewModel.addActiveDirectoryToFavorites(groupID: group.id) else {
            viewModel.alert = UserFacingAlert(
                title: L.t("favorites.add.title"),
                message: L.t("favorites.add.exists")
            )
            return
        }
    }

    private func addSelection(to group: FavoriteGroup) {
        guard canAddSelection(to: group) else {
            showKindMismatch(for: group)
            return
        }
        let addedCount = viewModel.addSelectionToFavorites(groupID: group.id)
        guard addedCount == 0 else { return }
        viewModel.alert = UserFacingAlert(
            title: L.t("favorites.add.title"),
            message: L.t("favorites.add.exists")
        )
    }

    /// Ekleme başarısız olduğunda sebebi ayırt edip uygun uyarıyı gösterir.
    private func showAddFailure(for group: FavoriteGroup, rejectedCount: Int) {
        if rejectedCount > 0 {
            showKindMismatch(for: group)
        } else {
            viewModel.alert = UserFacingAlert(
                title: L.t("favorites.add.title"),
                message: L.t("favorites.add.exists")
            )
        }
    }

    /// Bölümün kayıt türü ile sürüklenen öğenin türü uyuşmadığında gösterilir.
    private func showKindMismatch(for group: FavoriteGroup) {
        viewModel.alert = UserFacingAlert(
            title: L.t("favorites.add.title"),
            message: L.t("favorites.add.kindMismatch", group.name, group.kind.localizedTitle)
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
    /// Yeni bölümün kabul edeceği kayıt türü.
    @State private var newGroupKind: FavoriteGroupKind = .folder

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

                        // Bölümün kabul ettiği kayıt türü (salt bilgi).
                        Text(group.kind.localizedTitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.border.opacity(0.25)))
                            .fixedSize()

                        Menu {
                            ForEach(colors, id: \.1) { entry in
                                Button {
                                    favorites.updateGroup(
                                        FavoriteGroup(
                                            id: group.id,
                                            name: group.name,
                                            colorHex: entry.1,
                                            role: group.role,
                                            kind: group.kind
                                        )
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

                    // Yeni bölümün kayıt türü: Klasör veya Dosya.
                    Picker("", selection: $newGroupKind) {
                        ForEach(FavoriteGroupKind.selectableCases, id: \.self) { kind in
                            Text(kind.localizedTitle).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)
                    .help(L.t("favorites.kind"))

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
                        guard let group = favorites.addGroup(
                            name: newGroupName,
                            colorHex: newGroupColor,
                            kind: newGroupKind
                        ) else { return }
                        groupNames[group.id] = group.name
                        newGroupName = ""
                        newGroupKind = .folder
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
            favorites.updateGroup(
                FavoriteGroup(
                    id: group.id,
                    name: name,
                    colorHex: group.colorHex,
                    role: group.role,
                    kind: group.kind
                )
            )
        }
    }

    private func saveAndDismiss() {
        persistNames()
        dismiss()
    }
}
