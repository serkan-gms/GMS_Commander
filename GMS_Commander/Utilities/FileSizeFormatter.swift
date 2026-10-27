//
//  FileSizeFormatter.swift
//  GMS_Commander
//
//  Dosya boyutlarını Türkçe biçimde gösteren yardımcı.
//  Ondalık ayırıcı olarak virgül kullanır ve 1000 tabanlı birimleri tercih eder.
//

import Foundation

/// Dosya boyutlarını okunabilir metne çeviren biçimlendirici.
enum FileSizeFormatter {
    /// Kullanılan birimler (1000 tabanlı).
    private static let units = ["bayt", "KB", "MB", "GB", "TB", "PB"]

    /// Türkçe sayı biçimlendiricisi. Ondalık ayırıcı virgüldür.
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    /// Verilen bayt değerini "1,5 MB" gibi bir metne çevirir.
    /// - Parameter bytes: Boyut (bayt).
    /// - Returns: Türkçe biçimlendirilmiş boyut metni.
    static func string(fromBytes bytes: Int64) -> String {
        guard bytes > 0 else {
            return "0 bayt"
        }

        if bytes < 1000 {
            return "\(formatNumber(Double(bytes), fractionDigits: 0)) bayt"
        }

        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1000, unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }

        // Küçük değerlerde bir ondalık basamak anlamlıdır; büyük değerlerde
        // gereksiz hassasiyet göstermemek için basamak sayısını azaltıyoruz.
        let fractionDigits = value < 10 ? 1 : 0
        let unit = units[unitIndex]
        return "\(formatNumber(value, fractionDigits: fractionDigits)) \(unit)"
    }

    /// Bir dosya öğesi için gösterilecek boyut metni. Klasörlerde "—" döner.
    static func string(for item: FileItem) -> String {
        if item.isDirectory && !item.isSymbolicLink {
            return "—"
        }
        return string(fromBytes: item.size)
    }

    /// Panel durum çubuğunda kullanılan toplam boyut metni.
    static func string(forTotalOf items: [FileItem]) -> String {
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        return string(fromBytes: total)
    }

    /// Sayıyı Türkçe ondalık ayırıcı ile metne çevirir.
    private static func formatNumber(_ value: Double, fractionDigits: Int) -> String {
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = fractionDigits
        if let text = numberFormatter.string(from: NSNumber(value: value)) {
            return text
        }
        return "\(value)"
    }
}
