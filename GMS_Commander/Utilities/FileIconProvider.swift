//
//  FileIconProvider.swift
//  GMS_Commander
//
//  Dosya satırlarında gösterilecek simgeleri macOS'tan alır ve önbelleğe alır.
//  Simge üretimi yalnızca ana iş parçacığında yapılır.
//

import AppKit

/// Dosya türü simgelerini sağlayan önbellekli yardımcı.
@MainActor
enum FileIconProvider {
    /// Aynı yol için tekrar tekrar simge üretilmesini engelleyen önbellek.
    private static let cache = NSCache<NSString, NSImage>()

    /// Verilen öğe için simge döndürür.
    /// - Parameter item: Listelenecek dosya veya klasör.
    static func icon(for item: FileItem) -> NSImage {
        let key = item.url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        icon.size = NSSize(width: 16, height: 16)
        cache.setObject(icon, forKey: key)
        return icon
    }

    /// Verilen adres için simge döndürür.
    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        cache.setObject(icon, forKey: key)
        return icon
    }

    /// Simge görünümü için istenen boyutta simge döndürür.
    static func icon(for item: FileItem, pointSize: CGFloat) -> NSImage {
        let key = "\(item.url.path)|\(Int(pointSize))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        icon.size = NSSize(width: pointSize, height: pointSize)
        cache.setObject(icon, forKey: key)
        return icon
    }

    /// Önbelleği temizler (ör. Ayarlar > Yenile).
    static func clearCache() {
        cache.removeAllObjects()
    }
}
