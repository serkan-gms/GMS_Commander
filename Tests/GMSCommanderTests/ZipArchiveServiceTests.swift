//
//  ZipArchiveServiceTests.swift
//  GMSCommanderTests
//
//  ZIP sıkıştırma servisi testleri.
//

import Foundation
import XCTest
@testable import GMS_Commander

final class ZipArchiveServiceTests: XCTestCase {
    func testCompressesMultipleFilesAndFolders() async throws {
        let directory = try TestSupport.makeTemporaryDirectory()
        defer { TestSupport.remove(directory) }

        let first = try TestSupport.writeFile(named: "bir dosya.txt", contents: "bir", in: directory)
        let folder = try TestSupport.makeDirectory(named: "klasor", in: directory)
        try TestSupport.writeFile(named: "ic.txt", contents: "iki", in: folder)
        let destination = directory.appendingPathComponent("sonuc.zip")

        try await ZipArchiveService().compress(sources: [first, folder], to: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", destination.path]
        process.standardOutput = output
        try process.run()
        let listing = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(listing.contains("bir dosya.txt"))
        XCTAssertTrue(listing.contains("klasor/ic.txt"))
    }
}
