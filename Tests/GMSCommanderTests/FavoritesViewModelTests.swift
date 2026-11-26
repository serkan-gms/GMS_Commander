//
//  FavoritesViewModelTests.swift
//  GMSCommanderTests
//
//  Sık kullanılan klasörlerin ekleme, kaldırma ve kalıcılık davranışları.
//

import Foundation
import AppKit
import XCTest
@testable import GMS_Commander

@MainActor
final class FavoritesViewModelTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    func testAddMenuKeepsGroupActionsAndAvailability() throws {
        let folders = FavoriteGroup(name: "Folders", colorHex: 0, kind: .folder)
        let files = FavoriteGroup(name: "Files", colorHex: 0, kind: .file)
        var currentGroup: UUID?
        var selectionGroup: UUID?
        let view = FavoritesSidebarView.FavoritesAddMenu(
            groups: [folders, files],
            selectionCount: 1,
            canAddCurrent: { $0.id == folders.id },
            canAddSelection: { $0.id == files.id },
            addCurrent: { currentGroup = $0.id },
            addSelection: { selectionGroup = $0.id }
        )
        let coordinator = view.makeCoordinator()
        let menu = coordinator.makeMenu()
        let foldersMenu = try XCTUnwrap(menu.items.first?.submenu)
        let filesMenu = try XCTUnwrap(menu.items.last?.submenu)
        XCTAssertTrue(foldersMenu.items[0].isEnabled)
        XCTAssertFalse(foldersMenu.items[1].isEnabled)
        XCTAssertFalse(filesMenu.items[0].isEnabled)
        XCTAssertTrue(filesMenu.items[1].isEnabled)

        coordinator.perform(try XCTUnwrap(foldersMenu.items[0].action), with: foldersMenu.items[0])
        coordinator.perform(try XCTUnwrap(filesMenu.items[1].action), with: filesMenu.items[1])
        XCTAssertEqual(currentGroup, folders.id)
        XCTAssertEqual(selectionGroup, files.id)
    }

    override func setUpWithError() throws {
        directory = try TestSupport.makeTemporaryDirectory()
        suiteName = "com.gms.commander.favorites.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(try JSONEncoder().encode([FavoriteFolder]()), forKey: FavoritesViewModel.Keys.items)
        defaults.set(true, forKey: FavoritesViewModel.Keys.mountedVolumesSeeded)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        TestSupport.remove(directory)
    }

    func testAddsFolderAndRejectsDuplicateNormalizedPath() throws {
        let favorites = FavoritesViewModel(defaults: defaults)
        let folder = try TestSupport.makeDirectory(named: "Belgeler", in: directory)

        XCTAssertTrue(favorites.add(url: folder))
        XCTAssertTrue(favorites.contains(url: folder))
        XCTAssertFalse(favorites.add(path: folder.path + "/"))
        XCTAssertEqual(favorites.items.count, 1)
    }

    func testAddingExistingFavoriteToAnotherGroupMovesIt() throws {
        let favorites = FavoritesViewModel(defaults: defaults)
        let folder = try TestSupport.makeDirectory(named: "GMS_2026", in: directory)
        let projects = try XCTUnwrap(favorites.groups.first(where: { $0.name == L.t("favorites.group.projects") }))
        let initialGroupID = try XCTUnwrap(favorites.groups.first(where: { $0.id != projects.id })).id

        XCTAssertTrue(favorites.add(url: folder, to: initialGroupID))
        XCTAssertTrue(favorites.add(url: folder, to: projects.id))
        XCTAssertEqual(favorites.items.count, 1)
        XCTAssertEqual(favorites.items.first?.groupID, projects.id)
        XCTAssertFalse(favorites.add(url: folder, to: projects.id))
    }

    func testChangesPersistAcrossInstances() throws {
        let folder = try TestSupport.makeDirectory(named: "Belgeler", in: directory)
        let favorites = FavoritesViewModel(defaults: defaults)
        XCTAssertTrue(favorites.add(url: folder))

        let reloaded = FavoritesViewModel(defaults: defaults)
        XCTAssertEqual(reloaded.items.map(\.path), [folder.standardizedFileURL.path])
    }

    func testRemoveAndToggle() throws {
        let folder = try TestSupport.makeDirectory(named: "Belgeler", in: directory)
        let favorites = FavoritesViewModel(defaults: defaults)

        XCTAssertTrue(favorites.toggle(url: folder))
        XCTAssertTrue(favorites.contains(url: folder))
        XCTAssertFalse(favorites.toggle(url: folder))
        XCTAssertTrue(favorites.isEmpty)

        XCTAssertTrue(favorites.add(url: folder))
        favorites.remove(id: try XCTUnwrap(favorites.items.first?.id))
        XCTAssertTrue(favorites.isEmpty)
    }

    func testAddsFilesAndRejectsMissingPaths() throws {
        let file = try TestSupport.writeFile(named: "not-a-folder.txt", in: directory)
        let favorites = FavoritesViewModel(defaults: defaults)

        XCTAssertTrue(favorites.add(url: file))
        XCTAssertFalse(try XCTUnwrap(favorites.items.first).isDirectory)
        XCTAssertFalse(favorites.add(url: directory.appendingPathComponent("missing")))
        XCTAssertEqual(favorites.items.count, 1)
    }

    func testSuggestsQuickAccessAndApplicationsGroups() throws {
        let favorites = FavoritesViewModel(defaults: defaults)
        let folder = try TestSupport.makeDirectory(named: "GMS_2026", in: directory)
        let application = try TestSupport.makeDirectory(named: "Editor.app", in: directory)
        let quickAccessID = try XCTUnwrap(favorites.groups.first(where: { $0.role == .quickAccess })?.id)
        let applicationsID = try XCTUnwrap(favorites.groups.first(where: { $0.role == .applications })?.id)

        XCTAssertEqual(favorites.suggestedGroupID(for: folder), quickAccessID)
        XCTAssertEqual(favorites.suggestedGroupID(for: application), applicationsID)
        XCTAssertTrue(FavoriteFolder(path: application.path).isApplication)
        XCTAssertEqual(
            FavoriteFolder.displayName(for: "/Users/test/Documents"),
            L.t("favorites.folder.documents")
        )
    }

    func testRefreshMountedVolumesRemovesUnmountedDiskFavorites() throws {
        let diskGroup = FavoriteGroup(name: "Diskler", colorHex: 0xE0A84B, role: .disks)
        let staleVolume = FavoriteFolder(path: "/Volumes/Commander-Removed", groupID: diskGroup.id)
        defaults.set(try JSONEncoder().encode([diskGroup]), forKey: FavoritesViewModel.Keys.groups)
        defaults.set(try JSONEncoder().encode([staleVolume]), forKey: FavoritesViewModel.Keys.items)

        let favorites = FavoritesViewModel(defaults: defaults)
        favorites.refreshMountedVolumes()

        XCTAssertFalse(favorites.items.contains(where: { $0.path == staleVolume.path }))
    }

    func testCustomGroupsPersistAndMoveItems() throws {
        let folder = try TestSupport.makeDirectory(named: "Projeler", in: directory)
        let favorites = FavoritesViewModel(defaults: defaults)
        let firstGroupID = try XCTUnwrap(favorites.groups.first?.id)
        let customGroup = try XCTUnwrap(favorites.addGroup(name: "İş", colorHex: 0x42C98A))
        XCTAssertNil(favorites.addGroup(name: "İş", colorHex: 0x4F9CF9))

        XCTAssertTrue(favorites.add(url: folder, to: customGroup.id))
        let favorite = try XCTUnwrap(favorites.items.last)
        favorites.move(id: favorite.id, to: firstGroupID)

        let reloaded = FavoritesViewModel(defaults: defaults)
        XCTAssertEqual(reloaded.groups.last, customGroup)
        XCTAssertEqual(reloaded.items.last?.groupID, firstGroupID)
    }

    func testResetToDefaults() {
        let favorites = FavoritesViewModel(defaults: defaults)
        favorites.resetToDefaults()

        XCTAssertEqual(favorites.items.map(\.path), FavoritesViewModel.defaultItems().map(\.path))
        XCTAssertEqual(
            FavoritesViewModel(defaults: defaults).items.map(\.path),
            FavoritesViewModel.defaultItems().map(\.path)
        )
    }

    func testFavoriteFolderNormalizesPathAndDerivesDisplayName() {
        let favorite = FavoriteFolder(path: directory.path + "/")

        XCTAssertEqual(favorite.path, directory.standardizedFileURL.path)
        XCTAssertEqual(favorite.name, directory.lastPathComponent)
        XCTAssertEqual(FavoriteFolder.displayName(for: "/"), "/")
    }
}
