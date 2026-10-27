//
//  FilePropertiesTests.swift
//  GMSCommanderTests
//
//  Dosya özellikleri ve klasör boyutu ölçümü testleri.
//

import Foundation
import XCTest
@testable import GMS_Commander

final class FilePropertiesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try TestSupport.makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        TestSupport.remove(directory)
    }

    func testLoadFileProperties() throws {
        let fileURL = try TestSupport.writeFile(named: "ozellik.txt", contents: "1234567890", in: directory)
        let properties = try XCTUnwrap(FileProperties.load(for: fileURL))

        XCTAssertEqual(properties.name, "ozellik.txt")
        XCTAssertFalse(properties.sizeText.isEmpty)
        XCTAssertTrue(properties.isReadable)
        XCTAssertNil(properties.itemCountText)
        XCTAssertFalse(properties.permissionsText.isEmpty)
    }

    func testLoadDirectoryPropertiesIncludesItemCount() throws {
        let folderURL = try TestSupport.makeDirectory(named: "Klasör", in: directory)
        try TestSupport.writeFile(named: "a.txt", in: folderURL)
        try TestSupport.writeFile(named: "b.txt", in: folderURL)

        let properties = try XCTUnwrap(FileProperties.load(for: folderURL, includeFolderSize: true))
        XCTAssertNotNil(properties.itemCountText)
    }

    func testLoadReturnsNilForMissingPath() throws {
        let missing = directory.appendingPathComponent("yok.txt")
        XCTAssertNil(FileProperties.load(for: missing))
    }

    func testFolderMeasurementCountsBytesAndItems() throws {
        let folderURL = try TestSupport.makeDirectory(named: "Ölçüm", in: directory)
        try TestSupport.writeFile(named: "a.txt", contents: "12345", in: folderURL)
        try TestSupport.writeFile(named: "b.txt", contents: "123", in: folderURL)

        let measurement = FileProperties.folderMeasurement(for: folderURL)
        XCTAssertEqual(measurement.bytes, 8)
        XCTAssertEqual(measurement.itemCount, 2)
    }
}
