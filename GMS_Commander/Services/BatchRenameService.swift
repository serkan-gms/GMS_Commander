//
//  BatchRenameService.swift
//  GMS_Commander
//
//  Birden çok dosyayı kural tabanlı olarak yeniden adlandırır. Önce bir
//  önizleme planı üretilir; çakışma veya geçersiz ad varsa plan uygulanmaz.
//  Uygulama iki aşamalıdır: tüm kaynaklar geçici ada taşınır, ardından son
//  adlarına taşınır. Böylece A↔B gibi yer değiştirmeler veri kaybetmez.
//

import Foundation

// MARK: - Seçenekler

/// Toplu yeniden adlandırma kuralları.
struct BatchRenameOptions: Equatable, Sendable {
    /// Büyük/küçük harf dönüşümü.
    enum CaseMode: String, CaseIterable, Identifiable, Sendable {
        case unchanged
        case lowercased
        case uppercased
        case capitalized

        var id: String { rawValue }

        /// Kullanıcıya gösterilen Türkçe ad.
        var localizedName: String {
            switch self {
            case .unchanged: return L.t("batch.case.unchanged")
            case .lowercased: return L.t("batch.case.lower")
            case .uppercased: return L.t("batch.case.upper")
            case .capitalized: return L.t("batch.case.capitalized")
            }
        }
    }

    /// Aranan metin.
    var find = ""
    /// Aranan metnin yerine yazılacak metin.
    var replace = ""
    /// `find` düzenli ifade olarak yorumlansın mı?
    var useRegex = false
    /// Adın başına eklenecek metin.
    var prefix = ""
    /// Adın sonuna eklenecek metin.
    var suffix = ""
    /// Sayaç kullanılsın mı?
    var numberingEnabled = false
    /// Sayaç başlangıç değeri.
    var numberingStart = 1
    /// Sayaç artış adımı.
    var numberingStep = 1
    /// Sayaç basamak sayısı (sıfırla doldurulur).
    var numberingPadding = 3
    /// Sayaç adın başına mı eklensin?
    var numberAtStart = false
    /// Harf dönüşümü.
    var caseMode: CaseMode = .unchanged
    /// Yeni uzantı; boşsa mevcut uzantı korunur.
    var newExtension = ""
}

// MARK: - Plan

/// Tek bir yeniden adlandırma satırı.
struct BatchRenamePlanItem: Identifiable, Sendable {
    /// Kaynak adres.
    let source: URL
    /// Mevcut ad.
    let oldName: String
    /// Önerilen yeni ad.
    let newName: String
    /// Bu satırdaki hata; `nil` ise satır geçerli.
    let error: String?

    var id: URL { source }

    /// Ad değişmiyor mu?
    var isUnchanged: Bool { oldName == newName }

    /// Satır uygulanabilir mi?
    var isValid: Bool { error == nil && !isUnchanged }
}

/// Toplu yeniden adlandırma planı.
struct BatchRenamePlan: Sendable {
    let items: [BatchRenamePlanItem]

    /// Uygulanabilir satır sayısı.
    var changeCount: Int { items.filter(\.isValid).count }

    /// Herhangi bir satırda hata var mı?
    var hasErrors: Bool { items.contains { $0.error != nil } }

    /// Plan uygulanabilir mi?
    var canApply: Bool { changeCount > 0 && !hasErrors }
}

// MARK: - Hatalar

/// Toplu yeniden adlandırma hataları.
enum BatchRenameError: LocalizedError {
    case emptyPlan
    case invalidPlan
    case applyFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .emptyPlan:
            return "Yeniden adlandırılacak öğe yok."
        case .invalidPlan:
            return "Plan geçersiz: çakışan veya hatalı adlar var."
        case .applyFailed(let name, let detail):
            return "“\(name)” yeniden adlandırılamadı: \(detail)"
        }
    }
}

// MARK: - Servis

/// Toplu yeniden adlandırma servisi.
struct BatchRenameService: Sendable {
    /// Ad planını üretir. Dosya sistemine yazmaz.
    /// - Parameters:
    ///   - files: Yeniden adlandırılacak dosyalar (aynı klasörde olmalı).
    ///   - options: Kurallar.
    /// - Returns: Önizleme planı.
    static func plan(files: [URL], options: BatchRenameOptions) -> BatchRenamePlan {
        let sorted = files.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        var generated: [BatchRenamePlanItem] = []
        var regex: NSRegularExpression?
        var regexError: String?

        if options.useRegex, !options.find.isEmpty {
            do {
                regex = try NSRegularExpression(pattern: options.find)
            } catch {
                regexError = L.t("batch.error.regex")
            }
        }

        for (index, url) in sorted.enumerated() {
            let oldName = url.lastPathComponent
            var base = (oldName as NSString).deletingPathExtension
            let existingExtension = (oldName as NSString).pathExtension
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if let regexError {
                generated.append(BatchRenamePlanItem(
                    source: url,
                    oldName: oldName,
                    newName: oldName,
                    error: regexError
                ))
                continue
            }

            // Bul/değiştir
            if !options.find.isEmpty {
                if let regex {
                    let range = NSRange(base.startIndex..<base.endIndex, in: base)
                    base = regex.stringByReplacingMatches(
                        in: base,
                        range: range,
                        withTemplate: options.replace
                    )
                } else {
                    base = base.replacingOccurrences(of: options.find, with: options.replace)
                }
            }

            // Harf dönüşümü
            switch options.caseMode {
            case .unchanged: break
            case .lowercased: base = base.lowercased()
            case .uppercased: base = base.uppercased()
            case .capitalized: base = base.capitalized
            }

            // Sayaç
            if options.numberingEnabled {
                let value = options.numberingStart + index * options.numberingStep
                let padded = String(format: "%0\(max(options.numberingPadding, 1))ld", value)
                base = options.numberAtStart ? padded + base : base + padded
            }

            // Önek/sonek
            base = options.prefix + base + options.suffix

            // Uzantı
            let newExtension = options.newExtension
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            let finalExtension = newExtension.isEmpty ? existingExtension : newExtension
            var newName = isDirectory
                ? base
                : (finalExtension.isEmpty ? base : "\(base).\(finalExtension)")

            var error: String?
            if newName.isEmpty {
                error = L.t("batch.error.empty")
            } else if newName.contains("/") {
                error = L.t("batch.error.slash")
            } else if newName == "." || newName == ".." {
                error = L.t("batch.error.reserved")
            } else if newName.utf8.count > 255 {
                error = L.t("batch.error.tooLong")
            }
            if newName.isEmpty { newName = oldName }

            generated.append(BatchRenamePlanItem(
                source: url,
                oldName: oldName,
                newName: newName,
                error: error
            ))
        }

        // Aynı klasörde aynı hedef ada iki kez izin verilmez.
        var counts: [String: Int] = [:]
        for item in generated where item.error == nil {
            let key = "\(item.source.deletingLastPathComponent().path)/\(item.newName)".lowercased()
            counts[key, default: 0] += 1
        }

        // Hedefte zaten var olan (ve bu planın kaynağı olmayan) dosyalar çakışır.
        let sources = Set(sorted.map { $0.standardizedFileURL })
        let fileManager = FileManager.default

        let checked = generated.map { item -> BatchRenamePlanItem in
            guard item.error == nil else { return item }
            let directory = item.source.deletingLastPathComponent()
            let key = "\(directory.path)/\(item.newName)".lowercased()
            if counts[key, default: 0] > 1 {
                return BatchRenamePlanItem(
                    source: item.source,
                    oldName: item.oldName,
                    newName: item.newName,
                    error: L.t("batch.error.duplicate", item.newName)
                )
            }
            let target = directory.appendingPathComponent(item.newName)
            if fileManager.fileExists(atPath: target.path),
               !sources.contains(target.standardizedFileURL) {
                return BatchRenamePlanItem(
                    source: item.source,
                    oldName: item.oldName,
                    newName: item.newName,
                    error: L.t("batch.error.exists", item.newName)
                )
            }
            return item
        }

        return BatchRenamePlan(items: checked)
    }

    /// Planı uygular. Önce tüm kaynaklar geçici ada taşınır, sonra son adlarına.
    /// - Parameter plan: Önceden doğrulanmış plan.
    /// - Returns: Yeniden adlandırılan dosya sayısı.
    @discardableResult
    static func apply(_ plan: BatchRenamePlan) throws -> Int {
        guard plan.canApply else {
            throw plan.hasErrors ? BatchRenameError.invalidPlan : BatchRenameError.emptyPlan
        }
        let fileManager = FileManager.default
        let items = plan.items.filter(\.isValid)
        var temporaryMoves: [(temporary: URL, final: URL, source: URL)] = []

        // Birinci aşama: geçici adlar.
        do {
            for item in items {
                try Task.checkCancellation()
                let directory = item.source.deletingLastPathComponent()
                let temporary = directory.appendingPathComponent(
                    ".gms-rename-\(UUID().uuidString)"
                )
                try fileManager.moveItem(at: item.source, to: temporary)
                let finalURL = directory.appendingPathComponent(item.newName)
                temporaryMoves.append((temporary, finalURL, item.source))
            }
        } catch {
            // Hata durumunda taşınanları geri al.
            for move in temporaryMoves.reversed() {
                try? fileManager.moveItem(at: move.temporary, to: move.source)
            }
            throw error
        }

        // İkinci aşama: son adlar.
        for move in temporaryMoves {
            do {
                try fileManager.moveItem(at: move.temporary, to: move.final)
            } catch {
                throw BatchRenameError.applyFailed(
                    move.final.lastPathComponent,
                    error.localizedDescription
                )
            }
        }
        return temporaryMoves.count
    }

    /// Yeni adın geçerli olup olmadığını denetler (tek satırlık kullanım için).
    static func validationError(for name: String) -> String? {
        if name.isEmpty { return L.t("batch.error.empty") }
        if name.contains("/") { return L.t("batch.error.slash") }
        if name == "." || name == ".." { return L.t("batch.error.reserved") }
        if name.utf8.count > 255 { return L.t("batch.error.tooLong") }
        return nil
    }
}
