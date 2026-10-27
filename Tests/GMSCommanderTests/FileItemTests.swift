//
//  FileItemTests.swift
//  GMSCommanderTests
//
//  `FileItem` modeli, sıralama kuralları ve klasör anlık görüntüsü testleri.
//

import Foundation
import XCTest
@testable import GMS_Commander

final class FileItemTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TestSupport.makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        TestSupport.remove(directory)
    }

    func testMakeReadsBasicMetadata() throws {
        let fileURL = try TestSupport.writeFile(named: "rapor.txt", contents: "12345", in: directory)
        let item = try XCTUnwrap(FileItem.make(url: fileURL))

        XCTAssertEqual(item.name, "rapor.txt")
        XCTAssertFalse(item.isDirectory)
        XCTAssertFalse(item.isSymbolicLink)
        XCTAssertFalse(item.isHidden)
        XCTAssertEqual(item.size, 5)
        XCTAssertNotNil(item.modificationDate)
        XCTAssertTrue(item.kind.contains("TXT") || item.kind.contains("Metin"))
    }

    func testHiddenFileIsDetected() throws {
        let fileURL = try TestSupport.writeFile(named: ".gizli", in: directory)
        let item = try XCTUnwrap(FileItem.make(url: fileURL))
        XCTAssertTrue(item.isHidden)
    }

    func testDirectoryHasZeroSize() throws {
        let folderURL = try TestSupport.makeDirectory(named: "Klasör", in: directory)
        let item = try XCTUnwrap(FileItem.make(url: folderURL))
        XCTAssertTrue(item.isDirectory)
        XCTAssertEqual(item.size, 0)
        XCTAssertTrue(item.isNavigable)
        XCTAssertEqual(FileSizeFormatter.string(for: item), "—")
    }

    func testSymbolicLinkIsDetected() throws {
        let target = try TestSupport.writeFile(named: "hedef.txt", in: directory)
        let link = directory.appendingPathComponent("baglanti.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let item = try XCTUnwrap(FileItem.make(url: link))
        XCTAssertTrue(item.isSymbolicLink)
        XCTAssertEqual(item.fileExtension, "txt")
    }

    func testSortsFoldersFirstByName() throws {
        try TestSupport.makeDirectory(named: "zKlasör", in: directory)
        try TestSupport.writeFile(named: "aDosya.txt", in: directory)
        try TestSupport.writeFile(named: "bDosya.txt", in: directory)

        let items = try loadItems()
        let sorted = FileItem.sorted(items, by: .name, ascending: true, foldersFirst: true)

        XCTAssertEqual(sorted.first?.name, "zKlasör")
        XCTAssertEqual(sorted.map(\.name), ["zKlasör", "aDosya.txt", "bDosya.txt"])
    }

    func testSortsByNameDescendingWithoutFoldersFirst() throws {
        try TestSupport.makeDirectory(named: "Klasör", in: directory)
        try TestSupport.writeFile(named: "a.txt", in: directory)
        try TestSupport.writeFile(named: "b.txt", in: directory)

        let items = try loadItems()
        let sorted = FileItem.sorted(items, by: .name, ascending: false, foldersFirst: false)

        XCTAssertEqual(sorted.map(\.name), ["Klasör", "b.txt", "a.txt"])
    }

    func testSortsBySizeAndDate() throws {
        try TestSupport.writeFile(named: "kucuk.txt", contents: "1", in: directory)
        try TestSupport.writeFile(named: "buyuk.txt", contents: String(repeating: "x", count: 500), in: directory)

        let items = try loadItems()
        let bySize = FileItem.sorted(items, by: .size, ascending: true, foldersFirst: false)
        XCTAssertEqual(bySize.map(\.name), ["kucuk.txt", "buyuk.txt"])

        let byDate = FileItem.sorted(items, by: .date, ascending: true, foldersFirst: false)
        XCTAssertEqual(byDate.count, 2)
    }

    func testSortIsDeterministicForEqualValues() throws {
        try TestSupport.writeFile(named: "b.txt", contents: "aynı", in: directory)
        try TestSupport.writeFile(named: "a.txt", contents: "aynı", in: directory)

        let items = try loadItems()
        let first = FileItem.sorted(items, by: .size, ascending: true, foldersFirst: true).map(\.name)
        let second = FileItem.sorted(items.reversed(), by: .size, ascending: true, foldersFirst: true).map(\.name)

        XCTAssertEqual(first, second)
    }

    func testSnapshotStatistics() throws {
        try TestSupport.makeDirectory(named: "Alt", in: directory)
        try TestSupport.writeFile(named: "bir.txt", contents: "12345", in: directory)
        try TestSupport.writeFile(named: "iki.txt", contents: "1234567890", in: directory)

        let snapshot = try FileManagerService.listDirectorySync(at: directory, includeHidden: false)

        XCTAssertEqual(snapshot.folderCount, 1)
        XCTAssertEqual(snapshot.fileCount, 2)
        XCTAssertEqual(snapshot.totalSize, 15)
        XCTAssertEqual(snapshot.item(at: directory.appendingPathComponent("bir.txt"))?.name, "bir.txt")
        XCTAssertNil(snapshot.errorMessage)
        XCTAssertNotNil(snapshot.parentURL)
    }

    private func loadItems() throws -> [FileItem] {
        let snapshot = try FileManagerService.listDirectorySync(at: directory, includeHidden: false)
        return snapshot.items
    }
}
