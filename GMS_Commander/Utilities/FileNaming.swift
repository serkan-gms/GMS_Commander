//
//  FileNaming.swift
//  GMS_Commander
//
//  Dosya adı çakışmalarında benzersiz ad üretmek için ortak yardımcı.
//

import Foundation

/// Dosya adlandırma yardımcıları.
enum FileNaming {
    /// Hedefte aynı ada sahip bir öğe varsa "ad 2.uzantı" biçiminde
    /// benzersiz bir ad üretir. Ad en fazla 9999 kez denenir; yine de
    /// boşta ad bulunamazsa son üretilen ad döner.
    /// - Parameters:
    ///   - name: İstenen dosya/klasör adı.
    ///   - directory: Hedef klasör.
    ///   - fileManager: Testlerde değiştirilebilir dosya yöneticisi.
    /// - Returns: Hedef klasörde kullanılabilir adres.
    static func uniqueDestination(
        for name: String,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        var last = candidate
        while counter <= 9999 {
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let url = directory.appendingPathComponent(newName)
            if !fileManager.fileExists(atPath: url.path) {
                return url
            }
            last = url
            counter += 1
        }
        return last
    }
}
