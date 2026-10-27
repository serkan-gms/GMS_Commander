//
//  FileManagerServiceTests.swift
//  GMSCommanderTests
//
//  Listeleme, klasör oluşturma, yeniden adlandırma ve silme testleri.
//

import Foundation
import XCTest
@testable import GMS_Commander

final class FileManagerServiceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TestSupport.makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        TestSupport.remove(directory)
    }

    func testListDirectoryHidesHiddenItems() throws {
        try TestSupport.writeFile(named: "gorunur.txt", in: directory)
        try TestSupport.writeFile(named: ".gizli.txt", in: directory)

        let visible = try FileManagerService.listDirectorySync(at: directory, includeHidden: false)
        let all = try FileManagerService.listDirectorySync(at: directory, includeHidden: true)

        XCTAssertEqual(visible.items.count, 1)
        XCTAssertEqual(all.items.count, 2)
    }

    func testListDirectoryRejectsFileURL() throws {
        let fileURL = try TestSupport.writeFile(named: "dosya.txt", in: directory)
        XCTAssertThrowsError(try FileManagerService.listDirectorySync(at: fileURL, includeHidden: false)) { error in
            guard case FileOperationError.notADirectory = error else {
                return XCTFail("Beklenen hata notADirectory, gelen: \(error)")
            }
        }
    }

    func testCreateDirectoryUsesPreferredName() throws {
        let created = try FileManagerService.createDirectorySync(in: directory, preferredName: "Yeni Klasör")
        XCTAssertEqual(created.lastPathComponent, "Yeni Klasör")
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path))
    }

    func testCreateDirectoryAvoidsNameCollision() throws {
        let first = try FileManagerService.createDirectorySync(in: directory, preferredName: "Klasör")
        let second = try FileManagerService.createDirectorySync(in: directory, preferredName: "Klasör")

        XCTAssertEqual(first.lastPathComponent, "Klasör")
        XCTAssertEqual(second.lastPathComponent, "Klasör 2")
    }

    func testValidateNameAcceptsValidNames() throws {
        XCTAssertNoThrow(try FileManagerService.validateName("rapor 2025.txt"))
        XCTAssertNoThrow(try FileManagerService.validateName(".gizli"))
    }

    func testValidateNameRejectsInvalidNames() {
        for invalid in ["", ".", "..", "a/b.txt", "a:b.txt"] {
            XCTAssertThrowsError(try FileManagerService.validateName(invalid), "Reddedilmeliydi: \(invalid)")
        }
    }

    func testRenameMovesItem() throws {
        let fileURL = try TestSupport.writeFile(named: "eski.txt", in: directory)
        let renamed = try FileManagerService.renameSync(fileURL, to: "yeni.txt")

        XCTAssertEqual(renamed.lastPathComponent, "yeni.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testRenameRejectsExistingDestination() throws {
        let fileURL = try TestSupport.writeFile(named: "bir.txt", in: directory)
        try TestSupport.writeFile(named: "iki.txt", in: directory)

        XCTAssertThrowsError(try FileManagerService.renameSync(fileURL, to: "iki.txt")) { error in
            guard case FileOperationError.destinationExists = error else {
                return XCTFail("Beklenen hata destinationExists, gelen: \(error)")
            }
        }
    }

    func testUniqueDestinationGeneratesSuffix() throws {
        try TestSupport.writeFile(named: "rapor.txt", in: directory)
        try TestSupport.writeFile(named: "rapor 2.txt", in: directory)

        let destination = FileManagerService.uniqueDestination(for: "rapor.txt", in: directory)
        XCTAssertEqual(destination.lastPathComponent, "rapor 3.txt")
    }

    func testUniqueDestinationKeepsNameWhenFree() throws {
        let destination = FileManagerService.uniqueDestination(for: "serbest.txt", in: directory)
        XCTAssertEqual(destination.lastPathComponent, "serbest.txt")
    }

    func testDeletePermanentlyRemovesItem() throws {
        let fileURL = try TestSupport.writeFile(named: "sil.txt", in: directory)
        try FileManagerService.deletePermanentlySync(fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testIsSameLocationAndIsRoot() throws {
        let fileURL = try TestSupport.writeFile(named: "a.txt", in: directory)
        XCTAssertTrue(FileManagerService.isSameLocation(fileURL, fileURL))
        XCTAssertFalse(FileManagerService.isSameLocation(fileURL, directory))

        XCTAssertTrue(FileManagerService.isRoot(URL(fileURLWithPath: "/")))
        XCTAssertFalse(FileManagerService.isRoot(directory))
    }
}
