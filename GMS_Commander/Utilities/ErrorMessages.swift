//
//  ErrorMessages.swift
//  GMS_Commander
//
//  Dosya sistemi hatalarını kullanıcıya Türkçe açıklamalarla sunar.
//  Arayüzde gösterilecek başlık ve ayrıntı metinleri burada tek noktadan üretilir.
//

import Foundation
import Darwin

/// Uygulamanın kendi ürettiği, Türkçe açıklamalı dosya işlemi hataları.
enum FileOperationError: LocalizedError, Equatable {
    case destinationExists(URL)
    case destinationIsDirectory(URL)
    case destinationInsideSource(URL, URL)
    case verificationFailed(URL, URL)
    case invalidName(String)
    case sourceMissing(URL)
    case accessDenied(URL)
    case notADirectory(URL)
    case sameLocation(URL, URL)
    case cancelled
    case copyFailed(URL, String)
    case moveFailed(URL, String)
    case trashFailed(URL, String)
    case deleteFailed(URL, String)
    case searchFailed(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let url):
            return L.t("error.destinationExists", url.lastPathComponent)
        case .destinationIsDirectory(let url):
            return L.t("error.destinationIsDirectory", url.lastPathComponent)
        case .destinationInsideSource(let source, let destination):
            return L.t("error.destinationInsideSource", source.lastPathComponent, destination.path)
        case .verificationFailed(let source, let destination):
            return L.t("error.verificationFailed", source.lastPathComponent, destination.path)
        case .invalidName(let name):
            return L.t("error.invalidName", name)
        case .sourceMissing(let url):
            return L.t("error.sourceMissing", url.lastPathComponent)
        case .accessDenied(let url):
            return L.t("error.accessDenied", url.path)
        case .notADirectory(let url):
            return L.t("error.notADirectory", url.path)
        case .sameLocation(let source, let destination):
            return L.t("error.sameLocation", source.lastPathComponent, destination.path)
        case .cancelled:
            return L.t("error.cancelled")
        case .copyFailed(let url, let detail):
            return L.t("error.copyFailed", url.lastPathComponent, detail)
        case .moveFailed(let url, let detail):
            return L.t("error.moveFailed", url.lastPathComponent, detail)
        case .trashFailed(let url, let detail):
            return L.t("error.trashFailed", url.lastPathComponent, detail)
        case .deleteFailed(let url, let detail):
            return L.t("error.deleteFailed", url.lastPathComponent, detail)
        case .searchFailed(let detail):
            return L.t("error.searchFailed", detail)
        }
    }
}

/// Arayüzde gösterilecek hata bilgisi.
struct UserFacingAlert: Identifiable, Equatable {
    let id: UUID
    let title: String
    let message: String

    init(id: UUID = UUID(), title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }
}

/// Sistem hatalarını Türkçe metinlere eşleyen yardımcı.
enum ErrorMessages {
    /// Hata için kısa, kullanıcı dostu başlık.
    static func title(for error: Error) -> String {
        if let operationError = error as? FileOperationError {
            switch operationError {
            case .invalidName:
                return L.t("error.title.invalidName")
            case .accessDenied:
                return L.t("error.title.accessDenied")
            case .cancelled:
                return L.t("error.title.cancelled")
            case .destinationExists:
                return L.t("error.title.conflict")
            default:
                return L.t("error.title.generic")
            }
        }
        return L.t("error.title.generic")
    }

    /// Hata için ayrıntılı Türkçe açıklama.
    static func message(for error: Error) -> String {
        if let operationError = error as? FileOperationError {
            return operationError.errorDescription ?? L.t("error.unknown")
        }

        let nsError = error as NSError

        switch nsError.domain {
        case NSCocoaErrorDomain:
            if let description = cocoaMessage(for: nsError.code) {
                return description
            }
        case NSPOSIXErrorDomain:
            if let description = posixMessage(for: Int32(nsError.code)) {
                return description
            }
        default:
            break
        }

        // Kullanılabilir bir sistem açıklaması varsa onu da ekliyoruz.
        if !nsError.localizedDescription.isEmpty {
            return nsError.localizedDescription
        }
        return L.t("error.unknown")
    }

    /// İşlem hatasını `FileOperationFailure` tipine dönüştürür.
    static func failure(for url: URL, error: Error) -> FileOperationFailure {
        FileOperationFailure(url: url, message: message(for: error))
    }

    /// Cocoa hata kodlarını Türkçe metinlere eşler.
    private static func cocoaMessage(for code: Int) -> String? {
        switch CocoaError.Code(rawValue: code) {
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return L.t("error.notFound")
        case .fileWriteNoPermission, .fileReadNoPermission,
             .fileWriteInvalidFileName, .fileReadCorruptFile:
            return L.t("error.permission")
        case .fileWriteFileExists:
            return L.t("error.exists")
        case .fileWriteVolumeReadOnly:
            return L.t("error.readOnly")
        case .fileWriteOutOfSpace:
            return L.t("error.noSpace")
        case .fileWriteUnknown, .fileReadUnknown:
            return L.t("error.unknown")
        default:
            return nil
        }
    }

    /// POSIX hata kodlarını Türkçe metinlere eşler.
    private static func posixMessage(for code: Int32) -> String? {
        switch code {
        case EACCES, EPERM:
            return L.t("error.permission")
        case ENOENT:
            return L.t("error.notFound")
        case EEXIST:
            return L.t("error.exists")
        case ENOSPC:
            return L.t("error.noSpace")
        case EROFS:
            return L.t("error.readOnly")
        case ENOTDIR:
            return L.t("error.notDirectory")
        case EISDIR:
            return L.t("error.isDirectory")
        case EXDEV:
            return L.t("error.crossDevice")
        case ENOTEMPTY:
            return L.t("error.notEmpty")
        case ENAMETOOLONG:
            return L.t("error.nameTooLong")
        default:
            return nil
        }
    }
}
