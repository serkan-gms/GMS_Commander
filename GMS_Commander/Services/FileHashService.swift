//
//  FileHashService.swift
//  GMS_Commander
//
//  Dosyaların SHA-256 özetini parça parça hesaplar. Büyük dosyalar belleğe
//  tamamen alınmaz; işlem iptal edilebilir.
//

import Foundation
import CryptoKit

/// Hash hesaplama hatası.
enum FileHashError: LocalizedError {
    case unreadable(String)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return "Dosya okunamadı: \(name)"
        case .readFailed(let detail):
            return "Hash hesaplanırken okuma hatası: \(detail)"
        }
    }
}

/// Tek bir dosyanın hash sonucu.
struct FileHashResult: Identifiable, Sendable {
    let url: URL
    /// Hesaplanan SHA-256 (küçük harf hex) veya hata nedeniyle `nil`.
    let digest: String?
    /// Hesaplama sırasında oluşan hata metni.
    let errorMessage: String?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// SHA-256 hesaplayan servis.
struct FileHashService: Sendable {
    /// Okuma parçası boyutu (1 MB).
    static let chunkSize = 1024 * 1024

    /// Bir dosyanın SHA-256 özetini hesaplar.
    /// - Parameters:
    ///   - url: Dosya.
    ///   - control: İptal/duraklatma denetimi.
    ///   - progress: Okunan bayt sayısıyla periyodik olarak çağrılır.
    /// - Returns: Küçük harfli hex özet.
    static func sha256(
        of url: URL,
        control: TransferControl? = nil,
        progress: (@Sendable (Int64) -> Void)? = nil
    ) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw FileHashError.unreadable(url.lastPathComponent)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        var processed: Int64 = 0
        do {
            while true {
                try control?.waitIfPaused()
                let data = try handle.read(upToCount: Self.chunkSize) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
                processed += Int64(data.count)
                progress?(processed)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FileHashError.readFailed(error.localizedDescription)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Birden çok dosya için hash hesaplar (eşzamanlı; arka planda çağrılmalıdır).
    /// - Parameters:
    ///   - urls: Dosyalar.
    ///   - control: İptal denetimi.
    ///   - progress: Tamamlanan dosya sayısı.
    /// - Returns: Her dosya için sonuç; klasörler atlanır.
    static func hashes(
        for urls: [URL],
        control: TransferControl? = nil,
        progress: (@Sendable (Int) -> Void)? = nil
    ) -> [FileHashResult] {
        var results: [FileHashResult] = []
        for (index, url) in urls.enumerated() {
            if control?.isCancelled == true { break }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory { continue }
            do {
                let digest = try sha256(of: url, control: control)
                results.append(FileHashResult(url: url, digest: digest, errorMessage: nil))
            } catch is CancellationError {
                break
            } catch {
                results.append(
                    FileHashResult(
                        url: url,
                        digest: nil,
                        errorMessage: ErrorMessages.message(for: error)
                    )
                )
            }
            progress?(index + 1)
        }
        return results
    }
}
