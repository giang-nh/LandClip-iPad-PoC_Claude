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

    struct LiveRow: Identifiable, Equatable {
        var id: String { "\(gdb)::\(layer)" }
        let gdb: String
        let layer: String
        var geometryType: String = ""
        var sourceCount: Int = 0
        var candidateCount: Int = 0
        var outputCount: Int = 0
        var status: String = "running"
    }
    @Published private(set) var liveRows: [LiveRow] = []

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var progress = Report()
    @Published private(set) var catalog: PackageCatalog?
    @Published private(set) var result: ClipResult?
    /// A partially-finished (cancelled) result the next run can resume from.
    @Published private(set) var partialResult: ClipResult?
    /// When true, the next run ignores `partialResult` and starts over.
    @Published var restartFromScratch = false

    private static let processorVersion = "1"
    private var lastRunSignature: String?

    var canResume: Bool { partialResult != nil && !restartFromScratch }
    enum DrawMode { case polygon, rectangle }
    @Published var drawMode: DrawMode = .polygon
    /// AOI polygon vertices in WGS-84, in the order the user tapped them.
    @Published var aoiVertices: [CLLocationCoordinate2D] = []
    /// First corner while drawing a rectangle.
    @Published var rectangleAnchor: CLLocationCoordinate2D?

    func deleteVertex(at index: Int) {
        guard aoiVertices.indices.contains(index) else { return }
        aoiVertices.remove(at: index)
    }

    /// Places a rectangle AOI from two opposite corners.
    func setRectangle(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) {
        let minLat = min(a.latitude, b.latitude), maxLat = max(a.latitude, b.latitude)
        let minLon = min(a.longitude, b.longitude), maxLon = max(a.longitude, b.longitude)
        aoiVertices = [
            .init(latitude: minLat, longitude: minLon),
            .init(latitude: minLat, longitude: maxLon),
            .init(latitude: maxLat, longitude: maxLon),
            .init(latitude: maxLat, longitude: minLon),
        ]
        rectangleAnchor = nil
    }

    func clearAOIDrawing() {
        aoiVertices.removeAll()
        rectangleAnchor = nil
    }
    /// An imported AOI file (GeoJSON / GeoPackage); takes priority over `aoiVertices`.
    @Published private(set) var importedAOIName: String?
    /// Supported layer keys the user has excluded (empty = process all).
    @Published var deselectedLayerKeys: Set<String> = []

    private var importedAOIURL: URL?

    /// `gdb::layer` keys of supported layers.
    var supportedLayerKeys: [String] {
        (catalog?.layers ?? [])
            .filter { LandClipViewModel.isSupported($0.geometryType) }
            .map { "\($0.geodatabase.replacingOccurrences(of: ".gdb", with: ""))::\($0.name)" }
    }
    /// Keys to actually process; empty means "all supported" (engine default).
    var selectedLayerKeys: [String] {
        let selected = supportedLayerKeys.filter { !deselectedLayerKeys.contains($0) }
        return selected.count == supportedLayerKeys.count ? [] : selected
    }
    var selectedLayerCount: Int {
        supportedLayerKeys.count - deselectedLayerKeys.filter { supportedLayerKeys.contains($0) }.count
    }

    func toggleLayer(_ key: String) {
        if deselectedLayerKeys.contains(key) { deselectedLayerKeys.remove(key) }
        else { deselectedLayerKeys.insert(key) }
    }
    func selectAllLayers() { deselectedLayerKeys.removeAll() }
    func deselectAllLayers() { deselectedLayerKeys = Set(supportedLayerKeys) }

    var engineAvailable: Bool { NativeGeodatabaseReader().isAvailable }
    var canDraw: Bool { (stage == .ready || stage == .done) && importedAOIURL == nil }
    var hasAOI: Bool { importedAOIURL != nil || aoiVertices.count >= 3 }
    var canClip: Bool {
        switch stage {
        case .ready, .done: return hasAOI && selectedLayerCount > 0
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

    /// Synthetic package bundled with the app for the DEBUG quick-try shortcut.
    static var bundledSamplePackage: URL? {
        Bundle.main.url(forResource: "sample", withExtension: "ppkx", subdirectory: "public")
            ?? Bundle.main.url(forResource: "sample", withExtension: "ppkx")
    }

    static var bundledSampleAOI: URL? {
        Bundle.main.url(forResource: "sample-aoi", withExtension: "geojson", subdirectory: "public")
            ?? Bundle.main.url(forResource: "sample-aoi", withExtension: "geojson")
    }

    /// DEBUG shortcut: open the bundled package and, once ready, load the
    /// matching bundled AOI so the clip produces real results without any
    /// file picking.
    func openDemo() {
        guard let package = LandClipViewModel.bundledSamplePackage else { return }
        pendingDemoAOI = LandClipViewModel.bundledSampleAOI
        openPackage(package)
    }

    private var pendingDemoAOI: URL?

    func openPackage(_ url: URL) {
        worker?.cancel()
        cancelFlag.cancel()
        cleanup()
        clearImportedAOI()
        catalog = nil
        result = nil
        aoiVertices = []
        deselectedLayerKeys = []
        partialResult = nil
        lastRunSignature = nil
        restartFromScratch = false
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
                if let demoAOI = self.pendingDemoAOI {
                    self.pendingDemoAOI = nil
                    self.importAOI(demoAOI)
                }
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
        liveRows = []
        result = nil
        stage = .clipping

        let vertices = aoiVertices
        let importedURL = importedAOIURL
        let geodatabaseURLs = prepared.geodatabaseURLs
        let flag = CancelFlag()
        cancelFlag = flag
        let handler = progressHandler(flag)

        let signature = runSignature()
        let resuming = canResume && lastRunSignature == signature && clipOutputDirectory != nil
        let priorPartial = resuming ? partialResult : nil
        let skip = priorPartial?.completedLayerKeys ?? []
        let selected = self.selectedLayerKeys

        worker = Task {
            do {
                let outputDirectory: URL
                if resuming, let existing = self.clipOutputDirectory {
                    outputDirectory = existing
                } else {
                    outputDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("LandClipOutput-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                    self.clipOutputDirectory = outputDirectory
                }

                let aoiURL: URL
                if let importedURL {
                    aoiURL = importedURL
                } else {
                    aoiURL = outputDirectory.appendingPathComponent("aoi.geojson")
                    try LandClipViewModel.writeAOI(vertices, to: aoiURL)
                }

                var clipResult = try await Task.detached(priority: .userInitiated) {
                    try NativeClipEngine().clip(
                        gdbURLs: geodatabaseURLs,
                        aoiURL: aoiURL,
                        outputDirectory: outputDirectory,
                        selectedLayers: selected,
                        skipLayers: skip,
                        resume: resuming,
                        onEvent: handler
                    )
                }.value

                if let priorPartial {
                    clipResult = clipResult.merging(reusedFrom: priorPartial)
                    clipResult.rewriteCSV()
                }
                self.lastRunSignature = signature

                if clipResult.cancelled {
                    self.partialResult = clipResult
                    self.stage = .ready
                    self.progress.phase = "Đã dừng — còn "
                        + "\(self.selectedLayerCount - clipResult.completedLayerKeys.count)/\(self.selectedLayerCount) layer"
                } else {
                    self.partialResult = nil
                    self.restartFromScratch = false
                    self.result = clipResult
                    self.stage = .done
                }
            } catch {
                self.stage = flag.isCancelled ? .ready : .failed(error.localizedDescription)
            }
        }
    }

    /// Identifies an input configuration for resume: same package + AOI + layer
    /// selection + engine version means a stop can be continued.
    private func runSignature() -> String {
        let aoiPart: String
        if let name = importedAOIName {
            aoiPart = "file:\(name)"
        } else {
            aoiPart = aoiVertices
                .map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }
                .joined(separator: ";")
        }
        return [
            catalog?.packageName ?? "",
            aoiPart,
            selectedLayerKeys.sorted().joined(separator: ","),
            LandClipViewModel.processorVersion,
        ].joined(separator: "|")
    }

    func cancel() {
        cancelFlag.cancel()
        worker?.cancel()
    }

    /// Discard the partial result so the next run reprocesses everything.
    func startOver() {
        partialResult = nil
        lastRunSignature = nil
        restartFromScratch = false
        if let directory = clipOutputDirectory {
            try? FileManager.default.removeItem(at: directory)
            clipOutputDirectory = nil
        }
    }

    func reset() {
        worker?.cancel()
        cancelFlag.cancel()
        cleanup()
        clearImportedAOI()
        pendingDemoAOI = nil
        prepared = nil
        catalog = nil
        result = nil
        aoiVertices = []
        deselectedLayerKeys = []
        partialResult = nil
        lastRunSignature = nil
        restartFromScratch = false
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
            if let gdb = event.gdb, let layer = event.layer {
                var row = LiveRow(gdb: gdb, layer: layer)
                row.geometryType = event.geometryType ?? ""
                row.sourceCount = event.sourceCount ?? 0
                liveRows.removeAll { $0.id == row.id }
                liveRows.append(row)
            }
        case "layer_done":
            progress.layersDone += 1
            if let count = event.outputCount { progress.detail = "\(progress.detail) → \(count)" }
            if let gdb = event.gdb, let layer = event.layer,
               let idx = liveRows.firstIndex(where: { $0.id == "\(gdb)::\(layer)" }) {
                liveRows[idx].candidateCount = event.candidateCount ?? liveRows[idx].candidateCount
                liveRows[idx].outputCount = event.outputCount ?? liveRows[idx].outputCount
                liveRows[idx].status = event.status ?? "done"
            }
        case "complete":
            progress.phase = "Hoàn tất"
            progress.detail = ""
        case "cancelled":
            progress.phase = "Đã dừng"
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
