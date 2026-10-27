//
//  FileProperties.swift
//  GMS_Commander
//
//  Özellikler penceresinde gösterilen dosya bilgilerini toplar.
//  Klasörler için toplam boyut ve öğe sayısı isteğe bağlı olarak hesaplanır.
//

import Foundation
import Darwin

/// Bir dosya veya klasörün ayrıntılı özellikleri.
struct FileProperties: Sendable, Equatable {
    var name: String
    var path: String
    var kind: String
    var sizeText: String
    var itemCountText: String?
    var createdText: String
    var modifiedText: String
    var permissionsText: String
    var ownerText: String
    var groupText: String
    var isSymbolicLink: Bool
    var symlinkDestination: String?
    var isPackage: Bool
    var isHidden: Bool
    var isReadable: Bool
    var isWritable: Bool
    var isExecutable: Bool
    var extendedAttributeCount: Int
    var volumeName: String?
}

extension FileProperties {
    /// Verilen adres için özellikleri toplar.
    /// - Parameters:
    ///   - url: Dosya adresi.
    ///   - includeFolderSize: Klasörlerin toplam boyutu hesaplansın mı? (büyük klasörlerde yavaş olabilir)
    /// - Returns: Özellik bilgisi; dosya okunamazsa `nil`.
    static func load(for url: URL, includeFolderSize: Bool = true) -> FileProperties? {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .isHiddenKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isReadableKey,
            .isWritableKey,
            .isExecutableKey,
            .volumeNameKey
        ]
        let values = try? url.resourceValues(forKeys: resourceKeys)
        let isDirectory = values?.isDirectory ?? false
        let isSymbolicLink = values?.isSymbolicLink ?? false
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue

        var symlinkDestination: String?
        if isSymbolicLink {
            symlinkDestination = try? fileManager.destinationOfSymbolicLink(atPath: url.path)
        }

        var sizeText: String
        var itemCountText: String?

        if isDirectory && !isSymbolicLink {
            if includeFolderSize {
                let measurement = folderMeasurement(for: url)
                sizeText = FileSizeFormatter.string(fromBytes: measurement.bytes)
                itemCountText = L.t("properties.itemCount", measurement.itemCount)
            } else {
                sizeText = "—"
            }
        } else {
            let size = Int64(values?.fileSize ?? 0)
            sizeText = FileSizeFormatter.string(fromBytes: size)
        }

        return FileProperties(
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            path: url.path,
            kind: FileKindProvider.kind(
                for: url,
                isDirectory: isDirectory,
                isSymbolicLink: isSymbolicLink,
                isPackage: values?.isPackage ?? false
            ),
            sizeText: sizeText,
            itemCountText: itemCountText,
            createdText: DateFormatterHelper.detailedString(from: values?.creationDate ?? attributes[.creationDate] as? Date),
            modifiedText: DateFormatterHelper.detailedString(
                from: values?.contentModificationDate ?? attributes[.modificationDate] as? Date
            ),
            permissionsText: permissions.map { "\(PermissionsFormatter.symbolicString(fromMode: $0)) (\(PermissionsFormatter.octalString(fromMode: $0)))" } ?? "—",
            ownerText: attributes[.ownerAccountName] as? String ?? "—",
            groupText: attributes[.groupOwnerAccountName] as? String ?? "—",
            isSymbolicLink: isSymbolicLink,
            symlinkDestination: symlinkDestination,
            isPackage: values?.isPackage ?? false,
            isHidden: values?.isHidden ?? url.lastPathComponent.hasPrefix("."),
            isReadable: values?.isReadable ?? fileManager.isReadableFile(atPath: url.path),
            isWritable: values?.isWritable ?? fileManager.isWritableFile(atPath: url.path),
            isExecutable: values?.isExecutable ?? fileManager.isExecutableFile(atPath: url.path),
            extendedAttributeCount: extendedAttributeCount(for: url),
            volumeName: values?.volumeName
        )
    }

    /// Klasörün toplam boyutunu ve öğe sayısını hesaplar.
    static func folderMeasurement(for url: URL) -> (bytes: Int64, itemCount: Int) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return (0, 0)
        }

        var bytes: Int64 = 0
        var count = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: keys) else { continue }
            count += 1
            if values.isRegularFile == true {
                bytes += Int64(values.fileSize ?? 0)
            }
        }
        return (bytes, count)
    }

    /// Genişletilmiş öznitelik sayısını döndürür.
    private static func extendedAttributeCount(for url: URL) -> Int {
        url.path.withCString { pointer in
            let size = listxattr(pointer, nil, 0, 0)
            guard size > 0 else { return 0 }
            var buffer = [CChar](repeating: 0, count: size)
            let written = listxattr(pointer, &buffer, size, 0)
            guard written > 0 else { return 0 }
            // Adlar null karakterle ayrılır.
            return buffer.split(separator: 0).count
        }
    }
}
