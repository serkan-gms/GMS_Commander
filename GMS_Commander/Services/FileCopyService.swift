//
//  FileCopyService.swift
//  GMS_Commander
//
//  Dosya ve klasörleri ilerleme bildirimiyle kopyalayan servis.
//  Büyük dosyalar parça parça kopyalanır; meta veriler (izin, tarih, xattr) korunur.
//  Sembolik bağlantılar hedeflerine gidilmeden, bağlantı olarak kopyalanır.
//
//  Veri güvenliği kuralları:
//  - Var olan bir klasörün üzerine kopyalama, klasörü SİLMEZ; içeriği birleştirir.
//  - Normal dosyalar önce aynı klasörde geçici ada yazılır, boyutu doğrulanır ve
//    ardından atomik `rename(2)` ile hedefe taşınır. Böylece iptal veya hata
//    durumunda hedefte yarım dosya kalmaz.
//  - İptalde, bu işlem sırasında oluşturulan yeni öğeler temizlenir; var olan
//    kullanıcı dosyalarına dokunulmaz.
//

import Foundation
import Darwin

/// Kopyalanacak kaynağın boyut ve öğe sayısı tahmini.
struct CopyEstimate: Sendable, Equatable {
    var bytes: Int64 = 0
    var itemCount: Int = 0
}

/// Kopyalama servisi.
struct FileCopyService: Sendable {
    /// Parça boyutu (1 MB).
    private static let chunkSize = 1024 * 1024

    /// Kaynağın toplam boyutunu ve öğe sayısını hesaplar.
    /// - Parameter source: Ölçülecek kök öğe.
    /// - Returns: Bayt ve öğe sayısı tahmini.
    func estimate(source: URL) async -> CopyEstimate {
        await Task.detached(priority: .utility) {
            Self.estimateSync(source)
        }.value
    }

    /// Birden fazla kaynak için toplam tahmin üretir.
    func estimate(sources: [URL]) async -> CopyEstimate {
        await Task.detached(priority: .utility) {
            sources.reduce(into: CopyEstimate()) { partial, url in
                let estimate = Self.estimateSync(url)
                partial.bytes += estimate.bytes
                partial.itemCount += estimate.itemCount
            }
        }.value
    }

    /// Tek bir kaynağı hedefe kopyalar.
    /// - Parameters:
    ///   - source: Kaynak adres.
    ///   - destination: Hedef adres (dosya/klasör adı dâhil).
    ///   - overwrite: Hedef varsa üzerine yazılsın mı? Klasörlerde birleştirme yapılır.
    ///   - control: Duraklatma/iptal denetimi. `nil` ise yalnızca görev iptali izlenir.
    ///   - progress: Bu kaynak için tamamlanan bayt sayısını bildiren kapanış.
    func copy(
        source: URL,
        to destination: URL,
        overwrite: Bool,
        control: TransferControl? = nil,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.copySync(
                source: source,
                to: destination,
                overwrite: overwrite,
                control: control,
                progress: progress
            )
        }.value
    }

    // MARK: - Eşzamanlı çekirdek

    /// Kopyalama işleminin eşzamanlı çekirdeği (birim testlerinde doğrudan çağrılır).
    static func copySync(
        source: URL,
        to destination: URL,
        overwrite: Bool,
        control: TransferControl? = nil,
        progress: @escaping @Sendable (Int64) -> Void
    ) throws {
        // Bir öğeyi kendi içine kopyalamak sonsuz döngü ve veri kaybı riski taşır.
        if FileManagerService.isSameLocation(source, destination) {
            throw FileOperationError.sameLocation(source, destination)
        }
        if FileManagerService.isDescendant(destination, of: source) {
            throw FileOperationError.destinationInsideSource(source, destination)
        }

        let reporter = ProgressReporter(onProgress: progress)
        let tracker = CreatedItemTracker()
        do {
            try copyItemSync(
                source: source,
                destination: destination,
                overwrite: overwrite,
                control: control,
                reporter: reporter,
                tracker: tracker
            )
            reporter.flush()
        } catch {
            // Bu işlem sırasında oluşturulan yeni dosya/klasörleri geri al.
            // Var olan hedef klasörün içeriği korunur.
            tracker.cleanup()
            throw error
        }
    }

    /// Kaynağın boyutunu ve içerdiği öğe sayısını hesaplar.
    /// Paketler (ör. .app) bir klasör gibi kopyalandığı için içerikleri de sayılır.
    static func estimateSync(_ source: URL) -> CopyEstimate {
        let fileManager = FileManager.default
        var estimate = CopyEstimate()

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]
        guard let values = try? source.resourceValues(forKeys: resourceKeys) else {
            return estimate
        }

        if values.isSymbolicLink == true {
            // Bağlantının kendisi veri taşımaz; yine de bir öğe olarak sayılır.
            estimate.itemCount = 1
            return estimate
        }

        if values.isDirectory == true {
            estimate.itemCount += 1
            guard let enumerator = fileManager.enumerator(
                at: source,
                includingPropertiesForKeys: Array(resourceKeys),
                // Paketler kopyalanırken içeriğiyle birlikte kopyalandığından
                // burada da alt öğeler sayılmalıdır.
                options: [],
                errorHandler: { _, _ in true }
            ) else {
                return estimate
            }
            for case let childURL as URL in enumerator {
                guard let childValues = try? childURL.resourceValues(forKeys: resourceKeys) else { continue }
                estimate.itemCount += 1
                if childValues.isSymbolicLink == true { continue }
                if childValues.isRegularFile == true {
                    estimate.bytes += Int64(childValues.fileSize ?? 0)
                }
            }
        } else {
            estimate.itemCount = 1
            estimate.bytes = Int64(values.fileSize ?? 0)
        }

        return estimate
    }

    // MARK: - Özel yardımcılar

    /// Tek bir öğeyi (dosya, klasör veya bağlantı) özyinelemeli olarak kopyalar.
    private static func copyItemSync(
        source: URL,
        destination: URL,
        overwrite: Bool,
        control: TransferControl?,
        reporter: ProgressReporter,
        tracker: CreatedItemTracker
    ) throws {
        try control?.waitIfPaused()
        try Task.checkCancellation()

        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        guard let values = try? source.resourceValues(forKeys: resourceKeys) else {
            throw FileOperationError.sourceMissing(source)
        }

        let destinationExists = fileManager.fileExists(atPath: destination.path)
        let destinationValues = destinationExists
            ? try? destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            : nil
        // Sembolik bağlantı hedefi klasör olsa bile bağlantıdır; hedef klasörün
        // içeriğini silmemek için klasör sayılmaz.
        let destinationIsDirectory = (destinationValues?.isDirectory ?? false)
            && destinationValues?.isSymbolicLink != true

        // Sembolik bağlantı: hedefe gitmeden bağlantıyı yeniden oluştur.
        if values.isSymbolicLink == true {
            if destinationExists {
                guard overwrite else { throw FileOperationError.destinationExists(destination) }
                guard !destinationIsDirectory else {
                    throw FileOperationError.destinationIsDirectory(destination)
                }
            }
            try createSymbolicLink(
                source: source,
                destination: destination,
                destinationExists: destinationExists,
                tracker: tracker
            )
            return
        }

        if values.isDirectory == true {
            if destinationExists && !destinationIsDirectory {
                // Var olan normal dosyanın üzerine klasör yazılacaksa önce onu kaldır.
                guard overwrite else { throw FileOperationError.destinationExists(destination) }
                try removeRegularItem(at: destination)
            }

            if !fileManager.fileExists(atPath: destination.path) {
                do {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                } catch {
                    throw FileOperationError.copyFailed(destination, ErrorMessages.message(for: error))
                }
                tracker.recordCreated(destination)
            } else if !overwrite {
                // Hedef klasör varsa ve üzerine yazma izni yoksa dur.
                throw FileOperationError.destinationExists(destination)
            }
            // Hedef klasör varsa SİLİNMEZ; alt öğeler birleştirilir.

            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: source,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: []
                ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            } catch {
                throw FileOperationError.accessDenied(source)
            }

            for child in children {
                try control?.waitIfPaused()
                try Task.checkCancellation()
                let childDestination = destination.appendingPathComponent(child.lastPathComponent)
                try copyItemSync(
                    source: child,
                    destination: childDestination,
                    overwrite: overwrite,
                    control: control,
                    reporter: reporter,
                    tracker: tracker
                )
            }

            copyMetadata(from: source, to: destination)
            return
        }

        // Normal dosya dışındaki özel dosyalar (fifo, aygıt) için geçici ad
        // üzerinden kopyalama; hedefte yarım özel dosya bırakılmaz.
        if values.isRegularFile != true {
            if destinationExists {
                guard overwrite else { throw FileOperationError.destinationExists(destination) }
                guard !destinationIsDirectory else {
                    throw FileOperationError.destinationIsDirectory(destination)
                }
            }
            try copySpecialItem(
                source: source,
                destination: destination,
                destinationExists: destinationExists,
                tracker: tracker
            )
            return
        }

        try copyRegularFile(
            source: source,
            destination: destination,
            overwrite: overwrite,
            destinationExists: destinationExists,
            destinationIsDirectory: destinationIsDirectory,
            control: control,
            reporter: reporter,
            tracker: tracker
        )
    }

    /// Normal bir dosyayı parçalar hâlinde geçici dosyaya kopyalar, doğrular ve
    /// atomik olarak hedefe taşır.
    private static func copyRegularFile(
        source: URL,
        destination: URL,
        overwrite: Bool,
        destinationExists: Bool,
        destinationIsDirectory: Bool,
        control: TransferControl?,
        reporter: ProgressReporter,
        tracker: CreatedItemTracker
    ) throws {
        // Bir klasörün üzerine dosya yazmak, klasörü silmek anlamına gelir; asla yapma.
        guard !destinationIsDirectory else {
            throw FileOperationError.destinationIsDirectory(destination)
        }
        if destinationExists && !overwrite {
            throw FileOperationError.destinationExists(destination)
        }

        let fileManager = FileManager.default
        let temporaryURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".gms-copy-\(UUID().uuidString).tmp")

        defer {
            // Başarılı atomik taşımadan sonra geçici dosya kalmaz; hata veya
            // iptal durumunda burada temizlenir.
            try? fileManager.removeItem(at: temporaryURL)
        }

        do {
            guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
                throw FileOperationError.copyFailed(destination, L.t("error.unknown"))
            }

            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            let output = try FileHandle(forWritingTo: temporaryURL)
            defer { try? output.close() }

            var lastReport = DispatchTime.now()
            while true {
                try control?.waitIfPaused()
                try Task.checkCancellation()
                let data = try input.read(upToCount: chunkSize) ?? Data()
                if data.isEmpty {
                    break
                }
                try output.write(contentsOf: data)
                reporter.add(Int64(data.count))

                // Arayüzü çok sık güncellememek için 100 ms'lik bir sınır uyguluyoruz.
                let now = DispatchTime.now()
                if now.uptimeNanoseconds &- lastReport.uptimeNanoseconds > 100_000_000 {
                    lastReport = now
                    reporter.flush()
                }
            }
            try output.synchronize()
            try output.close()
            try input.close()

            // Boyut doğrulaması: disk dolu veya kesilen yazma sessizce geçmesin.
            let sourceSize = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let copiedSize = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
            guard Int64(sourceSize) == Int64(copiedSize) else {
                throw FileOperationError.verificationFailed(source, destination)
            }

            // Meta veriler geçici dosyaya uygulanır; atomik taşımada hedefe geçer.
            copyMetadata(from: source, to: temporaryURL)

            try control?.waitIfPaused()
            try Task.checkCancellation()

            let wasExisting = fileManager.fileExists(atPath: destination.path)
            try atomicRename(from: temporaryURL, to: destination)
            if !wasExisting {
                tracker.recordCreated(destination)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FileOperationError {
            throw error
        } catch {
            throw FileOperationError.copyFailed(source, ErrorMessages.message(for: error))
        }
    }

    /// Sembolik bağlantıyı geçici ad üzerinden atomik olarak oluşturur.
    private static func createSymbolicLink(
        source: URL,
        destination: URL,
        destinationExists: Bool,
        tracker: CreatedItemTracker
    ) throws {
        let fileManager = FileManager.default
        let temporaryURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".gms-link-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do {
            let linkTarget = try fileManager.destinationOfSymbolicLink(atPath: source.path)
            try fileManager.createSymbolicLink(atPath: temporaryURL.path, withDestinationPath: linkTarget)
            let wasExisting = fileManager.fileExists(atPath: destination.path)
            try atomicRename(from: temporaryURL, to: destination)
            if !wasExisting {
                tracker.recordCreated(destination)
            }
        } catch {
            throw FileOperationError.copyFailed(source, ErrorMessages.message(for: error))
        }
    }

    /// Özel dosyaları (fifo, aygıt vb.) geçici ad üzerinden kopyalar.
    private static func copySpecialItem(
        source: URL,
        destination: URL,
        destinationExists: Bool,
        tracker: CreatedItemTracker
    ) throws {
        let fileManager = FileManager.default
        let temporaryURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".gms-special-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do {
            try fileManager.copyItem(at: source, to: temporaryURL)
            try atomicRename(from: temporaryURL, to: destination)
            if !destinationExists {
                tracker.recordCreated(destination)
            }
        } catch {
            throw FileOperationError.copyFailed(source, ErrorMessages.message(for: error))
        }
    }

    /// Aynı birim içinde atomik yeniden adlandırma. Hedef dosya varsa yerine geçer.
    private static func atomicRename(from source: URL, to destination: URL) throws {
        let result = source.path.withCString { sourcePointer in
            destination.path.withCString { destinationPointer in
                rename(sourcePointer, destinationPointer)
            }
        }
        if result != 0 {
            let code = errno
            let message = String(cString: strerror(code))
            throw FileOperationError.copyFailed(destination, message)
        }
    }

    /// Yalnızca normal dosya veya sembolik bağlantıyı kaldırır; klasöre dokunmaz.
    private static func removeRegularItem(at url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let isDirectory = (values?.isDirectory ?? false) && values?.isSymbolicLink != true
        guard !isDirectory else {
            throw FileOperationError.destinationIsDirectory(url)
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw FileOperationError.copyFailed(url, ErrorMessages.message(for: error))
        }
    }

    /// İzin, tarih ve genişletilmiş öznitelikleri kaynaktan hedefe kopyalar.
    private static func copyMetadata(from source: URL, to destination: URL) {
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfItem(atPath: source.path) {
            var newAttributes: [FileAttributeKey: Any] = [:]
            if let permissions = attributes[.posixPermissions] {
                newAttributes[.posixPermissions] = permissions
            }
            if let modification = attributes[.modificationDate] {
                newAttributes[.modificationDate] = modification
            }
            if let creation = attributes[.creationDate] {
                newAttributes[.creationDate] = creation
            }
            if !newAttributes.isEmpty {
                try? fileManager.setAttributes(newAttributes, ofItemAtPath: destination.path)
            }
        }

        // Genişletilmiş öznitelikler ve ACL'ler (en iyi çaba).
        _ = source.path.withCString { sourcePointer in
            destination.path.withCString { destinationPointer in
                copyfile(sourcePointer, destinationPointer, nil, copyfile_flags_t(COPYFILE_XATTR | COPYFILE_ACL))
            }
        }
    }
}

// MARK: - Oluşturulan öğe izleme

/// Kopyalama sırasında yeni oluşturulan yolları kaydeder. Hata veya iptalde
/// yalnızca bu yollar geri alınır; kullanıcının var olan verisi korunur.
private final class CreatedItemTracker {
    private var createdPaths: [URL] = []

    /// Hedef daha önce yoksa kaydeder.
    func recordCreated(_ url: URL) {
        createdPaths.append(url)
    }

    /// Oluşturulan öğeleri tersten (önce dosyalar, sonra klasörler) kaldırır.
    func cleanup() {
        let fileManager = FileManager.default
        for url in createdPaths.reversed() {
            try? fileManager.removeItem(at: url)
        }
        createdPaths.removeAll()
    }
}

// MARK: - İlerleme bildirimi

/// Kopyalama sırasında biriken baytları belirli aralıklarla bildirir.
private final class ProgressReporter {
    private let onProgress: @Sendable (Int64) -> Void
    private var completedBytes: Int64 = 0
    private var lastFlushedBytes: Int64 = -1

    init(onProgress: @escaping @Sendable (Int64) -> Void) {
        self.onProgress = onProgress
    }

    /// Tamamlanan bayt miktarını artırır.
    func add(_ bytes: Int64) {
        completedBytes += bytes
    }

    /// Biriktirilen değeri bildirir.
    func flush() {
        guard completedBytes != lastFlushedBytes else { return }
        lastFlushedBytes = completedBytes
        onProgress(completedBytes)
    }
}
