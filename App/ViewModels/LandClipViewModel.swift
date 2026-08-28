import Foundation
import CoreLocation

/// Thread-safe cancel signal shared with the native worker thread. `Task`
/// cancellation does not cross into `Task.detached`, so the C callbacks poll this.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

@MainActor
final class LandClipViewModel: ObservableObject {
    enum Stage: Equatable {
        case idle
        case preparing(String)
        case ready
        case clipping
        case done
        case failed(String)
    }

    struct Report: Equatable {
        var phase: String = ""
        var detail: String = ""
        var layersDone: Int = 0
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var progress = Report()
    @Published private(set) var catalog: PackageCatalog?
    @Published private(set) var result: ClipResult?
    /// AOI polygon vertices in WGS-84, in the order the user tapped them.
    @Published var aoiVertices: [CLLocationCoordinate2D] = []
    /// An imported AOI file (GeoJSON / GeoPackage); takes priority over `aoiVertices`.
    @Published private(set) var importedAOIName: String?

    private var importedAOIURL: URL?

    var engineAvailable: Bool { NativeGeodatabaseReader().isAvailable }
    var canDraw: Bool { (stage == .ready || stage == .done) && importedAOIURL == nil }
    var hasAOI: Bool { importedAOIURL != nil || aoiVertices.count >= 3 }
    var canClip: Bool {
        switch stage {
        case .ready, .done: return hasAOI
        default: return false
        }
    }

    func importAOI(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("imported-aoi-\(UUID().uuidString).\(url.pathExtension)")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            importedAOIURL = destination
            importedAOIName = url.lastPathComponent
            aoiVertices = []
        } catch {
            stage = .failed("Không đọc được file AOI: \(error.localizedDescription)")
        }
    }

    func clearImportedAOI() {
        if let url = importedAOIURL { try? FileManager.default.removeItem(at: url) }
        importedAOIURL = nil
        importedAOIName = nil
    }
    var supportedLayerCount: Int {
        (catalog?.layers ?? []).filter { LandClipViewModel.isSupported($0.geometryType) }.count
    }

    private var prepared: PreparedPackage?
    private var clipOutputDirectory: URL?
    private var worker: Task<Void, Never>?
    private var cancelFlag = CancelFlag()

    static func isSupported(_ geometryType: String) -> Bool {
        ["Point", "MultiPoint", "LineString", "MultiLineString", "Polygon", "MultiPolygon"]
            .contains(geometryType)
    }

    func openPackage(_ url: URL) {
        worker?.cancel()
        cancelFlag.cancel()
        cleanup()
        clearImportedAOI()
        catalog = nil
        result = nil
        aoiVertices = []
        progress = Report()
        stage = .preparing(url.lastPathComponent)

        let flag = CancelFlag()
        cancelFlag = flag
        worker = Task {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let prepared = try await NativePackageScanner().prepare(
                    packageURL: url,
                    onEvent: self.progressHandler(flag)
                )
                guard !flag.isCancelled else { self.stage = .idle; return }
                self.prepared = prepared
                self.catalog = prepared.catalog
                self.stage = .ready
            } catch is CancellationError {
                self.stage = .idle
            } catch {
                self.stage = flag.isCancelled ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    /// Builds a `@Sendable` progress handler that forwards events to the main
    /// actor and reports the shared cancel flag.
    private nonisolated func progressHandler(_ flag: CancelFlag) -> GISProgressBridge.Handler {
        { [weak self] json in
            Task { @MainActor [weak self] in self?.applyEvent(json) }
            return flag.isCancelled
        }
    }

    func runClip() {
        guard stage == .ready || stage == .done, let prepared, hasAOI else { return }
        progress = Report()
        result = nil
        stage = .clipping

        let vertices = aoiVertices
        let importedURL = importedAOIURL
        let geodatabaseURLs = prepared.geodatabaseURLs
        let flag = CancelFlag()
        cancelFlag = flag
        let handler = progressHandler(flag)

        worker = Task {
            do {
                let outputDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LandClipOutput-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                self.clipOutputDirectory = outputDirectory

                let aoiURL: URL
                if let importedURL {
                    aoiURL = importedURL
                } else {
                    aoiURL = outputDirectory.appendingPathComponent("aoi.geojson")
                    try LandClipViewModel.writeAOI(vertices, to: aoiURL)
                }

                let clipResult = try await Task.detached(priority: .userInitiated) {
                    try NativeClipEngine().clip(
                        gdbURLs: geodatabaseURLs,
                        aoiURL: aoiURL,
                        outputDirectory: outputDirectory,
                        onEvent: handler
                    )
                }.value

                guard !flag.isCancelled else { self.stage = .ready; return }
                self.result = clipResult
                self.stage = .done
            } catch let error as ClipEngineError {
                if case .cancelled = error { self.stage = .ready } else { self.stage = .failed(error.localizedDescription) }
            } catch {
                self.stage = flag.isCancelled ? .ready : .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        cancelFlag.cancel()
        worker?.cancel()
    }

    func reset() {
        worker?.cancel()
        cancelFlag.cancel()
        cleanup()
        clearImportedAOI()
        prepared = nil
        catalog = nil
        result = nil
        aoiVertices = []
        progress = Report()
        stage = .idle
    }

    private func applyEvent(_ json: String) {
        guard let event = GISProgressEvent.decode(json) else { return }
        switch event.event {
        case "phase":
            progress.phase = LandClipViewModel.phaseLabel(event.phase ?? "")
            progress.detail = ""
        case "extract":
            progress.phase = "Đang giải nén"
            if let entries = event.entriesDone { progress.detail = "\(entries) mục" }
        case "layer_start":
            progress.detail = [event.gdb, event.layer].compactMap { $0 }.joined(separator: " / ")
        case "layer_done":
            progress.layersDone += 1
            if let count = event.outputCount { progress.detail = "\(progress.detail) → \(count)" }
        case "complete":
            progress.phase = "Hoàn tất"
            progress.detail = ""
        default:
            break
        }
    }

    private static func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "copy": return "Đang sao chép package"
        case "extract": return "Đang giải nén"
        case "catalog": return "Đang lập danh mục layer"
        case "aoi": return "Đang đọc vùng AOI"
        case "process": return "Đang xử lý layer"
        default: return "Đang xử lý"
        }
    }

    /// Emits the AOI as a single WGS-84 GeoJSON polygon (ring auto-closed).
    static func writeAOI(_ vertices: [CLLocationCoordinate2D], to url: URL) throws {
        var ring: [[Double]] = vertices.map { [$0.longitude, $0.latitude] }
        if let first = ring.first, ring.last != first {
            ring.append(first)
        }
        let feature: [String: Any] = [
            "type": "Feature",
            "properties": [String: Any](),
            "geometry": ["type": "Polygon", "coordinates": [ring]] as [String: Any],
        ]
        let geoJSON: [String: Any] = [
            "type": "FeatureCollection",
            "crs": ["type": "name",
                    "properties": ["name": "urn:ogc:def:crs:OGC:1.3:CRS84"]] as [String: Any],
            "features": [feature],
        ]
        let data = try JSONSerialization.data(withJSONObject: geoJSON, options: [.prettyPrinted])
        try data.write(to: url, options: .atomic)
    }

    private func cleanup() {
        if let directory = prepared?.jobDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        if let directory = clipOutputDirectory {
            try? FileManager.default.removeItem(at: directory)
            clipOutputDirectory = nil
        }
    }

    deinit {
        if let directory = prepared?.jobDirectory { try? FileManager.default.removeItem(at: directory) }
        if let directory = clipOutputDirectory { try? FileManager.default.removeItem(at: directory) }
    }
}
