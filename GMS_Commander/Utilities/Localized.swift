//
//  Localized.swift
//  GMS_Commander
//
//  Uygulamadaki tüm görünen metinlerin merkezi çeviri kaynağına erişimini sağlar.
//  Kaynak dosyası: Resources/tr.lproj/Localizable.strings
//

import Foundation

/// Türkçe yerelleştirme metinlerine erişim noktası.
enum L {
    /// Türkçe metin tablosu. Uygulama paketindeki `tr.lproj/Localizable.strings` dosyasından
    /// okunur. Paket bulunamazsa (ör. test çalıştırıcısı) anahtarın kendisi döner.
    private static let table: [String: String] = {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "tr.lproj"),
            Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "tr")
                .map { URL(fileURLWithPath: $0) },
            Bundle.main.resourceURL?.appendingPathComponent("tr.lproj/Localizable.strings")
        ]

        for case let url? in candidates {
            if let dictionary = NSDictionary(contentsOf: url) as? [String: String] {
                return dictionary
            }
        }
        return [:]
    }()

    /// Verilen anahtarın Türkçe karşılığını döndürür.
    /// - Parameter key: `Localizable.strings` içindeki anahtar.
    static func t(_ key: String) -> String {
        table[key] ?? Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    /// Biçimlendirme argümanları ile birlikte Türkçe metni döndürür.
    /// - Parameters:
    ///   - key: `Localizable.strings` içindeki biçim anahtarı.
    ///   - arguments: `%@` veya `%d` yer tutucuları için değerler.
    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        let format = table[key] ?? Bundle.main.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: "tr_TR"), arguments: arguments)
    }
}
