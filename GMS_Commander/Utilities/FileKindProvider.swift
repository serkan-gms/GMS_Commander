//
//  FileKindProvider.swift
//  GMS_Commander
//
//  Dosyaların Türkçe tür etiketlerini üretir (ör. "Klasör", "PDF Belgesi").
//  UniformTypeIdentifiers çerçevesiyle dosya uzantısına göre sınıflandırma yapılır.
//

import Foundation
import UniformTypeIdentifiers

/// Dosya türü etiketlerini üreten yardımcı.
enum FileKindProvider {
    /// Verilen adres için kullanıcıya gösterilecek tür etiketini döndürür.
    /// - Parameters:
    ///   - url: Dosyanın adresi.
    ///   - isDirectory: Öğe klasör mü?
    ///   - isSymbolicLink: Öğe sembolik bağlantı mı?
    ///   - isPackage: Öğe paket mi?
    static func kind(
        for url: URL,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        isPackage: Bool
    ) -> String {
        // Sembolik bağlantılar, hedeflerinin türü ne olursa olsun ayrı işaretlenir.
        if isSymbolicLink {
            return L.t("kind.symlink")
        }

        let fileExtension = url.pathExtension.lowercased()

        if isPackage {
            if fileExtension == "app" {
                return L.t("kind.application")
            }
            return L.t("kind.package")
        }

        if isDirectory {
            return L.t("kind.folder")
        }

        guard !fileExtension.isEmpty, let type = UTType(filenameExtension: fileExtension) else {
            return L.t("kind.file")
        }

        if type.conforms(to: .pdf) {
            return L.t("kind.pdf")
        }
        if type.conforms(to: .image) {
            return L.t("kind.image")
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return L.t("kind.video")
        }
        if type.conforms(to: .audio) {
            return L.t("kind.audio")
        }
        if type.conforms(to: .archive) || type.conforms(to: .zip) {
            return L.t("kind.archive")
        }
        if type.conforms(to: .spreadsheet) {
            return L.t("kind.spreadsheet")
        }
        if type.conforms(to: .presentation) {
            return L.t("kind.presentation")
        }
        if type.conforms(to: .sourceCode) {
            return L.t("kind.sourceCode")
        }
        if type.conforms(to: .plainText) || type.conforms(to: .text) {
            return L.t("kind.text")
        }
        if type.conforms(to: .font) {
            return L.t("kind.font")
        }
        if type.conforms(to: .diskImage) {
            return L.t("kind.diskImage")
        }
        if type.conforms(to: .executable) {
            return L.t("kind.executable")
        }

        return L.t("kind.namedFile", fileExtension.uppercased())
    }
}
