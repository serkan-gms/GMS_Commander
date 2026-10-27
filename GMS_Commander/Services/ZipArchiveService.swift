//
//  ZipArchiveService.swift
//  GMS_Commander
//
//  Seçili dosya ve klasörleri arşivler. Desteklenen biçimler dosya uzantısına
//  göre belirlenir: ZIP, TAR ve TAR.GZ.
//

import Foundation

enum ZipArchiveError: LocalizedError {
    case noSources
    case launchFailed(String)
    case compressionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSources:
            return "Arşivlenecek öğe seçilmedi."
        case .launchFailed(let reason):
            return "Sıkıştırma aracı başlatılamadı: \(reason)"
        case .compressionFailed(let reason):
            return "Arşiv oluşturulamadı: \(reason)"
        }
    }
}

struct ZipArchiveService: Sendable {
    /// Seçili öğeleri hedef arşive yazar.
    ///
    /// Biçim, hedef dosya uzantısından belirlenir. ZIP için `/usr/bin/zip`,
    /// TAR ve TAR.GZ için `/usr/bin/bsdtar` kullanılır. Kaynaklar kendi üst
    /// klasörlerine göre göreli adlarla eklenir; mutlak yol arşive yazılmaz.
    func compress(sources: [URL], to destination: URL) async throws {
        guard !sources.isEmpty, let first = sources.first else {
            throw ZipArchiveError.noSources
        }
        let format = ArchiveFormat.detect(destination) ?? .zip
        let sourceNames = sources.map(\.lastPathComponent)
        let destinationPath = destination.path
        let workingDirectory = first.deletingLastPathComponent()

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let errorPipe = Pipe()
            process.currentDirectoryURL = workingDirectory
            process.standardError = errorPipe

            switch format {
            case .zip:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.arguments = ["-q", "-r", "-FS", destinationPath]
                    + sourceNames.map { "./\($0)" }
            case .tar:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
                process.arguments = ["-cf", destinationPath] + sourceNames
            case .tarGz:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
                process.arguments = ["-czf", destinationPath] + sourceNames
            }

            do {
                try process.run()
            } catch {
                throw ZipArchiveError.launchFailed(error.localizedDescription)
            }
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let detail = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ZipArchiveError.compressionFailed(
                    detail.flatMap { $0.isEmpty ? nil : $0 } ?? "araç kodu \(process.terminationStatus)"
                )
            }
        }.value
    }
}
