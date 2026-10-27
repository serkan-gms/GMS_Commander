//
//  FileWatcherService.swift
//  GMS_Commander
//
//  Görüntülenen klasördeki değişiklikleri FSEvents ile izler ve panelin
//  kendiliğinden yenilenmesini sağlar. Bildirimler geciktirilerek birleştirilir.
//

import Foundation
import CoreServices

/// Klasör değişikliklerini izleyen servis.
@MainActor
final class FileWatcherService {
    private var stream: FSEventStreamRef?
    private var onChange: (() -> Void)?
    private var pendingWorkItem: DispatchWorkItem?
    private var watchedPath: String?

    /// İzlemenin etkin olup olmadığı.
    var isWatching: Bool { stream != nil }

    /// İzlenen klasörün yolu.
    var currentPath: String? { watchedPath }

    /// Belirtilen klasörü izlemeye başlar; önceki izleme varsa bırakılır.
    /// - Parameters:
    ///   - url: İzlenecek klasör.
    ///   - onChange: Değişiklik algılandığında ana iş parçacığında çağrılacak kapanış.
    func start(watching url: URL, onChange: @escaping () -> Void) {
        stop()

        self.onChange = onChange
        self.watchedPath = url.path

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [url.path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            FileWatcherService.streamCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(newStream, .main)
        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            return
        }
        stream = newStream
    }

    /// İzlemeyi durdurur.
    func stop() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        onChange = nil
        watchedPath = nil
    }

    /// Değişiklikleri birleştirerek tek bir yenileme tetikler.
    private func scheduleRefresh() {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.onChange?()
            }
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// FSEvents geri çağrısı. C imzası nedeniyle statik bir kapanış olarak tanımlanır.
    private static let streamCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        let service = Unmanaged<FileWatcherService>.fromOpaque(info).takeUnretainedValue()
        Task { @MainActor in
            service.scheduleRefresh()
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
