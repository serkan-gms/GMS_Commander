//
//  FileTransferTests.swift
//  GMSCommanderTests
//
//  Kopyalama ve taşıma servislerinin testleri.
//

import Foundation
import XCTest
@testable import GMS_Commander

final class FileTransferTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TestSupport.makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        TestSupport.remove(directory)
    }

    func testCopyFilePreservesContents() throws {
        let source = try TestSupport.writeFile(named: "kaynak.txt", contents: "merhaba dünya", in: directory)
        let destination = directory.appendingPathComponent("hedef.txt")

        try FileCopyService.copySync(source: source, to: destination, overwrite: false) { _ in }

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "merhaba dünya")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCopyDirectoryCopiesChildren() throws {
        let sourceDir = try TestSupport.makeDirectory(named: "Kaynak", in: directory)
        try TestSupport.writeFile(named: "a.txt", contents: "a", in: sourceDir)
        let nested = try TestSupport.makeDirectory(named: "Alt", in: sourceDir)
        try TestSupport.writeFile(named: "b.txt", contents: "b", in: nested)

        let destination = directory.appendingPathComponent("Hedef", isDirectory: true)
        try FileCopyService.copySync(source: sourceDir, to: destination, overwrite: false) { _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("a.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Alt/b.txt").path))
    }

    func testCopyPreservesSymbolicLink() throws {
        let target = try TestSupport.writeFile(named: "hedef.txt", in: directory)
        let link = directory.appendingPathComponent("baglanti.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let destination = directory.appendingPathComponent("kopya-baglanti.txt")
        try FileCopyService.copySync(source: link, to: destination, overwrite: false) { _ in }

        let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertEqual(values.isSymbolicLink, true)
    }

    func testCopyFailsWhenDestinationExistsWithoutOverwrite() throws {
        let source = try TestSupport.writeFile(named: "kaynak.txt", in: directory)
        let destination = try TestSupport.writeFile(named: "hedef.txt", in: directory)

        XCTAssertThrowsError(try FileCopyService.copySync(source: source, to: destination, overwrite: false) { _ in })
    }

    func testCopyOverwritesWhenRequested() throws {
        let source = try TestSupport.writeFile(named: "kaynak.txt", contents: "yeni", in: directory)
        let destination = try TestSupport.writeFile(named: "hedef.txt", contents: "eski", in: directory)

        try FileCopyService.copySync(source: source, to: destination, overwrite: true) { _ in }

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "yeni")
    }

    func testCopyReportsProgress() throws {
        let source = try TestSupport.writeFile(
            named: "buyuk.bin",
            contents: String(repeating: "x", count: 2_500_000),
            in: directory
        )
        let destination = directory.appendingPathComponent("buyuk-kopya.bin")

        final class Recorder: @unchecked Sendable {
            var total: Int64 = 0
        }
        let recorder = Recorder()

        try FileCopyService.copySync(source: source, to: destination, overwrite: false) { bytes in
            recorder.total += bytes
        }

        XCTAssertGreaterThan(recorder.total, 0)
        XCTAssertEqual(recorder.total, 2_500_000)
    }

    func testEstimateCountsBytesAndItems() throws {
        let fileURL = try TestSupport.writeFile(named: "a.txt", contents: "12345", in: directory)
        let estimate = FileCopyService.estimateSync(fileURL)

        XCTAssertEqual(estimate.bytes, 5)
        XCTAssertEqual(estimate.itemCount, 1)
    }

    func testMoveFileRemovesSource() throws {
        let source = try TestSupport.writeFile(named: "tasina.txt", contents: "veri", in: directory)
        let destination = directory.appendingPathComponent("tasinmis.txt")

        try FileMoveService.moveSync(source: source, to: destination, overwrite: false) { _ in }

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "veri")
    }

    func testMoveRejectsSameLocation() throws {
        let source = try TestSupport.writeFile(named: "ayni.txt", in: directory)
        XCTAssertThrowsError(try FileMoveService.moveSync(source: source, to: source, overwrite: false) { _ in }) { error in
            guard case FileOperationError.sameLocation = error else {
                return XCTFail("Beklenen hata sameLocation, gelen: \(error)")
            }
        }
    }

    func testMoveFailsForMissingSource() throws {
        let missing = directory.appendingPathComponent("yok.txt")
        XCTAssertThrowsError(try FileMoveService.moveSync(source: missing, to: directory.appendingPathComponent("x.txt"), overwrite: false) { _ in })
    }
}
