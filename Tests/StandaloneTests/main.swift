//
//  main.swift
//  StandaloneTests
//
//  XCTest bulunmayan ortamlarda (yalnızca Command Line Tools kurulu macOS)
//  testleri çalıştırmak için kullanılan bağımsız test koşucusu.
//  Aynı senaryolar Tests/GMSCommanderTests içinde XCTest olarak da bulunur.
//
//  Derleme: ./Scripts/test.sh
//

import Foundation

// MARK: - Küçük test çatısı

final class Harness {
    static var passed = 0
    static var failed = 0
    static var failures: [String] = []
    static var group = ""
}

func group(_ name: String) {
    Harness.group = name
    print("\n▸ \(name)")
}

func expect(_ condition: Bool, _ message: String, line: UInt = #line) {
    if condition {
        Harness.passed += 1
        print("  ✓ \(message)")
    } else {
        Harness.failed += 1
        Harness.failures.append("[\(Harness.group)] \(message) (satır \(line))")
        print("  ✗ \(message) — satır \(line)")
    }
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String, line: UInt = #line) {
    if lhs == rhs {
        expect(true, message, line: line)
    } else {
        expect(false, "\(message) (beklenen: \(rhs), gelen: \(lhs))", line: line)
    }
}

func expectThrows(_ message: String, line: UInt = #line, _ block: () throws -> Void) {
    do {
        try block()
        expect(false, "\(message) — hata bekleniyordu", line: line)
    } catch {
        expect(true, message, line: line)
    }
}

/// Hata türünü (ilişkili değerden bağımsız) doğrular.
func expectError(_ message: String, line: UInt = #line, _ block: () throws -> Void, matches: (Error) -> Bool) {
    do {
        try block()
        expect(false, "\(message) — hata bekleniyordu", line: line)
    } catch {
        expect(matches(error), "\(message) (gelen: \(error))", line: line)
    }
}

// MARK: - Yardımcılar

let workRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("GMSCommanderStandalone-\(UUID().uuidString)", isDirectory: true)

/// Dosya sisteminin bildirdiği gerçek yolu döndürür (/var → /private/var).
/// Foundation'ın `resolvingSymlinksInPath()` fonksiyonu bu takma adı çözmediği için POSIX kullanıyoruz.
func realPath(_ url: URL) -> URL {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(url.path, &buffer) != nil else { return url }
    return URL(fileURLWithPath: String(cString: buffer))
}

func freshDirectory(_ name: String = "case") -> URL {
    let url = workRoot.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return realPath(url)
}

@discardableResult
func writeFile(_ name: String, _ contents: String = "içerik", in directory: URL) -> URL {
    let url = directory.appendingPathComponent(name)
    try? contents.data(using: .utf8)?.write(to: url)
    return url
}

@discardableResult
func makeDirectory(_ name: String, in directory: URL) -> URL {
    let url = directory.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

// MARK: - Model testleri

func testFileItem() {
    group("Model: FileItem")

    let dir = freshDirectory()
    let fileURL = writeFile("rapor.txt", "12345", in: dir)
    let item = FileItem.make(url: fileURL)

    expectEqual(item?.name, "rapor.txt", "Ad okunuyor")
    expectEqual(item?.isDirectory, false, "Dosya, klasör değil")
    expectEqual(item?.isSymbolicLink, false, "Sembolik bağ değil")
    expectEqual(item?.size, 5, "Dosya boyutu 5 bayt")
    expect(item?.modificationDate != nil, "Değiştirme tarihi okunuyor")

    let hiddenURL = writeFile(".gizli", in: dir)
    expectEqual(FileItem.make(url: hiddenURL)?.isHidden, true, "Gizli dosya tespit ediliyor")

    let folderURL = makeDirectory("Klasör", in: dir)
    let folderItem = FileItem.make(url: folderURL)
    expectEqual(folderItem?.isDirectory, true, "Klasör tespit ediliyor")
    expectEqual(folderItem?.size, 0, "Klasör boyutu 0")
    expectEqual(FileSizeFormatter.string(for: folderItem!), "—", "Klasör boyutu metni —")

    let target = writeFile("hedef.txt", in: dir)
    let linkURL = dir.appendingPathComponent("baglanti.txt")
    try? FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: target)
    expectEqual(FileItem.make(url: linkURL)?.isSymbolicLink, true, "Sembolik bağ tespit ediliyor")

    // Sıralama
    let sortDir = freshDirectory()
    makeDirectory("zKlasör", in: sortDir)
    writeFile("aDosya.txt", in: sortDir)
    writeFile("bDosya.txt", in: sortDir)
    let items = (try? FileManagerService.listDirectorySync(at: sortDir, includeHidden: false).items) ?? []

    let byName = FileItem.sorted(items, by: .name, ascending: true, foldersFirst: true).map(\.name)
    expectEqual(byName, ["zKlasör", "aDosya.txt", "bDosya.txt"], "Klasörler önce, ad artan")

    let descending = FileItem.sorted(items, by: .name, ascending: false, foldersFirst: false).map(\.name)
    expectEqual(descending, ["zKlasör", "bDosya.txt", "aDosya.txt"], "Klasörler önce kapalı, ad azalan")

    let sizeDir = freshDirectory()
    writeFile("kucuk.txt", "1", in: sizeDir)
    writeFile("buyuk.txt", String(repeating: "x", count: 500), in: sizeDir)
    let sizeItems = (try? FileManagerService.listDirectorySync(at: sizeDir, includeHidden: false).items) ?? []
    let bySize = FileItem.sorted(sizeItems, by: .size, ascending: true, foldersFirst: false).map(\.name)
    expectEqual(bySize, ["kucuk.txt", "buyuk.txt"], "Boyuta göre artan sıralama")

    let tieDir = freshDirectory()
    writeFile("b.txt", "aynı", in: tieDir)
    writeFile("a.txt", "aynı", in: tieDir)
    let tieItems = (try? FileManagerService.listDirectorySync(at: tieDir, includeHidden: false).items) ?? []
    let firstRun = FileItem.sorted(tieItems, by: .size, ascending: true, foldersFirst: true).map(\.name)
    let secondRun = FileItem.sorted(tieItems.reversed(), by: .size, ascending: true, foldersFirst: true).map(\.name)
    expectEqual(firstRun, secondRun, "Eşit değerlerde sıralama deterministik")

    // Anlık görüntü istatistikleri
    let statDir = freshDirectory()
    makeDirectory("Alt", in: statDir)
    writeFile("bir.txt", "12345", in: statDir)
    writeFile("iki.txt", "1234567890", in: statDir)
    if let snapshot = try? FileManagerService.listDirectorySync(at: statDir, includeHidden: false) {
        expectEqual(snapshot.folderCount, 1, "Klasör sayısı")
        expectEqual(snapshot.fileCount, 2, "Dosya sayısı")
        expectEqual(snapshot.totalSize, 15, "Toplam boyut")
        expect(snapshot.item(at: statDir.appendingPathComponent("bir.txt")) != nil, "item(at:) buluyor")
        expect(snapshot.errorMessage == nil, "Hata mesajı yok")
        expect(snapshot.parentURL != nil, "Üst klasör bilgisi var")
    } else {
        expect(false, "Klasör listelenebildi")
    }
}

// MARK: - FileManagerService

func testFileManagerService() {
    group("Servis: FileManagerService")

    let dir = freshDirectory()
    writeFile("gorunur.txt", in: dir)
    writeFile(".gizli.txt", in: dir)

    let visible = try? FileManagerService.listDirectorySync(at: dir, includeHidden: false)
    let all = try? FileManagerService.listDirectorySync(at: dir, includeHidden: true)
    expectEqual(visible?.items.count, 1, "Gizli dosyalar listelenmiyor")
    expectEqual(all?.items.count, 2, "Gizli dosyalar dahil listeleniyor")

    let fileURL = writeFile("dosya.txt", in: dir)
    expectError("Dosya yolu klasör olarak listelenmiyor", {
        _ = try FileManagerService.listDirectorySync(at: fileURL, includeHidden: false)
    }, matches: { if case FileOperationError.notADirectory = $0 { return true } else { return false } })

    let createDir = freshDirectory()
    let created = try? FileManagerService.createDirectorySync(in: createDir, preferredName: "Yeni Klasör")
    expectEqual(created?.lastPathComponent, "Yeni Klasör", "Klasör tercih edilen adla oluşturuluyor")
    let second = try? FileManagerService.createDirectorySync(in: createDir, preferredName: "Yeni Klasör")
    expectEqual(second?.lastPathComponent, "Yeni Klasör 2", "Ad çakışmasında numara ekleniyor")

    expect((try? FileManagerService.validateName("rapor 2025.txt")) != nil, "Geçerli ad kabul ediliyor")
    for invalid in ["", ".", "..", "a/b.txt", "a:b.txt"] {
        expectThrows("Geçersiz ad reddediliyor: \"\(invalid)\"") {
            try FileManagerService.validateName(invalid)
        }
    }

    let renameDir = freshDirectory()
    let oldURL = writeFile("eski.txt", in: renameDir)
    let renamed = try? FileManagerService.renameSync(oldURL, to: "yeni.txt")
    expectEqual(renamed?.lastPathComponent, "yeni.txt", "Yeniden adlandırma yeni adı döndürüyor")
    expect(!exists(oldURL), "Eski ad kalmadı")

    let conflictDir = freshDirectory()
    let firstURL = writeFile("bir.txt", in: conflictDir)
    writeFile("iki.txt", in: conflictDir)
    expectError("Var olan ada yeniden adlandırma reddediliyor", {
        _ = try FileManagerService.renameSync(firstURL, to: "iki.txt")
    }, matches: { if case FileOperationError.destinationExists = $0 { return true } else { return false } })

    let uniqueDir = freshDirectory()
    writeFile("rapor.txt", in: uniqueDir)
    writeFile("rapor 2.txt", in: uniqueDir)
    expectEqual(
        FileManagerService.uniqueDestination(for: "rapor.txt", in: uniqueDir).lastPathComponent,
        "rapor 3.txt",
        "Benzersiz hedef adı üretiliyor"
    )
    expectEqual(
        FileManagerService.uniqueDestination(for: "serbest.txt", in: uniqueDir).lastPathComponent,
        "serbest.txt",
        "Boş adda değişiklik yapılmıyor"
    )

    let deleteDir = freshDirectory()
    let deleteURL = writeFile("sil.txt", in: deleteDir)
    try? FileManagerService.deletePermanentlySync(deleteURL)
    expect(!exists(deleteURL), "Kalıcı silme dosyayı kaldırıyor")

    let sameDir = freshDirectory()
    let sameURL = writeFile("a.txt", in: sameDir)
    expect(FileManagerService.isSameLocation(sameURL, sameURL), "Aynı konum tespiti")
    expect(!FileManagerService.isSameLocation(sameURL, sameDir), "Farklı konum tespiti")
    expect(FileManagerService.isRoot(URL(fileURLWithPath: "/")), "Kök klasör tespiti")
    expect(!FileManagerService.isRoot(sameDir), "Kök olmayan klasör tespiti")
}

// MARK: - Kopyalama

func testCopyService() {
    group("Servis: FileCopyService")

    let dir = freshDirectory()
    let source = writeFile("kaynak.txt", "merhaba dünya", in: dir)
    let destination = dir.appendingPathComponent("hedef.txt")
    try? FileCopyService.copySync(source: source, to: destination, overwrite: false) { _ in }

    expectEqual(
        (try? String(contentsOf: destination, encoding: .utf8)),
        "merhaba dünya",
        "Dosya içeriği korunuyor"
    )
    expect(exists(source), "Kopyalamada kaynak silinmiyor")

    let treeDir = freshDirectory()
    let sourceDir = makeDirectory("Kaynak", in: treeDir)
    writeFile("a.txt", "a", in: sourceDir)
    let nested = makeDirectory("Alt", in: sourceDir)
    writeFile("b.txt", "b", in: nested)
    let targetDir = treeDir.appendingPathComponent("Hedef", isDirectory: true)
    try? FileCopyService.copySync(source: sourceDir, to: targetDir, overwrite: false) { _ in }
    expect(exists(targetDir.appendingPathComponent("a.txt")), "Klasör içeriği kopyalanıyor")
    expect(exists(targetDir.appendingPathComponent("Alt/b.txt")), "Alt klasörler kopyalanıyor")

    let linkDir = freshDirectory()
    let linkTarget = writeFile("hedef.txt", in: linkDir)
    let link = linkDir.appendingPathComponent("baglanti.txt")
    try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: linkTarget)
    let linkCopy = linkDir.appendingPathComponent("kopya-baglanti.txt")
    try? FileCopyService.copySync(source: link, to: linkCopy, overwrite: false) { _ in }
    let linkValues = try? linkCopy.resourceValues(forKeys: [.isSymbolicLinkKey])
    expectEqual(linkValues?.isSymbolicLink, true, "Sembolik bağ bağ olarak kopyalanıyor")

    let conflictDir = freshDirectory()
    let conflictSource = writeFile("kaynak.txt", "yeni", in: conflictDir)
    let conflictTarget = writeFile("hedef.txt", "eski", in: conflictDir)
    expectThrows("Üzerine yazma kapalıyken çakışma hata veriyor") {
        try FileCopyService.copySync(source: conflictSource, to: conflictTarget, overwrite: false) { _ in }
    }
    try? FileCopyService.copySync(source: conflictSource, to: conflictTarget, overwrite: true) { _ in }
    expectEqual(
        (try? String(contentsOf: conflictTarget, encoding: .utf8)),
        "yeni",
        "Üzerine yazma açıkken içerik güncelleniyor"
    )

    let bigDir = freshDirectory()
    let bigSource = writeFile("buyuk.bin", String(repeating: "x", count: 2_500_000), in: bigDir)
    let bigTarget = bigDir.appendingPathComponent("buyuk-kopya.bin")
    final class ByteCounter: @unchecked Sendable {
        var total: Int64 = 0
    }
    let counter = ByteCounter()
    try? FileCopyService.copySync(source: bigSource, to: bigTarget, overwrite: false) { counter.total += $0 }
    expectEqual(counter.total, 2_500_000, "İlerleme geri bildirimi toplam baytı veriyor")

    let estimateSource = writeFile("e.txt", "12345", in: freshDirectory())
    let estimate = FileCopyService.estimateSync(estimateSource)
    expectEqual(estimate.bytes, 5, "Tahmini boyut doğru")
    expectEqual(estimate.itemCount, 1, "Tahmini öğe sayısı doğru")
}

// MARK: - Taşıma

func testMoveService() {
    group("Servis: FileMoveService")

    let dir = freshDirectory()
    let source = writeFile("tasina.txt", "veri", in: dir)
    let destination = dir.appendingPathComponent("tasinmis.txt")
    try? FileMoveService.moveSync(source: source, to: destination, overwrite: false) { _ in }

    expect(!exists(source), "Taşımada kaynak kaldırılıyor")
    expectEqual((try? String(contentsOf: destination, encoding: .utf8)), "veri", "Taşımada içerik korunuyor")

    let sameDir = freshDirectory()
    let sameURL = writeFile("ayni.txt", in: sameDir)
    expectError("Aynı konuma taşıma reddediliyor", {
        try FileMoveService.moveSync(source: sameURL, to: sameURL, overwrite: false) { _ in }
    }, matches: { if case FileOperationError.sameLocation = $0 { return true } else { return false } })

    let missingDir = freshDirectory()
    expectThrows("Olmayan kaynağı taşıma hata veriyor") {
        try FileMoveService.moveSync(
            source: missingDir.appendingPathComponent("yok.txt"),
            to: missingDir.appendingPathComponent("x.txt"),
            overwrite: false
        ) { _ in }
    }
}

// MARK: - Arama

func testSearchService() {
    group("Servis: FileSearchService")

    let root = freshDirectory()
    let nested = makeDirectory("Alt", in: root)
    let deeper = makeDirectory("Daha Derin", in: nested)
    writeFile("rapor-2025.txt", in: deeper)
    writeFile("baska.txt", in: root)

    let outcome = FileSearchService.searchSync(root: root, query: "rapor", includeHidden: false)
    expectEqual(outcome.items.count, 1, "Alt klasörlerdeki dosya bulunuyor")
    expectEqual(outcome.items.first?.name, "rapor-2025.txt", "Bulunan dosya adı doğru")
    expect(outcome.items.first?.relativePath != nil, "Göreli yol hesaplanıyor")
    expect(!outcome.reachedLimit, "Sınıra ulaşılmadı")

    let turkishRoot = freshDirectory()
    writeFile("İSTANBUL Raporu.txt", in: turkishRoot)
    writeFile("ıspanak.txt", in: turkishRoot)
    expectEqual(
        FileSearchService.searchSync(root: turkishRoot, query: "istanbul", includeHidden: false).items.count,
        1,
        "Büyük/küçük harf duyarsız arama (İ → i)"
    )
    expectEqual(
        FileSearchService.searchSync(root: turkishRoot, query: "ispanak", includeHidden: false).items.count,
        1,
        "Noktasız ı duyarsız arama"
    )

    let hiddenRoot = freshDirectory()
    writeFile(".gizli-rapor.txt", in: hiddenRoot)
    writeFile("rapor.txt", in: hiddenRoot)
    expectEqual(
        FileSearchService.searchSync(root: hiddenRoot, query: "rapor", includeHidden: false).items.count,
        1,
        "Gizli dosyalar aramada atlanıyor"
    )
    expectEqual(
        FileSearchService.searchSync(root: hiddenRoot, query: "rapor", includeHidden: true).items.count,
        2,
        "Gizli dosyalar dahil aranabiliyor"
    )

    let limitRoot = freshDirectory()
    for index in 0..<6 { writeFile("kayit-\(index).txt", in: limitRoot) }
    let limited = FileSearchService.searchSync(root: limitRoot, query: "kayit", includeHidden: false, limit: 3)
    expectEqual(limited.items.count, 3, "Sonuç sınırı uygulanıyor")
    expect(limited.reachedLimit, "Sınıra ulaşıldığı bildiriliyor")

    expectEqual(
        FileSearchService.searchSync(root: limitRoot, query: "   ", includeHidden: false).items.count,
        0,
        "Boş sorgu sonuç döndürmüyor"
    )

    expectEqual(FileSearchService.normalize("İSTANBUL"), "istanbul", "normalize: İ → i")
    expectEqual(FileSearchService.normalize("IŞIK"), "isik", "normalize: I → i, Ş → s")
}

// MARK: - Gelişmiş arama

func testAdvancedSearchService() {
    group("Servis: gelişmiş arama")

    let root = freshDirectory()
    let nested = makeDirectory("Alt", in: root)
    writeFile("rapor-2025.txt", "kısa", in: root)
    writeFile("notlar.pdf", "pdf içerik", in: root)
    writeFile("uzun.txt", String(repeating: "a", count: 200), in: root)
    writeFile("alt-rapor.txt", "merhaba dünya", in: nested)
    writeFile("buyuk.txt", String(repeating: "b", count: 3000), in: nested)
    let excluded = makeDirectory("node_modules", in: root)
    writeFile("gizli-rapor.txt", "x", in: excluded)
    writeFile(".gizli.txt", "gizli", in: root)

    var wildcard = SearchCriteria()
    wildcard.nameQuery = "*.txt"
    expectEqual(
        FileSearchService.searchSync(root: root, criteria: wildcard).items.count,
        5,
        "Joker desen (*.txt) eşleşiyor"
    )

    var regex = SearchCriteria()
    regex.nameQuery = "^rapor-[0-9]{4}\\.txt$"
    regex.useRegex = true
    expectEqual(
        FileSearchService.searchSync(root: root, criteria: regex).items.count,
        1,
        "Düzenli ifade ile ad araması"
    )

    var extensionFilter = SearchCriteria()
    extensionFilter.extensions = ["PDF"]
    expectEqual(
        FileSearchService.searchSync(root: root, criteria: extensionFilter).items.count,
        1,
        "Uzantı süzgeci (büyük harf duyarsız)"
    )

    var sizeFilter = SearchCriteria()
    sizeFilter.minimumSize = 150
    sizeFilter.maximumSize = 500
    let sized = FileSearchService.searchSync(root: root, criteria: sizeFilter)
    expectEqual(sized.items.count, 1, "Boyut aralığı süzgeci")
    expectEqual(sized.items.first?.name, "uzun.txt", "Boyut aralığındaki doğru dosya")

    var contentFilter = SearchCriteria()
    contentFilter.contentQuery = "dunya"
    let content = FileSearchService.searchSync(root: root, criteria: contentFilter)
    expectEqual(content.items.count, 1, "İçerik araması Türkçe karakter duyarsız")
    expectEqual(content.items.first?.name, "alt-rapor.txt", "İçerikte eşleşen dosya")

    var binaryContent = SearchCriteria()
    binaryContent.contentQuery = "dunya"
    let binaryURL = root.appendingPathComponent("ikili.bin")
    var binaryData = Data([0x00, 0x01, 0x02, 0x03])
    binaryData.append("dünya".data(using: .utf8) ?? Data())
    try? binaryData.write(to: binaryURL)
    let binaryOutcome = FileSearchService.searchSync(root: root, criteria: binaryContent)
    expectEqual(binaryOutcome.items.count, 1, "İkili dosya içerik aramasında atlanıyor")
    try? FileManager.default.removeItem(at: binaryURL)

    var excludedCriteria = SearchCriteria()
    excludedCriteria.nameQuery = "rapor"
    excludedCriteria.excludePatterns = ["node_modules"]
    expectEqual(
        FileSearchService.searchSync(root: root, criteria: excludedCriteria).items.count,
        2,
        "Hariç tutulan klasörün altına inilmiyor"
    )

    var nonRecursive = SearchCriteria()
    nonRecursive.nameQuery = "rapor"
    nonRecursive.recursive = false
    expectEqual(
        FileSearchService.searchSync(root: root, criteria: nonRecursive).items.count,
        1,
        "Alt klasörler hariç arama"
    )

    var foldersOnly = SearchCriteria()
    foldersOnly.nameQuery = "*"
    foldersOnly.includeFiles = false
    foldersOnly.includeFolders = true
    let folders = FileSearchService.searchSync(root: root, criteria: foldersOnly)
    expectEqual(folders.items.count, 2, "Yalnızca klasörler listeleniyor")

    let oldURL = writeFile("eski.txt", "eski", in: root)
    try? FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
        ofItemAtPath: oldURL.path
    )
    var dateFilter = SearchCriteria()
    dateFilter.nameQuery = "eski"
    dateFilter.modifiedBefore = Date(timeIntervalSince1970: 2_000_000)
    expectEqual(
        FileSearchService.searchSync(root: root, criteria: dateFilter).items.count,
        1,
        "Tarih aralığı süzgeci"
    )

    var cancelledCriteria = SearchCriteria()
    cancelledCriteria.nameQuery = "rapor"
    let cancellation = SearchCancellation()
    cancellation.cancel()
    let cancelled = FileSearchService.searchSync(
        root: root,
        criteria: cancelledCriteria,
        cancellation: cancellation
    )
    expect(cancelled.wasCancelled, "İptal bayrağı bildiriliyor")
    expectEqual(cancelled.items.count, 0, "İptal edilen arama sonuç döndürmüyor")

    expectEqual(SearchCriteria().isEmpty, true, "Boş ölçüt algılanıyor")
    expectEqual(cancelledCriteria.isEmpty, false, "Dolu ölçüt algılanıyor")
    expect(
        FileSearchService.matchesAnyPattern("rapor.tmp", patterns: ["*.tmp"]),
        "Joker eşleşmesi doğrudan çalışıyor"
    )
    expect(
        !FileSearchService.matchesAnyPattern("rapor.txt", patterns: ["*.tmp"]),
        "Uymayan desen reddediliyor"
    )
}

// MARK: - Hash

func testFileHashService() {
    group("Servis: SHA-256")

    let dir = freshDirectory("hash")
    let abcURL = writeFile("abc.txt", "abc", in: dir)
    expectEqual(
        try? FileHashService.sha256(of: abcURL),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "Bilinen SHA-256 değeri (abc)"
    )

    let emptyURL = writeFile("bos.txt", "", in: dir)
    expectEqual(
        try? FileHashService.sha256(of: emptyURL),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "Boş dosyanın SHA-256 değeri"
    )

    let bigData = Data(repeating: 0x41, count: FileHashService.chunkSize * 2 + 17)
    let bigURL = dir.appendingPathComponent("buyuk.bin")
    try? bigData.write(to: bigURL)
    let bigDigest = try? FileHashService.sha256(of: bigURL)
    expectEqual((bigDigest ?? "").count, 64, "Parçalı okumada 64 karakterlik özet")

    let folder = makeDirectory("Klasor", in: dir)
    let missing = dir.appendingPathComponent("yok.txt")
    let results = FileHashService.hashes(for: [abcURL, folder, missing])
    expectEqual(results.count, 2, "Klasör atlanıyor, eksik dosya sonuçta")
    expect(results.contains { $0.errorMessage != nil }, "Okunamayan dosya hata ile raporlanıyor")

    let control = TransferControl()
    control.cancel()
    expectThrows("İptal edilen hash hesaplaması hata veriyor") {
        _ = try FileHashService.sha256(of: bigURL, control: control)
    }
}

// MARK: - Görüntüleyici ve düzenleyici

func testFileViewerService() {
    group("Servis: görüntüleyici")

    let dir = freshDirectory("viewer")
    let turkishURL = writeFile("turkce.txt", "Merhaba dünya\nİkinci satır", in: dir)
    do {
        let document = try FileViewerService().loadText(url: turkishURL)
        expectEqual(document.encoding, .utf8, "UTF-8 kodlaması algılanıyor")
        expectEqual(document.text, "Merhaba dünya\nİkinci satır", "Metin doğru okunuyor")
        expectEqual(document.isTruncated, false, "Küçük dosya kısaltılmıyor")
        expectEqual(document.isBinary, false, "Metin dosyası ikili değil")
    } catch {
        expect(false, "Metin dosyası okunabildi (\(error.localizedDescription))")
    }

    let utf16URL = dir.appendingPathComponent("utf16.txt")
    var utf16Data = Data([0xFF, 0xFE])
    utf16Data.append("merhaba".data(using: .utf16LittleEndian) ?? Data())
    try? utf16Data.write(to: utf16URL)
    do {
        let document = try FileViewerService().loadText(url: utf16URL)
        expectEqual(document.encoding, .utf16LittleEndian, "UTF-16 LE BOM algılanıyor")
        expect(document.text.contains("merhaba"), "UTF-16 metni çözülüyor")
    } catch {
        expect(false, "UTF-16 dosyası okunabildi (\(error.localizedDescription))")
    }

    let binaryData = Data([0x00, 0x01, 0x02, 0x03, 0x41])
    expect(FileViewerService.isBinary(binaryData), "NUL baytı ikili dosya sayılıyor")
    expect(!FileViewerService.isBinary("düz metin".data(using: .utf8) ?? Data()), "Düz metin ikili değil")

    let longURL = writeFile("uzun.txt", String(repeating: "x", count: 100), in: dir)
    do {
        let truncated = try FileViewerService().loadText(url: longURL, maximumBytes: 10)
        expect(truncated.isTruncated, "Sınırlı okuma kısaltma bildiriyor")
    } catch {
        expect(false, "Sınırlı okuma başarılı (\(error.localizedDescription))")
    }

    let hexURL = writeFile("abc.bin", "ABC", in: dir)
    do {
        let hex = try FileViewerService().hexDump(url: hexURL)
        expect(hex.text.contains("41 42 43"), "Hex görünümünde baytlar var")
        expect(hex.text.hasPrefix("00000000"), "Hex görünümünde ofset var")
    } catch {
        expect(false, "Hex görünümü üretildi (\(error.localizedDescription))")
    }

    let saveURL = writeFile("kaydet.txt", "eski", in: dir)
    do {
        try FileViewerService.save(text: "yeni içerik", to: saveURL, encoding: .utf8)
        expectEqual(
            try String(contentsOf: saveURL, encoding: .utf8),
            "yeni içerik",
            "Atomik kaydetme içeriği yazıyor"
        )
    } catch {
        expect(false, "Kaydetme başarılı (\(error.localizedDescription))")
    }

    expectThrows("Dış değişiklik algılanıyor") {
        try FileViewerService.save(
            text: "üzerine yazma",
            to: saveURL,
            encoding: .utf8,
            expectedModificationDate: Date(timeIntervalSince1970: 1)
        )
    }

    let offsets = FileViewerService.lineStartOffsets(in: "a\nbb\nccc" as NSString)
    expectEqual(offsets, [0, 2, 5], "Satır başlangıçları doğru")
    expectEqual(FileViewerService.lineStartOffsets(in: "a\n" as NSString), [0], "Sondaki satır sonu boş satır sayılmıyor")
    expectEqual(FileViewerService.lineStartOffsets(in: "" as NSString), [0], "Boş metinde tek satır")
}

@MainActor
func testFileEditorViewModel() async {
    group("Görünüm: FileEditorViewModel")

    let dir = freshDirectory("editor")
    let url = writeFile("duzenle.txt", "başlangıç", in: dir)
    let model = FileEditorViewModel(url: url)
    await model.load()
    expectEqual(model.text, "başlangıç", "Düzenleyici içeriği yüklüyor")
    expectEqual(model.hasUnsavedChanges, false, "Yüklemede değişiklik yok")

    model.text = "değişti"
    expect(model.hasUnsavedChanges, "Değişiklik algılanıyor")
    let saved = await model.save()
    expect(saved, "Düzenleyici kaydediyor")
    expectEqual(
        try? String(contentsOf: url, encoding: .utf8),
        "değişti",
        "Kaydedilen içerik dosyada"
    )
    expectEqual(model.hasUnsavedChanges, false, "Kaydettikten sonra değişiklik yok")

    model.text = "dış değişiklik denemesi"
    try? FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 5)],
        ofItemAtPath: url.path
    )
    let conflictingSave = await model.save()
    expectEqual(conflictingSave, false, "Dış değişiklikte kaydetme reddediliyor")
    expect(model.isConfirmingOverwrite, "Dış değişiklik uyarısı gösteriliyor")

    let binaryURL = dir.appendingPathComponent("ikili.bin")
    try? Data([0, 1, 2, 3]).write(to: binaryURL)
    let binaryModel = FileEditorViewModel(url: binaryURL)
    await binaryModel.load()
    expect(binaryModel.errorMessage != nil, "İkili dosya düzenleyicide açılmıyor")
}

// MARK: - Yardımcı görünüm modelleri

/// Ana iş parçacığındaki bir koşul sağlanana kadar kısa aralıklarla bekler.
@MainActor
func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

@MainActor
func testAdvancedSearchViewModel() async {
    group("Görünüm: gelişmiş arama modeli")

    let dir = freshDirectory("advsearch-vm")
    _ = writeFile("bir.txt", "içerik", in: dir)
    _ = writeFile("iki.pdf", "pdf", in: dir)
    let sub = makeDirectory("alt", in: dir)
    _ = writeFile("uc.txt", "alt içerik", in: sub)

    let model = AdvancedSearchViewModel(root: dir)
    model.nameQuery = "*.txt"
    model.start()
    let finished = await waitUntil { !model.isSearching }
    expect(finished, "Arama zamanında tamamlandı")
    expectEqual(
        Set(model.results.map(\.name)),
        Set(["bir.txt", "uc.txt"]),
        "Ad deseni alt klasörlerle birlikte süzülüyor"
    )
    expectEqual(model.errorMessage, nil, "Geçerli aramada hata yok")

    let csv = dir.appendingPathComponent("sonuclar.csv")
    do {
        try model.exportCSV(to: csv)
        let content = (try? String(contentsOf: csv, encoding: .utf8)) ?? ""
        expect(content.contains("bir.txt") && content.contains("uc.txt"), "CSV sonuçları içeriyor")
        let raw = (try? Data(contentsOf: csv)) ?? Data()
        expect(raw.starts(with: [0xEF, 0xBB, 0xBF]), "CSV UTF-8 BOM ile yazılıyor")
    } catch {
        expect(false, "CSV dışa aktarıldı (\(error.localizedDescription))")
    }

    let emptyModel = AdvancedSearchViewModel(root: dir)
    emptyModel.start()
    expect(emptyModel.errorMessage != nil, "Boş ölçütte uyarı gösteriliyor")
    expect(!emptyModel.isSearching, "Boş ölçütte arama başlamıyor")

    let invalidRegex = AdvancedSearchViewModel(root: dir)
    invalidRegex.nameQuery = "["
    invalidRegex.useRegex = true
    invalidRegex.start()
    expect(invalidRegex.errorMessage != nil, "Geçersiz düzenli ifade reddediliyor")

    let invalidSize = AdvancedSearchViewModel(root: dir)
    invalidSize.nameQuery = "*.txt"
    invalidSize.minimumSizeText = "abc"
    invalidSize.start()
    expect(invalidSize.errorMessage != nil, "Geçersiz boyut reddediliyor")

    let invertedSize = AdvancedSearchViewModel(root: dir)
    invertedSize.nameQuery = "*.txt"
    invertedSize.minimumSizeText = "10"
    invertedSize.maximumSizeText = "1"
    invertedSize.start()
    expect(invertedSize.errorMessage != nil, "Ters boyut aralığı reddediliyor")

    let resetModel = AdvancedSearchViewModel(root: dir)
    resetModel.nameQuery = "*.txt"
    resetModel.includeHidden = true
    resetModel.reset()
    expectEqual(resetModel.nameQuery, "", "Sıfırlama ad alanını temizliyor")
    expectEqual(resetModel.includeHidden, false, "Sıfırlama gizli seçeneğini kapatıyor")
}

@MainActor
func testFileHashViewModel() async {
    group("Görünüm: hash modeli")

    let dir = freshDirectory("hash-vm")
    let file = writeFile("abc.txt", "abc", in: dir)
    let model = FileHashViewModel(urls: [file, dir])
    await model.start()

    expectEqual(model.results.count, 1, "Klasör sonuçlara katılmıyor")
    expectEqual(
        model.results.first?.digest,
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "Model bilinen SHA-256 değerini üretiyor"
    )
    expectEqual(model.isComputing, false, "Hesaplama tamamlanınca durum güncelleniyor")

    let csv = dir.appendingPathComponent("hash.csv")
    do {
        try model.exportCSV(to: csv)
        let content = (try? String(contentsOf: csv, encoding: .utf8)) ?? ""
        expect(content.contains("abc.txt"), "CSV dosya adını içeriyor")
        expect(content.contains("ba7816bf"), "CSV özeti içeriyor")
    } catch {
        expect(false, "Hash CSV dışa aktarıldı (\(error.localizedDescription))")
    }

    model.cancel()
    expect(model.wasCancelled || !model.isComputing, "Tamamlanmış işlem iptalden etkilenmiyor")
}

@MainActor
func testFolderCompareViewModel() async {
    group("Görünüm: klasör karşılaştırma modeli")

    let left = freshDirectory("compare-vm-left")
    let right = freshDirectory("compare-vm-right")
    _ = writeFile("ayni.txt", "aynı", in: left)
    _ = writeFile("ayni.txt", "aynı", in: right)
    _ = writeFile("solda.txt", "sol", in: left)
    _ = writeFile("sagda.txt", "sağ", in: right)

    let model = FolderCompareViewModel(leftRoot: left, rightRoot: right)
    model.start()
    let finished = await waitUntil { !model.isComparing }
    expect(finished, "Karşılaştırma zamanında tamamlandı")
    expectEqual(model.outcome?.count(of: .onlyLeft), 1, "Yalnızca solda olan sayısı doğru")
    expectEqual(model.outcome?.count(of: .onlyRight), 1, "Yalnızca sağda olan sayısı doğru")
    expectEqual(model.outcome?.count(of: .identical), 1, "Aynı dosya sayısı doğru")

    model.filter = .onlyLeft
    expectEqual(model.filteredEntries.map(\.relativePath), ["solda.txt"], "Süzgeç yalnızca sol tarafı gösteriyor")
    model.filter = .differences
    expect(!model.filteredEntries.contains { $0.status == .identical }, "Fark süzgeci aynı satırları gizliyor")

    let csv = left.appendingPathComponent("karsilastirma.csv")
    do {
        try model.exportCSV(to: csv)
        let content = (try? String(contentsOf: csv, encoding: .utf8)) ?? ""
        expect(content.contains("solda.txt"), "Karşılaştırma CSV'si satırları içeriyor")
    } catch {
        expect(false, "Karşılaştırma CSV dışa aktarıldı (\(error.localizedDescription))")
    }

    let sameModel = FolderCompareViewModel(leftRoot: left, rightRoot: left)
    sameModel.start()
    let sameFinished = await waitUntil { !sameModel.isComparing }
    expect(sameFinished, "Aynı klasör karşılaştırması sonuçlandı")
    expect(sameModel.errorMessage != nil, "Aynı klasör için hata gösteriliyor")
}

func testSelectionPatternMatcher() {
    group("Yardımcı: seçim deseni eşleştirme")

    expect(
        SelectionPatternMatcher.matches(name: "rapor.TXT", pattern: "*.txt", useRegex: false),
        "Joker büyük/küçük harf duyarsız eşleşiyor"
    )
    expect(
        !SelectionPatternMatcher.matches(name: "rapor.pdf", pattern: "*.txt", useRegex: false),
        "Joker uymayan adı reddediyor"
    )
    expect(
        SelectionPatternMatcher.matches(name: "abc", pattern: "a?c", useRegex: false),
        "Tek karakter jokeri eşleşiyor"
    )
    expect(
        !SelectionPatternMatcher.matches(name: "ac", pattern: "a?c", useRegex: false),
        "Tek karakter jokeri eksik harfte eşleşmiyor"
    )
    expect(
        SelectionPatternMatcher.matches(name: "RAPOR-2024", pattern: "rapor", useRegex: false),
        "Alt dize büyük/küçük harf duyarsız eşleşiyor"
    )
    expect(
        SelectionPatternMatcher.matches(name: "İSTANBUL", pattern: "istanbul", useRegex: false),
        "Türkçe harfler aksan duyarsız eşleşiyor"
    )
    expect(
        SelectionPatternMatcher.matches(name: "belge.PDF", pattern: "pdf$", useRegex: true),
        "Düzenli ifade büyük/küçük harf duyarsız eşleşiyor"
    )
    expect(
        SelectionPatternMatcher.matches(name: "rapor.txt", pattern: "^rapor", useRegex: true),
        "Düzenli ifade başlangıç çapası çalışıyor"
    )
    expect(
        !SelectionPatternMatcher.matches(name: "rapor.txt", pattern: "[", useRegex: true),
        "Geçersiz düzenli ifade eşleşmiyor"
    )
    expect(
        !SelectionPatternMatcher.isValidRegex("["),
        "Geçersiz düzenli ifade algılanıyor"
    )
    expect(
        SelectionPatternMatcher.isValidRegex("^rapor.*txt$"),
        "Geçerli düzenli ifade kabul ediliyor"
    )
    expect(
        !SelectionPatternMatcher.matches(name: "rapor.txt", pattern: "   ", useRegex: false),
        "Boş desen eşleşmiyor"
    )
}

// MARK: - Klasör karşılaştırma

func testFolderCompareService() {
    group("Servis: klasör karşılaştırma")

    let left = freshDirectory("compare-left")
    let right = freshDirectory("compare-right")
    writeFile("ayni.txt", "aynı içerik", in: left)
    writeFile("ayni.txt", "aynı içerik", in: right)
    writeFile("sol.txt", "yalnızca sol", in: left)
    writeFile("sag.txt", "yalnızca sağ", in: right)
    writeFile("boyut.txt", "1234", in: left)
    writeFile("boyut.txt", "123", in: right)
    writeFile("icerik.txt", "aaaa", in: left)
    writeFile("icerik.txt", "bbbb", in: right)
    let leftDateURL = writeFile("tarih.txt", "aynı", in: left)
    let rightDateURL = writeFile("tarih.txt", "aynı", in: right)
    try? FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
        ofItemAtPath: leftDateURL.path
    )
    try? FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 2_000_000)],
        ofItemAtPath: rightDateURL.path
    )
    writeFile("tip", "dosya", in: left)
    _ = makeDirectory("tip", in: right)
    writeFile(".gizli.txt", "gizli", in: left)
    writeFile("ic.txt", "iç", in: makeDirectory("alt", in: left))
    writeFile("ic.txt", "iç", in: makeDirectory("alt", in: right))

    var options = CompareOptions()
    options.compareSize = true
    options.compareDate = false
    options.compareContent = false
    options.includeHidden = false
    options.recursive = true

    do {
        let outcome = try FolderCompareService.compareSync(left: left, right: right, options: options)
        let byPath = Dictionary(uniqueKeysWithValues: outcome.entries.map { ($0.relativePath, $0) })
        expectEqual(byPath["ayni.txt"]?.status, .identical, "Aynı dosya eşit")
        expectEqual(byPath["sol.txt"]?.status, .onlyLeft, "Yalnızca solda")
        expectEqual(byPath["sag.txt"]?.status, .onlyRight, "Yalnızca sağda")
        expectEqual(byPath["boyut.txt"]?.status, .differentSize, "Farklı boyut")
        expectEqual(byPath["tip"]?.status, .typeMismatch, "Dosya/klasör tür uyuşmazlığı")
        expectEqual(byPath["alt/ic.txt"]?.status, .identical, "Alt klasördeki aynı dosya")
        expect(byPath[".gizli.txt"] == nil, "Gizli öğe varsayılan olarak atlanıyor")
        expectEqual(outcome.leftItemCount, 8, "Sol taraftaki öğe sayısı")
        expectEqual(outcome.rightItemCount, 8, "Sağ taraftaki öğe sayısı")

        options.includeHidden = true
        let hiddenOutcome = try FolderCompareService.compareSync(left: left, right: right, options: options)
        let hiddenEntry = hiddenOutcome.entries.first { $0.relativePath == ".gizli.txt" }
        expectEqual(hiddenEntry?.status, .onlyLeft, "Gizli öğe dahil edilebiliyor")

        options.includeHidden = false
        options.compareDate = true
        let dateOutcome = try FolderCompareService.compareSync(left: left, right: right, options: options)
        let dateEntry = dateOutcome.entries.first { $0.relativePath == "tarih.txt" }
        expectEqual(dateEntry?.status, .differentDate, "Farklı tarih algılanıyor")

        options.compareDate = false
        options.compareContent = true
        let contentOutcome = try FolderCompareService.compareSync(left: left, right: right, options: options)
        let contentEntry = contentOutcome.entries.first { $0.relativePath == "icerik.txt" }
        expectEqual(contentEntry?.status, .differentContent, "Farklı içerik SHA-256 ile algılanıyor")
        let sameEntry = contentOutcome.entries.first { $0.relativePath == "ayni.txt" }
        expectEqual(sameEntry?.status, .identical, "Aynı içerik eşit sayılıyor")

        var nonRecursive = options
        nonRecursive.recursive = false
        nonRecursive.compareContent = false
        let shallow = try FolderCompareService.compareSync(left: left, right: right, options: nonRecursive)
        expect(!shallow.entries.contains { $0.relativePath.contains("/") }, "Alt klasörler hariç tutuluyor")
        expect(shallow.entries.contains { $0.relativePath == "alt" }, "Üst düzey klasör listeleniyor")

        // Karşılaştırma hiçbir dosyayı değiştirmemeli.
        expectEqual(
            try? String(contentsOf: left.appendingPathComponent("sol.txt"), encoding: .utf8),
            "yalnızca sol",
            "Karşılaştırma sol dosyayı değiştirmiyor"
        )
        expectEqual(
            try? String(contentsOf: right.appendingPathComponent("sag.txt"), encoding: .utf8),
            "yalnızca sağ",
            "Karşılaştırma sağ dosyayı değiştirmiyor"
        )
    } catch {
        expect(false, "Klasör karşılaştırma (\(error.localizedDescription))")
    }

    expectThrows("Aynı klasör reddediliyor") {
        _ = try FolderCompareService.compareSync(left: left, right: left, options: options)
    }
    expectThrows("İç içe klasör reddediliyor") {
        _ = try FolderCompareService.compareSync(
            left: left,
            right: left.appendingPathComponent("alt"),
            options: options
        )
    }

    let cancelled = TransferControl()
    cancelled.cancel()
    do {
        _ = try FolderCompareService.compareSync(
            left: left,
            right: right,
            options: options,
            control: cancelled
        )
        expect(false, "İptal edilen karşılaştırma hata veriyor")
    } catch is CancellationError {
        expect(true, "İptal edilen karşılaştırma CancellationError veriyor")
    } catch {
        expect(false, "İptal hatası bekleniyordu: \(error.localizedDescription)")
    }
}

// MARK: - Özellikler

func testFileProperties() {
    group("Model: FileProperties")

    let dir = freshDirectory()
    let fileURL = writeFile("ozellik.txt", "1234567890", in: dir)

    if let properties = FileProperties.load(for: fileURL) {
        expectEqual(properties.name, "ozellik.txt", "Özellik adı")
        expect(!properties.sizeText.isEmpty, "Boyut metni dolu")
        expect(properties.isReadable, "Okunabilirlik bilgisi")
        expect(properties.itemCountText == nil, "Dosyada öğe sayısı yok")
        expect(!properties.permissionsText.isEmpty, "İzin metni dolu")
    } else {
        expect(false, "Dosya özellikleri yüklenebildi")
    }

    let folderURL = makeDirectory("Klasör", in: dir)
    writeFile("a.txt", in: folderURL)
    writeFile("b.txt", in: folderURL)
    expect(FileProperties.load(for: folderURL, includeFolderSize: true)?.itemCountText != nil, "Klasörde öğe sayısı var")

    expect(FileProperties.load(for: dir.appendingPathComponent("yok.txt")) == nil, "Olmayan yol için nil")

    let measureURL = makeDirectory("Ölçüm", in: dir)
    writeFile("a.txt", "12345", in: measureURL)
    writeFile("b.txt", "123", in: measureURL)
    let measurement = FileProperties.folderMeasurement(for: measureURL)
    expectEqual(measurement.bytes, 8, "Klasör boyutu ölçümü")
    expectEqual(measurement.itemCount, 2, "Klasör öğe sayısı ölçümü")
}

// MARK: - Biçimlendiriciler

func testFormatters() {
    group("Yardımcılar: biçimlendiriciler")

    expectEqual(FileSizeFormatter.string(fromBytes: 0), "0 bayt", "0 bayt gösterimi")
    expect(FileSizeFormatter.string(fromBytes: 512).contains("bayt"), "Bayt birimi")
    expect(FileSizeFormatter.string(fromBytes: 2_048).contains("KB"), "KB birimi")
    expect(FileSizeFormatter.string(fromBytes: 5 * 1_048_576).contains("MB"), "MB birimi")
    expect(FileSizeFormatter.string(fromBytes: 3 * 1_073_741_824).contains("GB"), "GB birimi")

    expectEqual(PermissionsFormatter.symbolicString(fromMode: 0o755), "rwxr-xr-x", "Sembolik izin 755")
    expectEqual(PermissionsFormatter.symbolicString(fromMode: 0o644), "rw-r--r--", "Sembolik izin 644")
    expectEqual(PermissionsFormatter.octalString(fromMode: 0o644), "644", "Sekizlik izin 644")

    expectEqual(DateFormatterHelper.listString(from: nil), "—", "Boş tarih listesi")
    expectEqual(DateFormatterHelper.detailedString(from: nil), "—", "Boş tarih ayrıntısı")
    expect(!DateFormatterHelper.listString(from: Date()).isEmpty, "Tarih biçimlendirmesi dolu")

    let errors: [Error] = [
        FileOperationError.destinationExists(URL(fileURLWithPath: "/tmp/a")),
        FileOperationError.invalidName("x"),
        FileOperationError.sourceMissing(URL(fileURLWithPath: "/tmp/b")),
        FileOperationError.accessDenied(URL(fileURLWithPath: "/tmp/c")),
        FileOperationError.notADirectory(URL(fileURLWithPath: "/tmp/d")),
        FileOperationError.sameLocation(
            URL(fileURLWithPath: "/tmp/e"),
            URL(fileURLWithPath: "/tmp/e")
        ),
        FileOperationError.cancelled,
        FileOperationError.copyFailed(URL(fileURLWithPath: "/tmp/f"), "hata"),
        FileOperationError.searchFailed("hata")
    ]
    var messagesOK = true
    for error in errors {
        if ErrorMessages.title(for: error).isEmpty || ErrorMessages.message(for: error).isEmpty {
            messagesOK = false
        }
    }
    expect(messagesOK, "Tüm hata türleri için Türkçe başlık ve mesaj var")

    var progress = OperationProgress(
        kind: .copy, currentItemName: "a", completedItems: 1, totalItems: 4, completedBytes: 50, totalBytes: 200
    )
    expectEqual(progress.fraction, 0.25, "Bayt tabanlı ilerleme oranı")
    progress.totalBytes = 0
    expectEqual(progress.fraction, 0.25, "Öğe tabanlı ilerleme oranı")
    progress.totalItems = 0
    expectEqual(progress.fraction, 0, "Bilinmeyen toplamda sıfır")

    expect(ConflictPolicy.ask.automaticDecision == nil, "ask politikası otomatik karar vermez")
    expectEqual(ConflictPolicy.overwrite.automaticDecision, .overwrite, "overwrite politikası")
    expectEqual(ConflictPolicy.skip.automaticDecision, .skip, "skip politikası")
    expectEqual(ConflictPolicy.keepBoth.automaticDecision, .keepBoth, "keepBoth politikası")

    expectEqual(TransferMode.copy.operationKind, .copy, "Pano kopyalama türü")
    expectEqual(TransferMode.move.operationKind, .move, "Pano taşıma türü")
    expectEqual(OperationKind.copy.localizedTitle, L.t("operation.copy"), "İşlem adı yerelleştirilmiş")
}

// MARK: - Ayarlar

@MainActor
func testSettingsStore() {
    group("Servis: SettingsStore")

    let suiteName = "com.gms.commander.standalone.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        expect(false, "Test UserDefaults paketi oluşturulabildi")
        return
    }

    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = SettingsStore(defaults: defaults)
    expectEqual(store.showHiddenFiles, false, "Gizli dosyalar varsayılan kapalı")
    expectEqual(store.foldersFirst, true, "Klasörler önce varsayılan açık")
    expectEqual(store.conflictPolicy, .ask, "Çakışma politikası varsayılan ask")
    expectEqual(store.sortKey(for: .left), .name, "Varsayılan sıralama ad")
    expectEqual(store.sortAscending(for: .left), true, "Varsayılan sıralama artan")

    store.showHiddenFiles = true
    store.foldersFirst = false
    store.conflictPolicy = .keepBoth

    let reloaded = SettingsStore(defaults: defaults)
    expectEqual(reloaded.showHiddenFiles, true, "Gizli dosya tercihi kalıcı")
    expectEqual(reloaded.foldersFirst, false, "Klasörler önce tercihi kalıcı")
    expectEqual(reloaded.conflictPolicy, .keepBoth, "Çakışma politikası kalıcı")

    store.setSort(key: .size, ascending: false, for: .left)
    expectEqual(store.sortKey(for: .left), .size, "Sol panel sıralaması ayrı")
    expectEqual(store.sortAscending(for: .left), false, "Sol panel yönü ayrı")
    expectEqual(store.sortKey(for: .right), .name, "Sağ panel sıralaması etkilenmiyor")

    store.setPath(URL(fileURLWithPath: "/Users/Shared"), for: .right)
    expectEqual(store.rightPanelPath, "/Users/Shared", "Panel yolu kalıcı")

    expectEqual(PanelSide.left.opposite, .right, "Karşı panel sol → sağ")
    expectEqual(PanelSide.right.opposite, .left, "Karşı panel sağ → sol")

    // Klavye profili
    expectEqual(store.keyBindings.label(for: .copy), "F5", "Varsayılan kopyalama tuşu F5")
    expectEqual(store.setFunctionKey(.f12, for: .copy), nil, "Boş tuş ataması kabul ediliyor")
    expectEqual(store.keyBindings.label(for: .copy), "F12", "Kopyalama tuşu F12 oldu")
    let reloadedKeys = SettingsStore(defaults: defaults)
    expectEqual(reloadedKeys.keyBindings.label(for: .copy), "F12", "Klavye ataması kalıcı")
    expectEqual(
        store.setFunctionKey(.f3, for: .terminal),
        .view,
        "Çakışan tuş ataması reddediliyor"
    )
    expectEqual(store.keyBindings.label(for: .terminal), "F9", "Çakışmada eski atama korunuyor")
    store.resetFunctionKeyBindings()
    expectEqual(store.keyBindings.label(for: .copy), "F5", "Varsayılana dönüş çalışıyor")

    expectEqual(store.additionalKeyBindings.key(for: .rename), .commandShiftR, "Varsayılan yeniden adlandırma kısayolu")
    expectEqual(store.setAdditionalShortcut(.commandShiftP, for: .rename), nil, "Ek kısayol değiştiriliyor")
    expectEqual(store.additionalKeyBindings.key(for: .rename), .commandShiftP, "Yeni ek kısayol uygulanıyor")
    expectEqual(
        store.setAdditionalShortcut(.commandShiftP, for: .properties),
        .rename,
        "Çakışan ek kısayol reddediliyor"
    )
    let reloadedAdditional = SettingsStore(defaults: defaults)
    expectEqual(reloadedAdditional.additionalKeyBindings.key(for: .rename), .commandShiftP, "Ek kısayol kalıcı")

    store.setVisibleColumns([.name, .fileExtension, .size], for: .left)
    store.setColumnWidths([PanelColumn.fileExtension.rawValue: 110], for: .left)
    let reloadedColumns = SettingsStore(defaults: defaults)
    expectEqual(
        reloadedColumns.visibleColumns(for: .left),
        [.name, .fileExtension, .size],
        "Boyut ve uzantı sütunları ayrı açılıp kapanabiliyor"
    )
    expectEqual(
        reloadedColumns.columnWidths(for: .left)[PanelColumn.fileExtension.rawValue],
        110,
        "Uzantı sütunu genişliği kalıcı"
    )
}

@MainActor
func testThemeManager() {
    group("Görünüm: ThemeManager")

    let suiteName = "com.gms.commander.theme.standalone.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        expect(false, "Tema testi için UserDefaults oluşturulabildi")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        ThemeManager.shared.themeID = .voidCommander
        ThemeManager.shared.resetFontSize()
        ThemeManager.shared.resetFontStyle()
    }

    let theme = ThemeManager(defaults: defaults)
    theme.themeID = .graphite
    theme.fontSize = 16
    theme.fontStyle = .classicDOS
    let reloaded = ThemeManager(defaults: defaults)
    expectEqual(reloaded.themeID, .graphite, "Tema tercihi kalıcı")
    expectEqual(reloaded.fontSize, 16, "Yazı boyutu kalıcı")
    expectEqual(reloaded.fontStyle, .classicDOS, "Klasik DOS yazı tipi tercihi kalıcı")
    expectEqual(reloaded.signature.themeID, .graphite, "Görünüm imzası etkin temayı içeriyor")
    expectEqual(reloaded.signature.fontSize, 16, "Görünüm imzası etkin yazı boyutunu içeriyor")
    expectEqual(reloaded.signature.fontStyle, .classicDOS, "Görünüm imzası yazı tipi tercihini içeriyor")
    expectEqual(
        ThemeManager.clampFontSize(99),
        ThemeManager.fontSizeRange.upperBound,
        "Yazı boyutu izin verilen sınıra sabitleniyor"
    )
    expect(ThemeID.daylight.isLight, "Açık tema tanınıyor")
    expect(!ThemeID.graphite.isLight, "Koyu tema tanınıyor")
}

func testPathBreadcrumbs() {
    group("Gezinme: yol kırıntıları")

    let target = URL(
        fileURLWithPath: "/Users/testuser/Documents/GMS_PROJE/TEKNIK DOKUMANLAR",
        isDirectory: true
    )
    let breadcrumbs = PathBreadcrumb.make(for: target)
    expectEqual(
        breadcrumbs.map(\.name),
        ["/", "Users", "testuser", "Documents", "GMS_PROJE", "TEKNIK DOKUMANLAR"],
        "Yol disk kökünden itibaren tüm bileşenlerle gösteriliyor"
    )
    expectEqual(breadcrumbs[3].url.path, "/Users/testuser/Documents", "Ara bileşen hedef yolu doğru")
    expectEqual(breadcrumbs.last?.url.standardizedFileURL, target.standardizedFileURL, "Son bileşen geçerli klasörü gösteriyor")

    let external = PathBreadcrumb.make(for: URL(fileURLWithPath: "/Volumes/Data/Project", isDirectory: true))
    expectEqual(external.map(\.name), ["/", "Volumes", "Data", "Project"], "Ev dışı yol kökten gösteriliyor")
    expectEqual(external[2].url.path, "/Volumes/Data", "Ev dışı ara klasör hedefi doğru")
}

func testPasteTargetResolver() {
    group("Gezinme: yapıştırma hedefi")

    let active = URL(fileURLWithPath: "/Users/testuser/Documents", isDirectory: true)
    let inactive = URL(fileURLWithPath: "/Users/testuser/Downloads", isDirectory: true)
    let localSource = active.appendingPathComponent("rapor.txt")
    let externalSource = URL(fileURLWithPath: "/tmp/baska.txt")

    expectEqual(
        PasteTargetResolver.destination(
            activeDirectory: active,
            inactiveDirectory: inactive,
            sources: [localSource]
        ).path,
        inactive.path,
        "Etkin paneldeki öğeler etkin olmayan panele yapıştırılır"
    )
    expectEqual(
        PasteTargetResolver.destination(
            activeDirectory: active,
            inactiveDirectory: inactive,
            sources: [externalSource]
        ).path,
        active.path,
        "Dışarıdan gelen öğeler etkin panele yapıştırılır"
    )
    expectEqual(
        PasteTargetResolver.destination(
            activeDirectory: active,
            inactiveDirectory: inactive,
            sources: [localSource, externalSource]
        ).path,
        active.path,
        "Karışık kaynaklarda etkin panel hedef olur"
    )
    expectEqual(
        PasteTargetResolver.destination(
            activeDirectory: active,
            inactiveDirectory: inactive,
            sources: []
        ).path,
        active.path,
        "Kaynak yokken etkin panel hedef olur"
    )
}

@MainActor
func testFavoritesViewModel() {
    group("ViewModel: FavoritesViewModel")

    let suiteName = "com.gms.commander.favorites.standalone.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        expect(false, "Test UserDefaults paketi oluşturulabildi")
        return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(try? JSONEncoder().encode([FavoriteFolder]()), forKey: FavoritesViewModel.Keys.items)
    defaults.set(true, forKey: FavoritesViewModel.Keys.mountedVolumesSeeded)
    let favorites = FavoritesViewModel(defaults: defaults)
    expect(favorites.isEmpty, "Saklanan boş liste korunuyor")

    let directory = freshDirectory("favorites")
    let folder = makeDirectory("Belgeler", in: directory)
    let application = makeDirectory("Editor.app", in: directory)
    let quickAccessGroupID = favorites.groups.first(where: { $0.role == .quickAccess })?.id
    let applicationsGroupID = favorites.groups.first(where: { $0.role == .applications })?.id
    expectEqual(favorites.suggestedGroupID(for: folder), quickAccessGroupID, "Klasör Hızlı Erişim bölümüne yönlendiriliyor")
    expectEqual(favorites.suggestedGroupID(for: application), applicationsGroupID, "Uygulama Uygulamalar bölümüne yönlendiriliyor")
    expect(FavoriteFolder(path: application.path).isApplication, "Uygulama paketi uygulama olarak tanınıyor")
    expectEqual(FavoriteFolder.displayName(for: "/Users/test/Documents"), L.t("favorites.folder.documents"), "Standart klasör adı Türkçeleştiriliyor")
    expect(favorites.add(url: folder), "Var olan klasör ekleniyor")
    expect(favorites.contains(url: folder), "Eklenen klasör bulunuyor")
    expect(!favorites.add(path: folder.path + "/"), "Son eğik çizgiyle yinelenen yol reddediliyor")
    expectEqual(favorites.items.count, 1, "Yinelenen kayıt eklenmiyor")
    let projectsGroup = favorites.groups.first(where: { $0.name == L.t("favorites.group.projects") })
    if let projectsGroup {
        expect(favorites.add(url: folder, to: projectsGroup.id), "Var olan öğe hedef bölüme eklenince taşınıyor")
        expectEqual(favorites.items.first?.groupID, projectsGroup.id, "Kayıt hedef bölüme taşınmış")
        expect(!favorites.add(url: folder, to: projectsGroup.id), "Aynı bölümdeki yinelenen kayıt reddediliyor")
    } else {
        expect(false, "Projeler ve alternatif hızlı erişim bölümü var")
    }

    let reloaded = FavoritesViewModel(defaults: defaults)
    expectEqual(reloaded.items.map(\.path), [folder.standardizedFileURL.path], "Kayıt yeniden yükleniyor")
    expect(reloaded.remove(url: folder), "Klasör adrese göre kaldırılıyor")
    expect(!reloaded.remove(url: folder), "Olmayan kayıt tekrar kaldırılamıyor")

    expect(reloaded.toggle(url: folder), "Toggle klasörü ekliyor")
    expect(!reloaded.toggle(url: folder), "Toggle kayıtlı klasörü kaldırıyor")
    let favoriteFile = writeFile("favorites-file.txt", in: directory)
    expectEqual(reloaded.kind(of: favoriteFile), .file, "Dosya türü doğru belirleniyor")
    expect(!reloaded.add(url: favoriteFile), "Dosya klasör bölümüne eklenmiyor")
    if let applicationsGroupID {
        expect(reloaded.add(url: favoriteFile, to: applicationsGroupID), "Dosya Uygulamalar bölümüne ekleniyor")
        expectEqual(reloaded.items.last?.isDirectory, false, "Dosya kaydı klasör değil")
    } else {
        expect(false, "Uygulamalar bölümü bulunuyor")
    }
    expect(
        !reloaded.add(url: directory.appendingPathComponent("missing", isDirectory: true)),
        "Olmayan klasör eklenmiyor"
    )

    let favorite = FavoriteFolder(path: directory.path + "/")
    expectEqual(favorite.path, directory.standardizedFileURL.path, "Favori yolu standartlaştırılıyor")
    expectEqual(favorite.name, directory.lastPathComponent, "Görünen ad yoldan üretiliyor")

    let customGroup = reloaded.addGroup(name: "Projeler", colorHex: 0x42C98A)
    expect(customGroup != nil, "Özel renkli bölüm ekleniyor")
    expect(reloaded.addGroup(name: "   ") == nil, "Boş bölüm adı reddediliyor")
    expect(reloaded.add(url: folder), "Klasör yeniden hızlı erişime ekleniyor")
    let favoriteID = reloaded.items.first(where: { $0.path == folder.standardizedFileURL.path })?.id
    if let favoriteID, let customGroup {
        reloaded.move(id: favoriteID, to: customGroup.id)
        expectEqual(
            reloaded.items.first(where: { $0.id == favoriteID })?.groupID,
            customGroup.id,
            "Öğe özel bölüme taşınıyor"
        )
        reloaded.rename(id: favoriteID, to: "Özel Ad")
        expectEqual(
            reloaded.items.first(where: { $0.id == favoriteID })?.name,
            "Özel Ad",
            "Hızlı erişim görünen adı değişiyor"
        )
        reloaded.removeGroup(id: customGroup.id)
        expect(reloaded.groups.contains(where: { $0.id == customGroup.id }) == false, "Özel bölüm siliniyor")
        expectEqual(
            reloaded.items.first(where: { $0.id == favoriteID })?.groupID,
            reloaded.groups.first?.id,
            "Silinen bölümdekiler başka bölüme taşınıyor"
        )
    } else {
        expect(false, "Bölüm düzenleme için kayıt ve grup bulunuyor")
    }

    let fileGroup = reloaded.addGroup(name: "Belgelerim", colorHex: 0xEF6461, kind: .file)
    expectEqual(fileGroup?.kind, .file, "Bölüm dosya tipinde oluşturuluyor")
    if let fileGroup, let applicationsGroupID {
        expect(reloaded.canAdd(url: favoriteFile, to: fileGroup.id), "Dosya, dosya bölümüne uygun")
        expect(!reloaded.canAdd(url: folder, to: fileGroup.id), "Klasör, dosya bölümüne uygun değil")
        expect(
            reloaded.canAdd(url: folder, to: applicationsGroupID) == false,
            "Klasör, Uygulamalar bölümüne uygun değil"
        )
        var renamed = fileGroup
        renamed.name = "Belgeler"
        reloaded.updateGroup(renamed)
        expectEqual(
            reloaded.groups.first(where: { $0.id == fileGroup.id })?.kind,
            .file,
            "Bölüm güncellenirken kayıt tipi korunuyor"
        )
    } else {
        expect(false, "Dosya bölümü oluşturuluyor")
    }

    reloaded.resetToDefaults()
    expectEqual(
        reloaded.items.map(\.path),
        FavoritesViewModel.defaultItems().map(\.path),
        "Varsayılan favoriler geri yükleniyor"
    )

    let diskSuiteName = "com.gms.commander.favorites.volumes.\(UUID().uuidString)"
    if let diskDefaults = UserDefaults(suiteName: diskSuiteName) {
        defer { diskDefaults.removePersistentDomain(forName: diskSuiteName) }
        let diskGroup = FavoriteGroup(name: "Diskler", colorHex: 0xE0A84B, role: .disks)
        let staleVolume = FavoriteFolder(path: "/Volumes/Commander-Removed", groupID: diskGroup.id)
        diskDefaults.set(try? JSONEncoder().encode([diskGroup]), forKey: FavoritesViewModel.Keys.groups)
        diskDefaults.set(try? JSONEncoder().encode([staleVolume]), forKey: FavoritesViewModel.Keys.items)
        diskDefaults.set(true, forKey: FavoritesViewModel.Keys.mountedVolumesSeeded)
        let diskFavorites = FavoritesViewModel(defaults: diskDefaults)
        diskFavorites.refreshMountedVolumes()
        expect(
            !diskFavorites.items.contains(where: { $0.path == staleVolume.path }),
            "Artık bağlı olmayan disk hızlı erişimden temizleniyor"
        )
    } else {
        expect(false, "Disk yenileme testi için UserDefaults oluşturuluyor")
    }
}

// MARK: - Panel görünüm modeli

@MainActor
func testFilePanelViewModel() async {
    group("ViewModel: FilePanelViewModel")

    let dir = freshDirectory("panel")
    writeFile("b.txt", "bb", in: dir)
    writeFile("a.txt", "a", in: dir)
    makeDirectory("Alt", in: dir)

    let suiteName = "com.gms.commander.panel.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        expect(false, "Panel testi için UserDefaults oluşturulabildi")
        return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = SettingsStore(defaults: defaults)
    settings.refreshAutomatically = false
    settings.gitIntegrationEnabled = false
    settings.setPath(dir, for: .left)

    let panel = FilePanelViewModel(side: .left, settings: settings)
    await panel.activate()

    expectEqual(panel.currentDirectory.standardizedFileURL, dir.standardizedFileURL, "Panel kayıtlı klasörü açıyor")
    expectEqual(panel.items.count, 3, "Panel öğeleri yükleniyor")
    expectEqual(panel.items.first?.name, "Alt", "Klasörler önce geliyor")
    expectEqual(panel.isLoading, false, "Yükleme tamamlandı")
    expect(!panel.title.isEmpty, "Panel başlığı dolu")
    expectEqual(panel.itemCountText, L.t("status.itemCount", 1, 2), "Durum çubuğu öğe sayılarını gösteriyor")

    let sub = dir.appendingPathComponent("Alt", isDirectory: true)
    panel.navigate(to: sub)
    await waitForLoad(panel)
    expectEqual(panel.currentDirectory.standardizedFileURL, sub.standardizedFileURL, "Alt klasöre gezinme")
    expect(panel.canGoBack, "Geri gidilebilir")

    panel.goBack()
    await waitForLoad(panel)
    expectEqual(panel.currentDirectory.standardizedFileURL, dir.standardizedFileURL, "Geri gezinme çalışıyor")
    expect(panel.canGoForward, "İleri gidilebilir")

    panel.goForward()
    await waitForLoad(panel)
    expectEqual(panel.currentDirectory.standardizedFileURL, sub.standardizedFileURL, "İleri gezinme çalışıyor")

    panel.goUp()
    await waitForLoad(panel)
    expectEqual(panel.currentDirectory.standardizedFileURL, dir.standardizedFileURL, "Üst klasöre çıkma")
    expectEqual(panel.focusedItem?.name, "Alt", "Üst klasörde çıkılan alt klasör seçiliyor")

    expectEqual(panel.sortKey, .name, "Varsayılan sıralama anahtarı")
    panel.sort(by: .name)
    expectEqual(panel.sortAscending, false, "Aynı sütuna sıralama yönü değiştiriyor")
    expectEqual(panel.items.first?.name, "Alt", "Azalan sıralamada da klasör önce")
    panel.sort(by: .size)
    expectEqual(panel.sortKey, .size, "Yeni sütuna sıralama")
    expectEqual(panel.sortAscending, true, "Yeni sütunda yön artan")

    panel.clearSelection()
    expectEqual(panel.selectionText, L.t("status.noSelection"), "Seçim yokken metin")
    panel.setSelection([dir.appendingPathComponent("a.txt")])
    expectEqual(panel.selection.count, 1, "Seçim güncelleniyor")
    expectEqual(panel.selectionText, L.t("status.selection", 1), "Seçim metni")
    expectEqual(panel.focusedItem?.name, "a.txt", "Odaklanan öğe")

    panel.navigate(to: dir.appendingPathComponent("yok", isDirectory: true))
    for _ in 0..<60 where panel.alert == nil {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    expect(panel.alert != nil, "Olmayan klasör için uyarı gösteriliyor")
    expect(panel.items.isEmpty, "Hatalı klasörde liste boş")
}

@MainActor
func waitForLoad(_ panel: FilePanelViewModel) async {
    try? await Task.sleep(nanoseconds: 60_000_000)
    for _ in 0..<100 {
        if !panel.isLoading { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

// MARK: - İşlem görünüm modeli ve kısayollar

func testOperationViewModel() {
    group("ViewModel: FileOperationViewModel")

    var progress = OperationProgress(
        kind: .copy,
        currentItemName: "belge.pdf",
        completedItems: 2,
        totalItems: 4,
        completedBytes: 500,
        totalBytes: 2000
    )

    var model = FileOperationViewModel(progress: progress)
    expectEqual(model.fraction, 0.25, "İlerleme oranı bayt üzerinden hesaplanıyor")
    expectEqual(model.percentText, "25%", "Yüzde metni tam sayıya yuvarlanıyor")
    expect(model.showsByteCount, "Toplam boyut bilindiğinde bayt metni gösterilir")
    expect(model.byteCountText.contains(" / "), "Bayt metni tamamlanan / toplam biçiminde")
    expectEqual(model.title, progress.kind.localizedTitle, "Başlık işlem türünden geliyor")
    expectEqual(model.currentItemName, "belge.pdf", "Geçerli öğe adı aktarılıyor")

    progress.totalBytes = 0
    progress.completedItems = 1
    model = FileOperationViewModel(progress: progress)
    expectEqual(model.fraction, 0.25, "Boyut bilinmiyorsa öğe sayısına göre hesaplanıyor")
    expect(!model.showsByteCount, "Toplam boyut sıfırken bayt metni gizleniyor")

    progress.totalItems = 0
    progress.completedItems = 0
    model = FileOperationViewModel(progress: progress)
    expectEqual(model.fraction, 0, "Veri yokken ilerleme sıfır")
    expectEqual(model.percentText, "0%", "Veri yokken yüzde sıfır")
}

func testKeyboardShortcutCatalog() {
    group("Yardımcılar: KeyboardShortcutManager")

    let shortcuts = KeyboardShortcutManager.all
    expectEqual(shortcuts.count, 36, "Katalog 36 kısayol içeriyor")
    expect(shortcuts.allSatisfy { !$0.keys.isEmpty }, "Tüm kısayollarda tuş birleşimi var")
    expect(shortcuts.allSatisfy { !$0.titleKey.isEmpty }, "Tüm kısayollarda eylem anahtarı var")
    expectEqual(Set(shortcuts.map(\.id)).count, shortcuts.count, "Kısayol kimlikleri benzersiz")
    expect(shortcuts.contains { $0.keys == "Space" }, "Boşluk tuşu Quick Look ile eşleşiyor")
    expect(shortcuts.contains { $0.keys == "⌘⌫" }, "Command+Delete Çöp Kutusu ile eşleşiyor")

    expectEqual(KeyboardShortcutManager.action(keyCode: 49, modifiers: []), .quickLook, "Space hızlı önizlemeye gider")
    expectEqual(KeyboardShortcutManager.action(keyCode: 36, modifiers: []), .open, "Return açma eylemine gider")
    expectEqual(KeyboardShortcutManager.action(keyCode: 51, modifiers: []), .goUp, "Backspace üst klasöre gider")
    expect(KeyboardShortcutManager.action(keyCode: 51, modifiers: .command) == nil, "Değiştirici tuş varken yalın eylem devre dışı")
    expect(KeyboardShortcutManager.action(keyCode: 0, modifiers: []) == nil, "Diğer tuşlar yönlendirilmez")
}

func testFunctionKeys() {
    group("Yardımcılar: İşlev tuşları")

    let actions = KeyboardShortcutManager.FunctionKeyAction.allCases
    expectEqual(actions.count, 9, "Dokuz işlev tuşu tanımlı")
    expectEqual(Set(actions.map(\.keyLabel)).count, 9, "İşlev tuşu etiketleri benzersiz")
    expectEqual(actions.map(\.keyLabel), ["F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11"], "İşlev tuşu sırası NC düzeninde")
    expect(actions.allSatisfy { !$0.title.isEmpty }, "Tüm işlev tuşlarında Türkçe başlık var")

    expectEqual(KeyboardShortcutManager.functionKeyAction(keyCode: 96, modifiers: []), .copy, "F5 kopyalamaya gider")
    expectEqual(KeyboardShortcutManager.functionKeyAction(keyCode: 97, modifiers: []), .move, "F6 taşımaya gider")
    expectEqual(KeyboardShortcutManager.functionKeyAction(keyCode: 98, modifiers: []), .newFolder, "F7 yeni klasör açar")
    expectEqual(KeyboardShortcutManager.functionKeyAction(keyCode: 100, modifiers: []), .delete, "F8 silmeye gider")
    expectEqual(KeyboardShortcutManager.functionKeyAction(keyCode: 101, modifiers: []), .terminal, "F9 Terminal açar")
    expectEqual(KeyboardShortcutManager.functionKeyAction(keyCode: 109, modifiers: []), .quit, "F10 çıkışa gider")
    expectEqual(KeyboardShortcutManager.functionKeyAction(keyCode: 103, modifiers: []), .compress, "F11 sıkıştırmaya gider")
    expectEqual(
        KeyboardShortcutManager.functionKeyAction(keyCode: 99, modifiers: .function),
        .view,
        "F3, Fn değiştiricisiyle de önizleme açar"
    )
    expect(
        KeyboardShortcutManager.functionKeyAction(keyCode: 96, modifiers: .command) == nil,
        "Değiştirici tuş varken işlev tuşu devre dışı"
    )

    expectEqual(KeyboardShortcutManager.command(keyCode: 96, modifiers: []), .function(.copy), "Komut işlev tuşunu döndürür")
    expectEqual(KeyboardShortcutManager.command(keyCode: 49, modifiers: []), .bare(.quickLook), "Komut yalın tuşu döndürür")
    expectEqual(
        KeyboardShortcutManager.command(keyCode: 15, modifiers: [.command, .shift]),
        .additional(.rename),
        "Değiştirilebilir yeniden adlandırma kısayolu çalışıyor"
    )
    expect(KeyboardShortcutManager.command(keyCode: 0, modifiers: []) == nil, "Bilinmeyen tuş komut üretmez")

    let customBindings = KeyboardShortcutManager.FunctionKeyBindings(
        dictionary: ["copy": "f12"]
    )
    expectEqual(customBindings.label(for: .copy), "F12", "Özel atama etiketi F12")
    expectEqual(
        KeyboardShortcutManager.functionKeyAction(
            keyCode: 111,
            modifiers: [],
            bindings: customBindings
        ),
        .copy,
        "Özel atama F12'yi kopyalamaya yönlendiriyor"
    )
    expect(
        KeyboardShortcutManager.functionKeyAction(
            keyCode: 96,
            modifiers: [],
            bindings: customBindings
        ) == nil,
        "Eski F5 tuşu özel atamada boş"
    )
    let duplicateBindings = KeyboardShortcutManager.FunctionKeyBindings(
        dictionary: ["terminal": "f3"]
    )
    expectEqual(
        duplicateBindings.label(for: .terminal),
        "F9",
        "Çakışan atama varsayılana geri alınıyor"
    )
}

func testZipArchiveService() async {
    group("Servis: ZipArchiveService")

    let directory = freshDirectory("archive")
    let first = writeFile("bir dosya.txt", "bir", in: directory)
    let folder = makeDirectory("klasor", in: directory)
    writeFile("ic.txt", "iki", in: folder)
    let destination = directory.appendingPathComponent("sonuc.zip")

    do {
        try await ZipArchiveService().compress(sources: [first, folder], to: destination)
        expect(exists(destination), "ZIP arşivi oluşturuluyor")

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", destination.path]
        process.standardOutput = output
        try process.run()
        let listing = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        expectEqual(process.terminationStatus, 0, "Arşiv doğrulanabiliyor")
        expect(listing.contains("bir dosya.txt"), "Boşluk içeren dosya arşivleniyor")
        expect(listing.contains("klasor/ic.txt"), "Alt klasör içeriği arşivleniyor")
    } catch {
        expect(false, "ZIP arşivi oluşturuluyor (\(error.localizedDescription))")
    }
}

// MARK: - Arşiv testleri

/// Testler için elle TAR başlığı üretir. Güvenlik testlerinde `bsdtar`ın
/// normalde izin vermeyeceği kayıtları (.., mutlak yol, symlink) oluşturmak
/// için kullanılır.
func makeTarEntry(
    name: String,
    type: Character = "0",
    linkName: String = "",
    data: Data = Data()
) -> Data {
    var header = [UInt8](repeating: 0, count: 512)
    func write(_ text: String, offset: Int, length: Int) {
        let bytes = Array(text.utf8.prefix(length))
        for (index, byte) in bytes.enumerated() {
            header[offset + index] = byte
        }
    }
    write(name, offset: 0, length: 100)
    write("0000644", offset: 100, length: 8)
    write("0000000", offset: 108, length: 8)
    write("0000000", offset: 116, length: 8)
    write(String(format: "%011o", data.count), offset: 124, length: 12)
    write(String(format: "%011o", 0), offset: 136, length: 12)
    // Sağlama alanı hesaplanırken boşluklarla doldurulur.
    for index in 148..<156 { header[index] = 0x20 }
    header[156] = UInt8(type.unicodeScalars.first!.value)
    write(linkName, offset: 157, length: 100)
    write("ustar", offset: 257, length: 6)
    write("00", offset: 263, length: 2)

    let checksum = header.reduce(0) { $0 + Int($1) }
    let checksumText = String(format: "%06o", checksum) + "\0 "
    write(checksumText, offset: 148, length: 8)

    var result = Data(header)
    if !data.isEmpty {
        result.append(data)
        let remainder = data.count % 512
        if remainder != 0 {
            result.append(Data(repeating: 0, count: 512 - remainder))
        }
    }
    return result
}

func makeTar(_ entries: [(name: String, type: Character, link: String, data: Data)]) -> Data {
    var data = Data()
    for entry in entries {
        data.append(makeTarEntry(
            name: entry.name,
            type: entry.type,
            linkName: entry.link,
            data: entry.data
        ))
    }
    data.append(Data(repeating: 0, count: 1024))
    return data
}

func testArchiveService() async {
    group("Servis: ArchiveService")

    // Yol normalleştirme
    expectEqual(ArchiveService.normalizedEntryPath("klasor/dosya.txt"), "klasor/dosya.txt", "Güvenli göreli yol kabul edilir")
    expect(ArchiveService.normalizedEntryPath("../kotu.txt") == nil, "Üst klasöre çıkan yol reddedilir")
    expect(ArchiveService.normalizedEntryPath("a/../../kotu.txt") == nil, "Gizlenmiş üst klasör reddedilir")
    expect(ArchiveService.normalizedEntryPath("/etc/passwd") == nil, "Mutlak yol reddedilir")
    expect(ArchiveService.normalizedEntryPath("C:/Windows/system.ini") == nil, "Windows sürücü yolu reddedilir")
    expect(ArchiveService.normalizedEntryPath("klasor\\dosya.txt") == "klasor/dosya.txt", "Ters eğik çizgi normalleştirilir")
    expect(ArchiveService.normalizedEntryPath("./dosya.txt") == "dosya.txt", "Nokta bileşeni atılır")

    // ZIP oluşturma, listeleme ve çıkarma
    let directory = freshDirectory("archive-extract")
    let sourceFile = writeFile("belge.txt", "arşiv içeriği", in: directory)
    let sourceFolder = makeDirectory("alt klasor", in: directory)
    writeFile("ic.txt", "alt içerik", in: sourceFolder)
    let zipURL = directory.appendingPathComponent("test.zip")
    let destination = freshDirectory("archive-destination")

    do {
        try await ZipArchiveService().compress(sources: [sourceFile, sourceFolder], to: zipURL)
        let service = ArchiveService()
        let entries = try service.listEntries(in: zipURL)
        expect(entries.contains { $0.path == "belge.txt" && !$0.isDirectory }, "ZIP dosyası listelenir")
        expect(entries.contains { $0.path == "alt klasor/ic.txt" }, "ZIP alt klasörü listelenir")

        let moved = try ArchiveService.extractSync(
            archive: zipURL,
            destination: destination,
            entries: entries,
            selectedPaths: nil,
            control: nil,
            progress: nil
        )
        expect(!moved.isEmpty, "ZIP arşivi çıkarılır")
        expectEqual(
            try String(contentsOf: destination.appendingPathComponent("alt klasor/ic.txt"), encoding: .utf8),
            "alt içerik",
            "Çıkarılan dosya içeriği doğru"
        )
        let leftover = (try? FileManager.default.contentsOfDirectory(atPath: destination.path))?.filter {
            $0.hasPrefix(".gms-arşiv-")
        } ?? []
        expect(leftover.isEmpty, "Çıkarma sonrası geçici klasör kalmaz")
    } catch {
        expect(false, "ZIP listeleme/çıkarma (\(error.localizedDescription))")
    }

    // TAR.GZ oluşturma ve listeleme
    let tarDirectory = freshDirectory("tar-source")
    let tarFile = writeFile("tar-ic.txt", "tar içeriği", in: tarDirectory)
    let tarGzURL = tarDirectory.appendingPathComponent("arsiv.tar.gz")
    do {
        try await ZipArchiveService().compress(sources: [tarFile], to: tarGzURL)
        let entries = try ArchiveService().listEntries(in: tarGzURL)
        expect(entries.contains { $0.path == "tar-ic.txt" }, "TAR.GZ oluşturulup listelenir")
    } catch {
        expect(false, "TAR.GZ oluşturma/listeleme (\(error.localizedDescription))")
    }

    // Zip Slip: elle hazırlanmış kötü niyetli TAR
    let maliciousDirectory = freshDirectory("archive-malicious")
    let maliciousTar = maliciousDirectory.appendingPathComponent("kotu.tar")
    let maliciousData = makeTar([
        (name: "../kacak.txt", type: "0", link: "", data: Data("kötü".utf8))
    ])
    try? maliciousData.write(to: maliciousTar)
    let safeDestination = freshDirectory("archive-safe-destination")
    do {
        _ = try ArchiveService().listEntries(in: maliciousTar)
        expect(false, "Zip Slip kaydı listelemede reddedilir")
    } catch {
        expect(true, "Zip Slip kaydı listelemede reddedilir")
    }

    // Mutlak yol içeren TAR
    let absoluteTar = maliciousDirectory.appendingPathComponent("mutlak.tar")
    try? makeTar([
        (name: "/tmp/kacak-gms.txt", type: "0", link: "", data: Data())
    ]).write(to: absoluteTar)
    expectError("Mutlak yol içeren arşiv reddedilir", {
        _ = try ArchiveService().listEntries(in: absoluteTar)
    }, matches: { error in
        if case ArchiveError.unsafeEntry = error { return true }
        return false
    })

    // Sembolik bağlantı: çıkarma sırasında yakalanmalı
    let symlinkTar = maliciousDirectory.appendingPathComponent("baglanti.tar")
    try? makeTar([
        (name: "kacak", type: "2", link: "/etc/passwd", data: Data())
    ]).write(to: symlinkTar)
    do {
        let entries = try ArchiveService().listEntries(in: symlinkTar)
        _ = try ArchiveService.extractSync(
            archive: symlinkTar,
            destination: safeDestination,
            entries: entries,
            selectedPaths: nil,
            control: nil,
            progress: nil
        )
        expect(false, "Sembolik bağlantılı arşiv çıkarılmaz")
    } catch {
        if case ArchiveError.symbolicLinkRejected = error {
            expect(true, "Sembolik bağlantılı arşiv çıkarılmaz")
        } else {
            expect(false, "Sembolik bağlantı hatası bekleniyordu (\(error))")
        }
    }
    expect(!exists(safeDestination.appendingPathComponent("kacak")), "Sembolik bağlantı hedefe taşınmaz")

    // Seçili öğe çıkarma
    let selectedTar = maliciousDirectory.appendingPathComponent("secim.tar")
    try? makeTar([
        (name: "bir.txt", type: "0", link: "", data: Data("1".utf8)),
        (name: "iki.txt", type: "0", link: "", data: Data("2".utf8))
    ]).write(to: selectedTar)
    let selectedDestination = freshDirectory("archive-selected")
    do {
        let entries = try ArchiveService().listEntries(in: selectedTar)
        _ = try ArchiveService.extractSync(
            archive: selectedTar,
            destination: selectedDestination,
            entries: entries,
            selectedPaths: ["iki.txt"],
            control: nil,
            progress: nil
        )
        expect(!exists(selectedDestination.appendingPathComponent("bir.txt")), "Seçilmeyen öğe çıkarılmaz")
        expect(exists(selectedDestination.appendingPathComponent("iki.txt")), "Seçilen öğe çıkarılır")
    } catch {
        expect(false, "Seçili öğe çıkarma (\(error.localizedDescription))")
    }

    // Yinelenen kayıt
    let duplicateTar = maliciousDirectory.appendingPathComponent("yinelenen.tar")
    try? makeTar([
        (name: "ayni.txt", type: "0", link: "", data: Data("1".utf8)),
        (name: "ayni.txt", type: "0", link: "", data: Data("2".utf8))
    ]).write(to: duplicateTar)
    expectError("Yinelenen kayıt reddedilir", {
        _ = try ArchiveService().listEntries(in: duplicateTar)
    }, matches: { error in
        if case ArchiveError.unsafeEntry = error { return true }
        return false
    })

    // Var olan hedefle çakışma: benzersiz ad üretilir
    let conflictDirectory = freshDirectory("archive-conflict")
    writeFile("bir.txt", "eski", in: conflictDirectory)
    let conflictTar = maliciousDirectory.appendingPathComponent("cakisma.tar")
    try? makeTar([
        (name: "bir.txt", type: "0", link: "", data: Data("yeni".utf8))
    ]).write(to: conflictTar)
    do {
        let entries = try ArchiveService().listEntries(in: conflictTar)
        _ = try ArchiveService.extractSync(
            archive: conflictTar,
            destination: conflictDirectory,
            entries: entries,
            selectedPaths: nil,
            control: nil,
            progress: nil
        )
        expectEqual(
            try String(contentsOf: conflictDirectory.appendingPathComponent("bir.txt"), encoding: .utf8),
            "eski",
            "Çıkarma mevcut dosyanın üzerine yazmaz"
        )
        expect(exists(conflictDirectory.appendingPathComponent("bir 2.txt")), "Çakışmada yeni ad kullanılır")
    } catch {
        expect(false, "Çakışma çıkarma (\(error.localizedDescription))")
    }
}

func testBatchRenameService() {
    group("Servis: BatchRenameService")

    let directory = freshDirectory("batch-rename")
    let first = writeFile("rapor.txt", "bir", in: directory)
    let second = writeFile("not.txt", "iki", in: directory)

    var options = BatchRenameOptions()
    options.prefix = "2026-"
    options.numberingEnabled = true
    options.numberingStart = 1
    options.numberingPadding = 2
    options.numberAtStart = false
    options.newExtension = "md"

    let plan = BatchRenameService.plan(files: [first, second], options: options)
    expectEqual(plan.changeCount, 2, "İki dosya için plan üretilir")
    expect(!plan.hasErrors, "Geçerli planda hata yok")
    expectEqual(plan.items[0].newName, "2026-not01.md", "Önek, sayaç ve uzantı uygulanır")
    expectEqual(plan.items[1].newName, "2026-rapor02.md", "Sayaç sıralı artar")

    do {
        let count = try BatchRenameService.apply(plan)
        expectEqual(count, 2, "Plan uygulanır")
        expect(exists(directory.appendingPathComponent("2026-rapor02.md")), "Yeni ad diske yazılır")
        expect(!exists(first), "Eski ad kalmaz")
    } catch {
        expect(false, "Plan uygulama (\(error.localizedDescription))")
    }

    // Var olan hedefle çakışma
    let conflictDirectory = freshDirectory("batch-conflict")
    let source = writeFile("a.txt", "kaynak", in: conflictDirectory)
    writeFile("b.txt", "mevcut", in: conflictDirectory)
    var conflictOptions = BatchRenameOptions()
    conflictOptions.find = "a"
    conflictOptions.replace = "b"
    let realConflictPlan = BatchRenameService.plan(files: [source], options: conflictOptions)
    expect(realConflictPlan.hasErrors, "Var olan ada çakışan plan hata verir")
    expectThrows("Hatalı plan uygulanmaz") {
        _ = try BatchRenameService.apply(realConflictPlan)
    }
    expectEqual(
        (try? String(contentsOf: source, encoding: .utf8)) ?? "",
        "kaynak",
        "Hatalı planda dosya değişmez"
    )

    // Yer değiştirme iki aşamalı uygulanır
    let swapDirectory = freshDirectory("batch-swap")
    let fileA = writeFile("a.txt", "A", in: swapDirectory)
    let fileB = writeFile("b.txt", "B", in: swapDirectory)
    let swapPlan = BatchRenamePlan(items: [
        BatchRenamePlanItem(source: fileA, oldName: "a.txt", newName: "b.txt", error: nil),
        BatchRenamePlanItem(source: fileB, oldName: "b.txt", newName: "a.txt", error: nil)
    ])
    do {
        _ = try BatchRenameService.apply(swapPlan)
        expectEqual(
            try String(contentsOf: swapDirectory.appendingPathComponent("a.txt"), encoding: .utf8),
            "B",
            "Yer değiştirmede a.txt içeriği B olur"
        )
        expectEqual(
            try String(contentsOf: swapDirectory.appendingPathComponent("b.txt"), encoding: .utf8),
            "A",
            "Yer değiştirmede b.txt içeriği A olur"
        )
    } catch {
        expect(false, "Yer değiştirme (\(error.localizedDescription))")
    }

    // Geçersiz düzenli ifade
    var regexOptions = BatchRenameOptions()
    regexOptions.find = "["
    regexOptions.useRegex = true
    let regexPlan = BatchRenameService.plan(files: [fileA], options: regexOptions)
    expect(regexPlan.hasErrors, "Geçersiz düzenli ifade hatası gösterilir")
}

func testTrashService() {
    group("Servis: TrashService")

    let root = freshDirectory("trash-root")
    let destination = freshDirectory("trash-restore")
    let service = TrashService(trashRoot: root)

    let trashedFile = writeFile("eski belge.txt", "çöp", in: root)
    let trashedFolder = makeDirectory("eski klasor", in: root)
    writeFile("ic.txt", "alt", in: trashedFolder)
    writeFile(".DS_Store", "x", in: root)

    do {
        let items = try service.listItems()
        expectEqual(items.count, 2, "Çöp kutusu öğeleri listelenir (.DS_Store hariç)")
        expect(items.contains { $0.name == "eski klasor" && $0.isDirectory }, "Klasör öğesi tanınır")

        writeFile("eski belge.txt", "hedefte var", in: destination)
        let restored = try service.restore(items, to: destination)
        expectEqual(restored.count, 2, "İki öğe geri yüklenir")
        expectEqual(
            try String(contentsOf: destination.appendingPathComponent("eski belge.txt"), encoding: .utf8),
            "hedefte var",
            "Geri yükleme mevcut dosyanın üzerine yazmaz"
        )
        expect(exists(destination.appendingPathComponent("eski belge 2.txt")), "Çakışmada yeni ad kullanılır")
        expect(exists(destination.appendingPathComponent("eski klasor/ic.txt")), "Klasör içeriğiyle geri yüklenir")
        expect(!exists(trashedFile), "Geri yüklenen dosya çöpten kaldırılır")
    } catch {
        expect(false, "Çöp kutusu listeleme/geri yükleme (\(error.localizedDescription))")
    }

    // Çöp kutusu dışındaki bir öğe geri yüklenemez.
    let outsider = writeFile("disarida.txt", "x", in: destination)
    let outsiderItem = TrashItem(
        url: outsider,
        name: outsider.lastPathComponent,
        isDirectory: false,
        size: 1,
        modificationDate: nil
    )
    expectError("Çöp dışındaki öğe geri yüklenmez", {
        _ = try service.restore([outsiderItem], to: destination)
    }, matches: { error in
        if case TrashError.sourceNotInTrash = error { return true }
        return false
    })

    // Boşaltma .DS_Store'u korur.
    writeFile("silinecek.txt", "x", in: root)
    do {
        try service.empty()
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        expectEqual(remaining, [".DS_Store"], "Çöp kutusu boşaltılır, .DS_Store korunur")
    } catch {
        expect(false, "Çöp kutusu boşaltma (\(error.localizedDescription))")
    }
}

func testTerminalTarget() {
    group("Servisler: Terminal hedefi")

    let directory = workRoot.appendingPathComponent("terminal-klasor", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let file = workRoot.appendingPathComponent("terminal-ornek.txt")
    try? "içerik".write(to: file, atomically: true, encoding: .utf8)

    expectEqual(
        TerminalService.resolvedDirectory(for: directory)?.path,
        directory.standardizedFileURL.path,
        "Klasör yolu doğrudan hedef olur"
    )
    expectEqual(
        TerminalService.resolvedDirectory(for: file)?.path,
        workRoot.standardizedFileURL.path,
        "Dosya yolu için üst klasör hedef olur"
    )
    expect(
        TerminalService.resolvedDirectory(for: workRoot.appendingPathComponent("olmayan-yol")) == nil,
        "Olmayan yol için hedef çözümlenmez"
    )
    expect(TerminalService.isAvailable, "Sistem Terminali kurulu")
}

// MARK: - Çalıştırma

try? FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)

print("GMS_Commander — Bağımsız Test Koşucusu")
print("Tarih: \(DateFormatterHelper.detailedString(from: Date()))")
print("Klasör: \(workRoot.path)")

testFileItem()
testFileManagerService()
testCopyService()
testMoveService()
testSearchService()
testAdvancedSearchService()
testFileHashService()
testFileViewerService()
await testFileEditorViewModel()
await testAdvancedSearchViewModel()
await testFileHashViewModel()
await testFolderCompareViewModel()
testSelectionPatternMatcher()
testFolderCompareService()
testFileProperties()
testFormatters()
testFavoritesViewModel()
testSettingsStore()
testThemeManager()
testPathBreadcrumbs()
testPasteTargetResolver()
await testFilePanelViewModel()
await testZipArchiveService()
await testArchiveService()
testTrashService()
testBatchRenameService()
testOperationViewModel()
testKeyboardShortcutCatalog()
testFunctionKeys()
testTerminalTarget()

try? FileManager.default.removeItem(at: workRoot)

print("\n" + String(repeating: "─", count: 60))
print("Geçen: \(Harness.passed)   Başarısız: \(Harness.failed)   Toplam: \(Harness.passed + Harness.failed)")

if Harness.failed > 0 {
    print("\nBaşarısız testler:")
    for failure in Harness.failures {
        print("  • \(failure)")
    }
    exit(1)
}

print("Tüm testler başarılı.")
exit(0)
