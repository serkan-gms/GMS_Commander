//
//  TestSupport.swift
//  GMSCommanderTests
//
//  Testlerde kullanılan ortak yardımcılar.
//

import Darwin
import Foundation
import XCTest
@testable import GMS_Commander

/// Geçici klasörlerle çalışan testler için yardımcılar.
enum TestSupport {
    /// Benzersiz bir geçici klasör oluşturur.
    static func makeTemporaryDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("GMSCommanderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // macOS'ta /var bir takma addır; dosya sistemi /private/var yolu döndürür.
        // Karşılaştırmaların tutarlı olması için gerçek yolu kullanıyoruz.
        return realPath(base)
    }

    /// Dosya sisteminin bildirdiği gerçek yolu döndürür (/var → /private/var).
    /// Foundation'ın `resolvingSymlinksInPath()` fonksiyonu bu takma adı çözmediği için POSIX kullanılır.
    static func realPath(_ url: URL) -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(url.path, &buffer) != nil else { return url }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    /// Klasörü sessizce siler.
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Verilen klasörde bir dosya oluşturur.
    @discardableResult
    static func writeFile(named name: String, contents: String = "içerik", in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.data(using: .utf8)?.write(to: url)
        return url
    }

    /// Verilen klasörde bir alt klasör oluşturur.
    @discardableResult
    static func makeDirectory(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
