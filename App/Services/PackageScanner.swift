import Foundation

protocol PackageScanning: Sendable {
    func scan(packageURL: URL) async throws -> PackageCatalog
}

enum PackageScanError: LocalizedError {
    case invalidExtension
    case nativeEngineUnavailable
    case extractionFailed(String)
    case geodatabaseNotFound

    var errorDescription: String? {
        switch self {
        case .invalidExtension:
            return "Hãy chọn file có phần mở rộng .ppkx."
        case .nativeEngineUnavailable:
            return "GIS engine native chưa được tích hợp trong bản PoC này."
        case let .extractionFailed(message):
            return "Không thể giải nén PPKX: \(message)"
        case .geodatabaseNotFound:
            return "Package không chứa File Geodatabase (.gdb)."
        }
    }
}

struct DefaultPackageScanner: PackageScanning {
    func scan(packageURL: URL) async throws -> PackageCatalog {
        if NativeGeodatabaseReader().isAvailable {
            return try await NativePackageScanner().scan(packageURL: packageURL)
        }
        return try await MockPackageScanner().scan(packageURL: packageURL)
    }
}

/// A package that has been copied into the sandbox, unpacked and catalogued. The
/// extracted geodatabases stay on disk so the clip engine can reuse them; the
/// caller must delete `jobDirectory` when finished.
struct PreparedPackage: Sendable {
    let catalog: PackageCatalog
    let geodatabaseURLs: [URL]
    let jobDirectory: URL
}

struct NativePackageScanner: PackageScanning {
    func scan(packageURL: URL) async throws -> PackageCatalog {
        let prepared = try await prepare(packageURL: packageURL)
        try? FileManager.default.removeItem(at: prepared.jobDirectory)
        return prepared.catalog
    }

    /// Streaming copy → unpack → discover `.gdb` → read catalog, keeping the
    /// extracted tree on disk. `onEvent` receives `{"event":"phase",...}` and
    /// `{"event":"extract",...}` events and can request cancellation.
    func prepare(
        packageURL: URL,
        onEvent: @escaping GISProgressBridge.Handler = { _ in false }
    ) async throws -> PreparedPackage {
        guard packageURL.pathExtension.lowercased() == "ppkx" else {
            throw PackageScanError.invalidExtension
        }
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let values = try packageURL.resourceValues(forKeys: [.fileSizeKey])
            let jobDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LandClipScans", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let archiveURL = jobDirectory.appendingPathComponent("package.ppkx")
            let extractedURL = jobDirectory.appendingPathComponent("extracted", isDirectory: true)
            try fileManager.createDirectory(at: extractedURL, withIntermediateDirectories: true)

            do {
                _ = onEvent(#"{"event":"phase","phase":"copy"}"#)
                try Task.checkCancellation()
                try Self.copyStreaming(from: packageURL, to: archiveURL)

                _ = onEvent(#"{"event":"phase","phase":"extract"}"#)
                try Task.checkCancellation()
                try Self.extract(packageURL: archiveURL, destinationURL: extractedURL, onEvent: onEvent)
                try? fileManager.removeItem(at: archiveURL)

                _ = onEvent(#"{"event":"phase","phase":"catalog"}"#)
                try Task.checkCancellation()
                let geodatabases = Self.findGeodatabases(in: extractedURL)
                guard !geodatabases.isEmpty else { throw PackageScanError.geodatabaseNotFound }
                let reader = NativeGeodatabaseReader()
                var layers: [LayerInfo] = []
                for geodatabase in geodatabases {
                    try Task.checkCancellation()
                    layers.append(contentsOf: try reader.read(gdbURL: geodatabase))
                }
                return PreparedPackage(
                    catalog: PackageCatalog(
                        packageName: packageURL.lastPathComponent,
                        packageSize: Int64(values.fileSize ?? 0),
                        layers: layers
                    ),
                    geodatabaseURLs: geodatabases,
                    jobDirectory: jobDirectory
                )
            } catch {
                try? fileManager.removeItem(at: jobDirectory)
                throw error
            }
        }.value
    }

    private static func copyStreaming(from source: URL, to destination: URL) throws {
        guard let input = InputStream(url: source), let output = OutputStream(url: destination, append: false) else {
            throw CocoaError(.fileReadUnknown)
        }
        input.open()
        output.open()
        defer { input.close(); output.close() }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024 * 1024)
        defer { buffer.deallocate() }
        while input.hasBytesAvailable {
            try Task.checkCancellation()
            let count = input.read(buffer, maxLength: 1024 * 1024)
            if count < 0 { throw input.streamError ?? CocoaError(.fileReadUnknown) }
            if count == 0 { break }
            var written = 0
            while written < count {
                let result = output.write(buffer.advanced(by: written), maxLength: count - written)
                if result <= 0 { throw output.streamError ?? CocoaError(.fileWriteUnknown) }
                written += result
            }
        }
    }

    private static func extract(
        packageURL: URL,
        destinationURL: URL,
        onEvent: @escaping GISProgressBridge.Handler = { _ in false }
    ) throws {
        let bridge = GISProgressBridge(onEvent)
        var nativeError: UnsafeMutablePointer<CChar>?
        let succeeded = packageURL.path.withCString { packagePath in
            destinationURL.path.withCString { destinationPath in
                landclip_archive_extract_ppkx(
                    packagePath, destinationPath,
                    GISProgressBridge.callback, bridge.context,
                    &nativeError
                )
            }
        }
        withExtendedLifetime(bridge) {}
        defer { landclip_gis_free_string(nativeError) }
        guard succeeded == 1 else {
            let message = nativeError.map { String(cString: $0) } ?? "Lỗi native không xác định."
            throw PackageScanError.extractionFailed(message)
        }
    }

    private static func findGeodatabases(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "gdb",
               (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                result.append(url)
                enumerator.skipDescendants()
            }
        }
        return result.sorted { $0.path < $1.path }
    }
}

struct MockPackageScanner: PackageScanning {
    func scan(packageURL: URL) async throws -> PackageCatalog {
        guard packageURL.pathExtension.lowercased() == "ppkx" else {
            throw PackageScanError.invalidExtension
        }
        let values = try packageURL.resourceValues(forKeys: [.fileSizeKey])
        try await Task.sleep(for: .milliseconds(350))
        return PackageCatalog(
            packageName: packageURL.lastPathComponent,
            packageSize: Int64(values.fileSize ?? 0),
            layers: []
        )
    }
}
