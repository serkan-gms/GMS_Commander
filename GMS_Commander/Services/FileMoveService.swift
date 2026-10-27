//
//  FileMoveService.swift
//  GMS_Commander
//
//  Dosya ve klasörleri taşıyan servis. Aynı disk içinde atomik `rename(2)`
//  kullanır; farklı diskler arasında kopyalama + doğrulama + kaynağı silme
//  yöntemine düşer.
//
//  Veri güvenliği kuralları:
//  - Hedefte var olan bir klasör asla toptan silinmez; iki klasör birleştirilir.
//  - Normal dosyalar aynı birimdeyse atomik olarak değiştirilir.
//  - Farklı birim taşımasında kopya doğrulanmadan kaynak silinmez.
//  - Bir klasörün kendi alt klasörüne taşınması reddedilir.
//

import Foundation
import Darwin

/// Taşıma servisi.
struct FileMoveService: Sendable {
    /// Bir kaynağı hedefe taşır.
    /// - Parameters:
    ///   - source: Kaynak adres.
    ///   - destination: Hedef adres (dosya/klasör adı dâhil).
    ///   - overwrite: Hedef varsa üzerine yazılsın mı? Klasörlerde birleştirme yapılır.
    ///   - control: Duraklatma/iptal denetimi.
    ///   - progress: Farklı disk taşımalarında kopyalama ilerlemesi (bayt).
    func move(
        source: URL,
        to destination: URL,
        overwrite: Bool,
        control: TransferControl? = nil,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.moveSync(
                source: source,
                to: destination,
                overwrite: overwrite,
                control: control,
                progress: progress
            )
        }.value
    }

    /// Taşımanın eşzamanlı çekirdeği (birim testlerinde doğrudan çağrılır).
    static func moveSync(
        source: URL,
        to destination: URL,
        overwrite: Bool,
        control: TransferControl? = nil,
        progress: @escaping @Sendable (Int64) -> Void
    ) throws {
        try control?.waitIfPaused()
        try Task.checkCancellation()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: source.path) else {
            throw FileOperationError.sourceMissing(source)
        }

        if FileManagerService.isSameLocation(source, destination) {
            throw FileOperationError.sameLocation(source, destination)
        }
        if FileManagerService.isDescendant(destination, of: source) {
            throw FileOperationError.destinationInsideSource(source, destination)
        }

        let sourceValues = try? source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        let sourceIsDirectory = (sourceValues?.isDirectory ?? false) && sourceValues?.isSymbolicLink != true
        let sourceFileSize = Int64(sourceValues?.fileSize ?? 0)
        let destinationExists = fileManager.fileExists(atPath: destination.path)
        let destinationValues = destinationExists
            ? try? destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            : nil
        // Sembolik bağlantı, hedefi klasör olsa bile bağlantı olarak değiştirilir;
        // hedef klasörün içeriği asla silinmez.
        let destinationIsDirectory = (destinationValues?.isDirectory ?? false)
            && destinationValues?.isSymbolicLink != true

        if destinationExists {
            guard overwrite else { throw FileOperationError.destinationExists(destination) }

            // İki klasör: hedefi silmek yerine içerikleri birleştir.
            if sourceIsDirectory && destinationIsDirectory {
                try mergeMoveDirectory(
                    source: source,
                    destination: destination,
                    control: control,
                    progress: progress
                )
                return
            }

            // Klasörün veya dosyanın üzerine klasör yazılacaksa hedef klasör
            // asla silinmez.
            if !sourceIsDirectory && destinationIsDirectory {
                throw FileOperationError.destinationIsDirectory(destination)
            }

            // Kaynak klasör, hedef normal dosya: yalnızca dosyayı kaldır.
            if sourceIsDirectory && !destinationIsDirectory {
                try removeNonDirectoryItem(at: destination)
            }
        }

        do {
            try control?.waitIfPaused()
            try Task.checkCancellation()
            // Aynı birimde atomik taşıma. Hedef normal dosya ise atomik değiştirir.
            try atomicMove(from: source, to: destination)
            // Taşıma sonrası kaynak artık yok; boyut daha önce okunmuştu.
            progress(sourceIsDirectory ? 0 : sourceFileSize)
        } catch {
            if isCrossDevice(error) {
                try moveByCopying(
                    source: source,
                    to: destination,
                    control: control,
                    progress: progress
                )
            } else {
                throw FileOperationError.moveFailed(source, ErrorMessages.message(for: error))
            }
        }
    }

    // MARK: - Klasör birleştirme

    /// Hedef klasör varsa, kaynak klasörün çocuklarını tek tek taşıyarak birleştirir.
    /// Var olan hedef dosyalar `overwrite` kararı doğrultusunda değiştirilir; hedef
    /// klasörler yine birleştirilir. İşlem sonunda boşalan kaynak klasör kaldırılır.
    private static func mergeMoveDirectory(
        source: URL,
        destination: URL,
        control: TransferControl?,
        progress: @escaping @Sendable (Int64) -> Void
    ) throws {
        let fileManager = FileManager.default
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw FileOperationError.accessDenied(source)
        }

        for child in children {
            try control?.waitIfPaused()
            try Task.checkCancellation()

            let childDestination = destination.appendingPathComponent(child.lastPathComponent)
            let childValues = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            let childIsDirectory = (childValues?.isDirectory ?? false) && childValues?.isSymbolicLink != true

            let childDestinationExists = fileManager.fileExists(atPath: childDestination.path)
            let childDestinationValues = childDestinationExists
                ? try? childDestination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                : nil
            let childDestinationIsDirectory = (childDestinationValues?.isDirectory ?? false)
                && childDestinationValues?.isSymbolicLink != true

            if childDestinationExists {
                if childIsDirectory && childDestinationIsDirectory {
                    try mergeMoveDirectory(
                        source: child,
                        destination: childDestination,
                        control: control,
                        progress: progress
                    )
                    continue
                }
                if !childIsDirectory && childDestinationIsDirectory {
                    // Dosyanın üzerine klasör yazmak hedef klasörü silmek olur.
                    throw FileOperationError.destinationIsDirectory(childDestination)
                }
                if childIsDirectory && !childDestinationIsDirectory {
                    // Yalnızca normal dosyayı kaldır; klasör asla toptan silinmez.
                    try removeNonDirectoryItem(at: childDestination)
                }
            }

            do {
                try atomicMove(from: child, to: childDestination)
                progress(Int64(childValues?.fileSize ?? 0))
            } catch {
                if isCrossDevice(error) {
                    try moveByCopying(
                        source: child,
                        to: childDestination,
                        control: control,
                        progress: progress
                    )
                } else {
                    throw FileOperationError.moveFailed(child, ErrorMessages.message(for: error))
                }
            }
        }

        do {
            try fileManager.removeItem(at: source)
        } catch {
            throw FileOperationError.moveFailed(
                source,
                L.t("error.moveSourceNotRemoved", ErrorMessages.message(for: error))
            )
        }
    }

    // MARK: - Farklı birim taşıma

    /// Farklı diskler arasında kopyalayıp doğrulayarak kaynağı siler.
    private static func moveByCopying(
        source: URL,
        to destination: URL,
        control: TransferControl?,
        progress: @escaping @Sendable (Int64) -> Void
    ) throws {
        do {
            // `FileCopyService` her dosyayı geçici ad + boyut doğrulaması ile yazar.
            try FileCopyService.copySync(
                source: source,
                to: destination,
                overwrite: true,
                control: control,
                progress: progress
            )
        } catch {
            throw FileOperationError.moveFailed(source, ErrorMessages.message(for: error))
        }

        // Kopyanın hedefte gerçekten bulunduğunu doğrula; kaynak ancak bundan
        // sonra silinir.
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw FileOperationError.verificationFailed(source, destination)
        }

        do {
            try FileManager.default.removeItem(at: source)
        } catch {
            // Kopya başarılı olduğu hâlde kaynak silinemediyse kullanıcı bilgilendirilir.
            throw FileOperationError.moveFailed(
                source,
                L.t("error.moveSourceNotRemoved", ErrorMessages.message(for: error))
            )
        }
    }

    // MARK: - Yardımcılar

    /// Aynı birimde atomik taşıma. Hedef normal dosya/bağlantıysa atomik değiştirir.
    private static func atomicMove(from source: URL, to destination: URL) throws {
        let result = source.path.withCString { sourcePointer in
            destination.path.withCString { destinationPointer in
                rename(sourcePointer, destinationPointer)
            }
        }
        if result != 0 {
            let code = errno
            let message = String(cString: strerror(code))
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    /// Yalnızca normal dosya veya sembolik bağlantıyı kaldırır; klasöre dokunmaz.
    private static func removeNonDirectoryItem(at url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let isDirectory = (values?.isDirectory ?? false) && values?.isSymbolicLink != true
        guard !isDirectory else {
            throw FileOperationError.destinationIsDirectory(url)
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw FileOperationError.moveFailed(url, ErrorMessages.message(for: error))
        }
    }

    /// Hatada alttaki POSIX `EXDEV` (farklı aygıt) kodunu arar.
    private static func isCrossDevice(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        var depth = 0
        while let nsError = current, depth < 5 {
            if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EXDEV) {
                return true
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }
}
