//
//  FileViewerService.swift
//  GMS_Commander
//
//  Dahili görüntüleyici ve düzenleyici için dosya okuma/yazma işlemleri.
//  Büyük dosyalar sınırlı miktarda okunur; ikili dosyalar metin olarak
//  açılmaz. Kodlama seçimi ve hex görünümü desteklenir.
//

import Foundation

// MARK: - Kodlama

/// Görüntüleyicide seçilebilen metin kodlamaları.
enum ViewerEncoding: String, CaseIterable, Identifiable, Sendable {
    case utf8
    case utf16
    case utf16LittleEndian
    case utf16BigEndian
    case isoLatin1
    case windows1254

    var id: String { rawValue }

    /// Foundation kodlama karşılığı.
    var stringEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .utf16: return .utf16
        case .utf16LittleEndian: return .utf16LittleEndian
        case .utf16BigEndian: return .utf16BigEndian
        case .isoLatin1: return .isoLatin1
        case .windows1254: return .windowsCP1254
        }
    }

    /// Kullanıcıya gösterilen ad.
    var localizedName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16: return "UTF-16"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .utf16BigEndian: return "UTF-16 BE"
        case .isoLatin1: return "ISO Latin-1"
        case .windows1254: return "Windows-1254 (Türkçe)"
        }
    }

    /// Veri başındaki BOM işaretine göre kodlama tahmin eder.
    static func detect(from data: Data) -> ViewerEncoding? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return .utf8
        }
        if bytes.count >= 2 {
            if bytes[0] == 0xFF, bytes[1] == 0xFE { return .utf16LittleEndian }
            if bytes[0] == 0xFE, bytes[1] == 0xFF { return .utf16BigEndian }
        }
        return nil
    }
}

// MARK: - Görüntüleme belgesi

/// Görüntüleyiciye yüklenen metin ve bilgileri.
struct ViewerDocument: Sendable {
    /// Metin içeriği (gerekirse kısaltılmış).
    let text: String
    /// Kullanılan kodlama.
    let encoding: ViewerEncoding
    /// Dosyanın tamamı okunmadı mı?
    let isTruncated: Bool
    /// Dosyanın toplam boyutu.
    let byteCount: Int64
    /// İkili dosya mı?
    let isBinary: Bool
}

// MARK: - Hatalar

/// Görüntüleyici/düzenleyici hataları.
enum ViewerError: LocalizedError {
    case unreadable(String)
    case encodingFailed(String)
    case binaryFile
    case tooLarge(String)
    case fileChanged
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            return "Dosya okunamadı: \(detail)"
        case .encodingFailed(let encoding):
            return "Dosya \(encoding) kodlamasıyla çözülemedi. Farklı bir kodlama seçin."
        case .binaryFile:
            return "Bu dosya ikili (binary) görünüyor; metin düzenleyiciyle açılmaz."
        case .tooLarge(let size):
            return "Dosya düzenleyici için çok büyük (\(size)). Görüntüleyiciyi veya harici bir düzenleyiciyi kullanın."
        case .fileChanged:
            return "Dosya siz açtıktan sonra başka bir uygulamada değişmiş. Kaydetmek bu değişikliklerin üzerine yazar."
        case .saveFailed(let detail):
            return "Dosya kaydedilemedi: \(detail)"
        }
    }
}

// MARK: - Servis

/// Dosya okuma/yazma servisi.
struct FileViewerService: Sendable {
    /// Görüntüleyicide en fazla okunacak bayt (8 MB).
    static let maximumPreviewBytes = 8 * 1024 * 1024
    /// Hex görünümünde en fazla okunacak bayt (512 KB).
    static let maximumHexBytes = 512 * 1024
    /// Düzenleyicide izin verilen en büyük dosya (16 MB).
    static let maximumEditableBytes: Int64 = 16 * 1024 * 1024

    /// Bir veri bloğunun ikili olup olmadığını tahmin eder.
    /// UTF-16 BOM'u metin sayılır; NUL baytı veya yoğun denetim karakteri
    /// ikili dosya işareti kabul edilir.
    static func isBinary(_ data: Data, url: URL? = nil) -> Bool {
        if ViewerEncoding.detect(from: data) != nil { return false }
        guard !data.isEmpty else { return false }

        var controlCount = 0
        for byte in data.prefix(8192) {
            if byte == 0 { return true }
            if byte < 0x09 || (byte > 0x0D && byte < 0x20) {
                controlCount += 1
            }
        }
        let sample = min(data.count, 8192)
        return sample > 0 && Double(controlCount) / Double(sample) > 0.05
    }

    /// Metin dosyasını okur.
    /// - Parameters:
    ///   - url: Dosya.
    ///   - encoding: Zorunlu kodlama; `nil` ise BOM/UTF-8 denenir.
    ///   - maximumBytes: Okunacak en fazla bayt.
    /// - Returns: Belge.
    func loadText(
        url: URL,
        encoding requested: ViewerEncoding? = nil,
        maximumBytes: Int = FileViewerService.maximumPreviewBytes
    ) throws -> ViewerDocument {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let totalBytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ViewerError.unreadable(error.localizedDescription)
        }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: maximumBytes)) ?? Data()
        let truncated = totalBytes > Int64(data.count)
        let binary = Self.isBinary(data, url: url)

        let encoding: ViewerEncoding
        if let requested {
            encoding = requested
        } else if let detected = ViewerEncoding.detect(from: data) {
            encoding = detected
        } else if String(data: data, encoding: .utf8) != nil {
            encoding = .utf8
        } else {
            encoding = .isoLatin1
        }

        guard let text = String(data: data, encoding: encoding.stringEncoding) else {
            throw ViewerError.encodingFailed(encoding.localizedName)
        }

        return ViewerDocument(
            text: text,
            encoding: encoding,
            isTruncated: truncated,
            byteCount: totalBytes,
            isBinary: binary
        )
    }

    /// Dosyanın hex görünümünü üretir.
    /// - Parameters:
    ///   - url: Dosya.
    ///   - maximumBytes: Okunacak en fazla bayt.
    /// - Returns: Hex metni ve kısaltma bilgisi.
    func hexDump(
        url: URL,
        maximumBytes: Int = FileViewerService.maximumHexBytes
    ) throws -> (text: String, isTruncated: Bool, byteCount: Int64) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let totalBytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ViewerError.unreadable(error.localizedDescription)
        }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: maximumBytes)) ?? Data()
        let truncated = totalBytes > Int64(data.count)

        var lines: [String] = []
        lines.reserveCapacity(data.count / 16 + 1)
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let end = min(offset + 16, bytes.count)
            var hex = ""
            var ascii = ""
            for index in 0..<16 {
                if offset + index < end {
                    let byte = bytes[offset + index]
                    hex += String(format: "%02X ", byte)
                    ascii += (byte >= 0x20 && byte < 0x7F) ? String(UnicodeScalar(byte)) : "."
                } else {
                    hex += "   "
                    ascii += " "
                }
                if index == 7 { hex += " " }
            }
            lines.append(String(format: "%08X  ", offset) + hex + " |" + ascii + "|")
            offset += 16
        }

        return (lines.joined(separator: "\n"), truncated, totalBytes)
    }

    /// Metni belirtilen kodlamayla atomik olarak kaydeder.
    /// - Parameters:
    ///   - text: Yeni içerik.
    ///   - url: Dosya.
    ///   - encoding: Kodlama.
    ///   - expectedModificationDate: Dosyanın açılışta okunan tarihi; farklıysa
    ///     `ViewerError.fileChanged` fırlatılır. `nil` ise denetlenmez.
    static func save(
        text: String,
        to url: URL,
        encoding: ViewerEncoding,
        expectedModificationDate: Date? = nil
    ) throws {
        if let expectedModificationDate {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let current = attributes?[.modificationDate] as? Date
            if let current, abs(current.timeIntervalSince(expectedModificationDate)) > 0.5 {
                throw ViewerError.fileChanged
            }
        }

        guard let data = text.data(using: encoding.stringEncoding) else {
            throw ViewerError.encodingFailed(encoding.localizedName)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attributes?[.posixPermissions] as? NSNumber

        do {
            try data.write(to: url, options: .atomic)
            if let permissions {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: permissions],
                    ofItemAtPath: url.path
                )
            }
        } catch {
            throw ViewerError.saveFailed(error.localizedDescription)
        }
    }

    /// Dosyadaki satır başlangıçlarının karakter indekslerini üretir.
    static func lineStartOffsets(in text: NSString) -> [Int] {
        var offsets: [Int] = [0]
        offsets.reserveCapacity(max(text.length / 40, 16))
        var index = 0
        while index < text.length {
            let newline = text.range(of: "\n", options: [], range: NSRange(location: index, length: text.length - index))
            if newline.location == NSNotFound { break }
            let next = newline.location + newline.length
            if next < text.length {
                offsets.append(next)
            }
            index = next
        }
        return offsets
    }
}
