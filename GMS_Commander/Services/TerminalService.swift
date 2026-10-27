//
//  TerminalService.swift
//  GMS_Commander
//
//  Sistem Terminal uygulamasını verilen klasörde açar.
//

import AppKit

/// Terminal uygulamasını başlatan yardımcı.
enum TerminalService {
    /// Terminal uygulamasının paket kimliği.
    private static let bundleIdentifier = "com.apple.Terminal"

    /// Terminal kurulu mu?
    static var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// Verilen adres için açılacak klasörü belirler.
    ///
    /// Klasör yolu verilirse kendisi, dosya yolu verilirse üst klasörü döner.
    /// Yol mevcut değilse `nil` döner.
    /// - Parameter url: Hedef adres.
    static func resolvedDirectory(for url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue ? standardized : standardized.deletingLastPathComponent()
    }

    /// Verilen adreste yeni bir Terminal penceresi açar.
    /// - Parameter directory: Açılacak klasör. Dosya yolu verilirse üst klasörü kullanılır.
    /// - Returns: Başlatma isteği gönderilebildiyse `true`.
    @discardableResult
    static func open(at directory: URL) -> Bool {
        guard let target = resolvedDirectory(for: directory) else { return false }

        // `/usr/bin/open -a Terminal <yol>` en taşınabilir yöntemdir: Terminal hazır
        // değilse sistem uygulamayı başlatır, hazırsa yeni pencere açar.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", target.path]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
