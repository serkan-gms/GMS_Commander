//
//  ArchiveService.swift
//  GMS_Commander
//
//  ZIP, TAR ve TAR.GZ arşivlerini listeler ve güvenli biçimde çıkarır.
//  Çıkarma işlemi her zaman hedefin içinde oluşturulan geçici bir klasöre
//  yapılır; ardından içerik doğrulanır. Böylece "Zip Slip" (göreli yol
//  kaçışı), mutlak yol ve sembolik bağlantı kaçışı ile karşılaşılırsa
//  hiçbir dosya hedef klasöre taşınmadan işlem iptal edilir.
//

import Foundation

// MARK: - Arşiv biçimi

/// Desteklenen arşiv biçimleri.
enum ArchiveFormat: String, Sendable, CaseIterable {
    case zip
    case tar
    case tarGz

    /// Dosya uzantısından biçim tahmin eder.
    /// - Parameter url: Arşiv dosyası.
    /// - Returns: Tanınan biçim, aksi hâlde `nil`.
    static func detect(_ url: URL) -> ArchiveFormat? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
            return .tarGz
        }
        if name.hasSuffix(".tar") {
            return .tar
        }
        if name.hasSuffix(".zip") {
            return .zip
        }
        return nil
    }

    /// Oluşturma sırasında kullanılacak dosya uzantısı.
    var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .tar: return "tar"
        case .tarGz: return "tar.gz"
        }
    }

    /// Kullanıcıya gösterilen ad.
    var localizedName: String {
        switch self {
        case .zip: return "ZIP"
        case .tar: return "TAR"
        case .tarGz: return "TAR.GZ"
        }
    }
}

// MARK: - Arşiv kaydı

/// Arşiv içindeki tek bir öğe.
struct ArchiveEntry: Identifiable, Hashable, Sendable {
    /// Arşiv içindeki göreli yol. Dizinlerde sonunda "/" yoktur.
    let path: String

    /// Öğe bir klasör mü?
    let isDirectory: Bool

    var id: String { path }

    /// Son yol bileşeni.
    var name: String {
        (path as NSString).lastPathComponent
    }

    /// Üst klasörün arşiv içindeki yolu; kök öğeler için `nil`.
    var parentPath: String? {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == "." ? nil : parent
    }

    /// Görünen ada göre derinlik (kök öğeler 0).
    var depth: Int {
        path.split(separator: "/").count - 1
    }
}

// MARK: - İlerleme

/// Arşiv çıkarma ilerlemesi.
struct ArchiveProgress: Sendable {
    /// Tamamlanan öğe sayısı.
    let completedItems: Int
    /// Toplam öğe sayısı.
    let totalItems: Int
    /// Şu an işlenen öğenin adı.
    let currentName: String

    /// 0…1 arası ilerleme oranı.
    var fraction: Double {
        guard totalItems > 0 else { return 0 }
        return min(Double(completedItems) / Double(totalItems), 1)
    }
}

// MARK: - Hatalar

/// Arşiv işlemlerinde oluşabilecek hatalar.
enum ArchiveError: LocalizedError {
    /// Arşiv biçimi tanınmadı.
    case unsupportedFormat(String)
    /// Arşiv okunamadı.
    case listFailed(String)
    /// Arşivde güvenli olmayan bir yol bulundu.
    case unsafeEntry(String)
    /// Arşivde sembolik bağlantı bulundu.
    case symbolicLinkRejected(String)
    /// Arşiv beklenenden büyük açılıyor.
    case sizeLimitExceeded(limitBytes: Int64)
    /// Arşivde çok fazla öğe var.
    case entryLimitExceeded(Int)
    /// Çıkarma başarısız.
    case extractionFailed(String)
    /// Hedef klasör yazılabilir değil.
    case destinationUnavailable(String)
    /// İşlem kullanıcı tarafından iptal edildi.
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let name):
            return "“\(name)” arşiv biçimi desteklenmiyor. ZIP, TAR ve TAR.GZ desteklenir."
        case .listFailed(let detail):
            return "Arşiv içeriği okunamadı: \(detail)"
        case .unsafeEntry(let path):
            return "Arşiv güvenli olmayan bir yol içeriyor: \(path). Çıkarma işlemi durduruldu."
        case .symbolicLinkRejected(let path):
            return "Arşiv sembolik bağlantı içeriyor (\(path)). Güvenlik nedeniyle çıkarma durduruldu."
        case .sizeLimitExceeded(let limit):
            return "Arşiv açıldığında izin verilen boyutu aşıyor (\(FileSizeFormatter.string(fromBytes: limit)))."
        case .entryLimitExceeded(let limit):
            return "Arşiv izin verilen en fazla \(limit) öğe sınırını aşıyor."
        case .extractionFailed(let detail):
            return "Arşiv çıkarılamadı: \(detail)"
        case .destinationUnavailable(let detail):
            return "Hedef klasör kullanılamıyor: \(detail)"
        case .cancelled:
            return "Arşiv çıkarma işlemi iptal edildi."
        }
    }
}

// MARK: - Servis

/// Arşiv listeleme ve güvenli çıkarma servisi.
///
/// Listeleme ve çıkarma işlemleri sistemde bulunan `bsdtar` (libarchive)
/// aracıyla yapılır. libarchive varsayılan olarak mutlak yolları ve ".."
/// bileşenlerini reddeder; buna ek olarak bu servis tüm kayıtları önceden
/// doğrular, çıkarmayı hedefin içindeki geçici klasöre yapar ve sonucu
/// yeniden tarayarak sembolik bağlantıları reddeder.
struct ArchiveService: Sendable {
    /// Tek bir çıkarma işleminde izin verilen en fazla öğe sayısı.
    static let maximumEntryCount = 200_000
    /// Tahmini açılmış boyut üst sınırı (20 GB).
    static let maximumExtractedBytes: Int64 = 20 * 1024 * 1024 * 1024

    private let tarURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
    private let unzipURL = URL(fileURLWithPath: "/usr/bin/unzip")

    // MARK: Listeleme

    /// Arşivdeki öğeleri listeler.
    /// - Parameter archive: Arşiv dosyası.
    /// - Returns: Arşivdeki öğeler (arşiv sırasıyla).
    func listEntries(in archive: URL) throws -> [ArchiveEntry] {
        guard ArchiveFormat.detect(archive) != nil else {
            throw ArchiveError.unsupportedFormat(archive.lastPathComponent)
        }
        let output = try runTool(tarURL, arguments: ["-tf", archive.path])
        let lines = output.split(whereSeparator: \.isNewline)
        var entries: [ArchiveEntry] = []
        var seen = Set<String>()

        for rawLine in lines {
            let raw = String(rawLine)
            guard !raw.isEmpty else { continue }
            let isDirectory = raw.hasSuffix("/")
            let trimmed = isDirectory ? String(raw.dropLast()) : raw
            guard let path = Self.normalizedEntryPath(trimmed) else {
                throw ArchiveError.unsafeEntry(raw)
            }
            // Aynı yolun iki kez bulunması (yinelenen kayıt) belirsizdir;
            // hangi içeriğin yazılacağı platforma göre değişebilir.
            let key = path.lowercased()
            guard seen.insert(key).inserted else {
                throw ArchiveError.unsafeEntry("\(raw) (yinelenen kayıt)")
            }
            entries.append(ArchiveEntry(path: path, isDirectory: isDirectory))
        }

        if entries.count > Self.maximumEntryCount {
            throw ArchiveError.entryLimitExceeded(Self.maximumEntryCount)
        }
        return entries
    }

    /// ZIP arşivleri için tahmini açılmış boyutu döndürür. Diğer biçimlerde
    /// güvenilir bir tahmin olmadığından `nil` döner.
    func estimatedUncompressedSize(of archive: URL) -> Int64? {
        guard ArchiveFormat.detect(archive) == .zip else { return nil }
        guard let output = try? runTool(unzipURL, arguments: ["-l", archive.path]) else { return nil }

        // "unzip -l" çıktısının son satırı "  7  2 files" benzeri toplamı verir.
        for line in output.split(separator: "\n").reversed() {
            let parts = line.split(whereSeparator: { $0 == " " }).filter { !$0.isEmpty }
            guard parts.count >= 2,
                  let bytes = Int64(parts[0]),
                  parts[1].hasSuffix("file") || parts[1].hasSuffix("files") else { continue }
            return bytes
        }
        return nil
    }

    // MARK: Çıkarma

    /// Arşivi hedef klasöre çıkarır.
    /// - Parameters:
    ///   - archive: Arşiv dosyası.
    ///   - destination: Hedef klasör (mevcut ve yazılabilir olmalı).
    ///   - selectedPaths: Yalnızca bu yolları çıkar; `nil` ise tümü.
    ///   - control: Duraklatma/iptal denetimi.
    ///   - progress: İlerleme bildirimi.
    /// - Returns: Hedef klasöre taşınan kök öğeler.
    @discardableResult
    func extract(
        archive: URL,
        to destination: URL,
        selectedPaths: Set<String>? = nil,
        control: TransferControl? = nil,
        progress: (@Sendable (ArchiveProgress) -> Void)? = nil
    ) async throws -> [URL] {
        let entries = try listEntries(in: archive)
        let format = ArchiveFormat.detect(archive)
        guard format != nil else {
            throw ArchiveError.unsupportedFormat(archive.lastPathComponent)
        }

        if let estimate = estimatedUncompressedSize(of: archive) {
            guard estimate <= Self.maximumExtractedBytes else {
                throw ArchiveError.sizeLimitExceeded(limitBytes: Self.maximumExtractedBytes)
            }
        }

        return try await Task.detached(priority: .userInitiated) {
            try Self.extractSync(
                archive: archive,
                destination: destination,
                entries: entries,
                selectedPaths: selectedPaths,
                control: control,
                progress: progress
            )
        }.value
    }

    /// Çıkarma işleminin eşzamanlı çekirdeği. Testlerde doğrudan çağrılır.
    static func extractSync(
        archive: URL,
        destination: URL,
        entries: [ArchiveEntry],
        selectedPaths: Set<String>?,
        control: TransferControl?,
        progress: (@Sendable (ArchiveProgress) -> Void)?
    ) throws -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ArchiveError.destinationUnavailable(destination.path)
        }
        guard fileManager.isWritableFile(atPath: destination.path) else {
            throw ArchiveError.destinationUnavailable("klasör salt okunur")
        }

        try control?.checkCancellation()

        // Geçici klasör hedefin içinde oluşturulur: taşıma aynı birimde kalır ve
        // yarım kalan çıkarma hedefin dışına taşmaz.
        let temporaryName = ".gms-arşiv-\(UUID().uuidString)"
        let temporaryDirectory = destination.appendingPathComponent(temporaryName, isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        // --no-same-owner: arşivdeki kullanıcı kimliğine geçme.
        // --no-same-permissions: kısıtlayıcı izinlerin hedefe taşınmasını engelle.
        // -x: çıkar, -f: dosya, -C: hedef klasör.
        process.arguments = [
            "-x", "-f", archive.path,
            "--no-same-owner", "--no-same-permissions",
            "-C", temporaryDirectory.path
        ]
        // Hata çıktısı geçici bir dosyaya yazılır; boru (pipe) dolduğunda
        // sürecin kilitlenmesini önler.
        let errorLogURL = temporaryDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("\(temporaryName).log")
        FileManager.default.createFile(atPath: errorLogURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorLogURL)
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorLogURL)
        }
        process.standardError = errorHandle
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ArchiveError.extractionFailed(error.localizedDescription)
        }

        // İptal isteği geldiğinde süreci sonlandır.
        while process.isRunning {
            if Task.isCancelled || control?.isCancelled == true {
                process.terminate()
                process.waitUntilExit()
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()

        try? errorHandle.synchronize()
        let errorText = (try? String(
            contentsOf: errorLogURL,
            encoding: .utf8
        ))?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw ArchiveError.extractionFailed(
                errorText.flatMap { $0.isEmpty ? nil : $0 }
                    ?? "bsdtar kodu \(process.terminationStatus)"
            )
        }

        // Çıkarılan ağacı doğrula: sembolik bağlantı, aygıt dosyası veya
        // geçici klasörün dışına çıkan bir yol varsa hiçbir şey taşınmaz.
        try validateExtractedTree(temporaryDirectory)

        // Seçili öğeleri belirle. Bir üst klasör seçiliyse alt öğeleri ayrıca
        // taşımaya gerek yoktur.
        let allPaths = entries.map(\.path)
        var pathsToMove: [String]
        if let selectedPaths, !selectedPaths.isEmpty {
            let selected = Set(selectedPaths.map { Self.trimTrailingSlash($0) })
            var candidates = allPaths.filter { selected.contains($0) }
            // Arşivde yol farklı yazılmış olabilir; mevcut olanları da dene.
            for path in selected where !candidates.contains(path) {
                if fileManager.fileExists(atPath: temporaryDirectory.appendingPathComponent(path).path) {
                    candidates.append(path)
                }
            }
            guard !candidates.isEmpty else { return [] }
            let topLevel = candidates.filter { candidate in
                !candidates.contains { other in
                    other != candidate && candidate.hasPrefix(other + "/")
                }
            }
            pathsToMove = topLevel
        } else {
            pathsToMove = allPaths.filter { entry in
                !allPaths.contains { other in
                    other != entry && entry.hasPrefix(other + "/")
                }
            }
        }

        // Yol derinliğine göre sırala; üst klasörler önce taşınsın.
        pathsToMove.sort { lhs, rhs in
            let lhsDepth = lhs.split(separator: "/").count
            let rhsDepth = rhs.split(separator: "/").count
            if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        var movedRoots: [URL] = []
        let total = pathsToMove.count
        for (index, path) in pathsToMove.enumerated() {
            try control?.waitIfPaused()
            try control?.checkCancellation()
            progress?(ArchiveProgress(
                completedItems: index,
                totalItems: total,
                currentName: (path as NSString).lastPathComponent
            ))

            let sourceURL = temporaryDirectory.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

            // Seçili bir alt öğenin üst klasörleri hedefte yoksa oluştur.
            let parentRelative = (path as NSString).deletingLastPathComponent
            let parentURL: URL
            if parentRelative.isEmpty || parentRelative == "." {
                parentURL = destination
            } else {
                parentURL = destination.appendingPathComponent(parentRelative, isDirectory: true)
                try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
            }

            let finalURL = FileNaming.uniqueDestination(
                for: sourceURL.lastPathComponent,
                in: parentURL,
                fileManager: fileManager
            )
            do {
                try fileManager.moveItem(at: sourceURL, to: finalURL)
                movedRoots.append(finalURL)
            } catch {
                throw ArchiveError.extractionFailed("\(path): \(error.localizedDescription)")
            }
        }

        progress?(ArchiveProgress(
            completedItems: total,
            totalItems: total,
            currentName: ""
        ))
        return movedRoots
    }

    // MARK: Yardımcılar

    /// Arşiv kaydı yolunu doğrular ve normalleştirir.
    /// Mutlak yol, üst klasöre çıkan bileşen ve denetim karakteri reddedilir.
    static func normalizedEntryPath(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        // Windows üzerinde üretilmiş ZIP'ler ters eğik çizgi kullanabilir.
        let unified = raw.replacingOccurrences(of: "\\", with: "/")
        guard !unified.hasPrefix("/"), !unified.hasPrefix("~") else { return nil }
        guard !unified.contains("\0") else { return nil }
        // "C:/..." gibi sürücü harfi taşıyan yollar.
        if unified.count >= 2,
           unified[unified.index(unified.startIndex, offsetBy: 1)] == ":" {
            return nil
        }

        var components: [String] = []
        for component in unified.split(separator: "/", omittingEmptySubsequences: true) {
            let text = String(component)
            if text == "." { continue }
            if text == ".." { return nil }
            components.append(text)
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

    /// Çıkarılan ağacı tarar; sembolik bağlantı veya özel dosya varsa hata verir.
    static func validateExtractedTree(_ root: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            throw ArchiveError.extractionFailed("çıkarılan içerik taranamadı")
        }

        let rootPath = root.standardizedFileURL.path
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                let relative = url.path.hasPrefix(rootPath)
                    ? String(url.path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    : url.lastPathComponent
                throw ArchiveError.symbolicLinkRejected(relative)
            }
            if values?.isRegularFile != true && values?.isDirectory != true {
                throw ArchiveError.unsafeEntry(url.lastPathComponent)
            }
            // Standart yol, geçici klasörün altında kalmalı.
            guard url.standardizedFileURL.path.hasPrefix(rootPath + "/") else {
                throw ArchiveError.unsafeEntry(url.path)
            }
        }
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Bir aracı çalıştırıp standart çıktısını döndürür.
    private func runTool(_ executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw ArchiveError.listFailed(error.localizedDescription)
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArchiveError.listFailed(
                detail.flatMap { $0.isEmpty ? nil : $0 } ?? "araç kodu \(process.terminationStatus)"
            )
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
