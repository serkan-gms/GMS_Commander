//
//  DirectoryItem.swift
//  GMS_Commander
//
//  Bir klasörün listelenmesi sonucunda oluşan anlık görüntüyü (snapshot) tanımlar.
//  Panel görünümü bu değeri kullanarak dosya listesini ve durum çubuğunu besler.
//

import Foundation

/// Yol çubuğunda tıklanabilir bir klasör bileşeni.
struct PathBreadcrumb: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String

    var id: String { url.standardizedFileURL.path }

    /// Kökten geçerli klasöre kadar tıklanabilir yol bileşenlerini üretir.
    ///
    /// Yol her zaman disk kökünden başlar; ilk öğe disk adını taşır. Böylece
    /// yol çubuğunda disk simgesinin hemen yanında önce disk, ardından sırasıyla
    /// klasör adları görünür ve kullanıcı yolun tamamını okuyabilir.
    static func make(for directory: URL) -> [PathBreadcrumb] {
        let root = URL(fileURLWithPath: "/", isDirectory: true)
        let target = directory.standardizedFileURL

        var result = [PathBreadcrumb(url: root, name: "/")]
        var current = root
        for component in target.path.split(separator: "/") {
            current.appendPathComponent(String(component), isDirectory: true)
            result.append(PathBreadcrumb(url: current.standardizedFileURL, name: String(component)))
        }
        return result
    }
}

/// Bir klasörün içeriğinin belirli bir andaki hâli.
struct DirectorySnapshot: Sendable {
    /// Listelenen klasörün adresi.
    let url: URL

    /// Üst klasörün adresi. Kök klasörde `nil` olur.
    let parentURL: URL?

    /// Klasördeki öğeler (sıralanmamış ham liste).
    let items: [FileItem]

    /// Hacimde kullanılabilir boş alan (bayt). Okunamazsa `nil`.
    let volumeAvailableCapacity: Int64?

    /// Listeleme sırasında oluşan kritik hata (ör. izin reddi).
    let errorMessage: String?

    /// Klasördeki dosyaların toplam boyutu (yalnızca doğrudan alt öğeler).
    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    /// Klasör sayısı.
    var folderCount: Int {
        items.filter(\.isDirectory).count
    }

    /// Dosya sayısı.
    var fileCount: Int {
        items.filter { !$0.isDirectory }.count
    }

    /// Belirtilen adresteki öğeyi döndürür.
    func item(at url: URL) -> FileItem? {
        if let direct = items.first(where: { $0.url == url }) {
            return direct
        }
        let target = url.standardizedFileURL
        return items.first { $0.url.standardizedFileURL == target }
    }
}
